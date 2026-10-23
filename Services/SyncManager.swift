import Foundation
import Observation
import SwiftData

struct AuthenticatedUser: Codable, Equatable {
    let id: String
    let name: String?
    let email: String?
    let image: String?
    let username: String?
    let displayUsername: String?
}

struct SyncProfilePayload: Codable {
    var username: String?
    var email: String?
    var name: String?
    var image: String?
}

struct SyncChapterPayload: Codable {
    var path: String
    var name: String
    var releaseTime: String?
    var bookmark: Bool
    var unread: Bool
    var isDownloaded: Bool
    var chapterNumber: Double?
    var page: String
    var position: Int
    var progress: Int?
    var lastReadParagraphIndex: Int?
}

struct SyncNovelPayload: Codable {
    var path: String
    var pluginId: String
    var name: String
    var cover: String?
    var summary: String?
    var author: String?
    var artist: String?
    var status: String
    var genres: String?
    var inLibrary: Bool
    var totalPages: Int
    var libraryPosition: Int
    var chapters: [SyncChapterPayload]
}

struct SyncSourcePayload: Codable {
    var id: String
    var name: String
    var site: String
    var lang: String
    var version: String
    var url: String
    var iconUrl: String
}

struct SyncPayload: Codable {
    var profile: SyncProfilePayload
    var library: [SyncNovelPayload]
    var sources: [SyncSourcePayload]
}

private struct SyncEnvelope: Decodable {
    let user: AuthenticatedUser
    let data: RemoteSyncData?
}

private struct RemoteSyncData: Decodable {
    let profile: SyncProfilePayload
    let library: [SyncNovelPayload]
    let sources: [SyncSourcePayload]
}

@Observable
@MainActor
final class SyncManager {
    var currentUser: AuthenticatedUser?
    var isWorking = false
    var lastMessage: String?
    var lastError: String?

    var backendURL: String = UserDefaults.standard.string(forKey: "sync.backendURL") ?? SyncManager.defaultBackendURL

    static let defaultBackendURL = "https://lnreader.traverses.dpdns.org"
    /// Retired Azure backend — existing installs still have this saved.
    private static let legacyBackendURL = "https://lnreader-sync-sky788.azurewebsites.net"

    init() {
        // One-time migration off the retired Azure backend.
        if backendURL == Self.legacyBackendURL || backendURL == "https://lnreader-sync.onrender.com" {
            backendURL = Self.defaultBackendURL
            UserDefaults.standard.set(backendURL, forKey: "sync.backendURL")
        }
    }

    private var baseURL: URL {
        URL(string: backendURL.trimmingCharacters(in: .whitespacesAndNewlines)) ?? URL(string: SyncManager.defaultBackendURL)!
    }

    func updateBackendURL(_ value: String) {
        backendURL = value
        UserDefaults.standard.set(value, forKey: "sync.backendURL")
    }

    func loadSession() async {
        do {
            let envelope: SyncEnvelope = try await request(path: "/api/sync", method: "GET")
            currentUser = envelope.user
            lastError = nil
        } catch {
            currentUser = nil
        }
    }

    func signIn(identifier: String, password: String) async {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = trimmed.contains("@") ? "/api/auth/sign-in/email" : "/api/auth/sign-in/username"
        let body: [String: Any] = trimmed.contains("@")
            ? ["email": trimmed, "password": password, "rememberMe": true]
            : ["username": trimmed, "password": password]

        await run("Signed in") {
            try await requestRaw(path: path, method: "POST", bodyData: try jsonData(body))
            await loadSession()
        }
    }

    func register(username: String, email: String, password: String) async {
        let cleanUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let body: [String: Any] = [
            "name": cleanUsername.isEmpty ? email : cleanUsername,
            "email": email.trimmingCharacters(in: .whitespacesAndNewlines),
            "password": password,
            "username": cleanUsername,
            "displayUsername": cleanUsername,
        ]

        await run("Account created") {
            try await requestRaw(path: "/api/auth/sign-up/email", method: "POST", bodyData: try jsonData(body))
            await loadSession()
        }
    }

    func signOut() async {
        await run("Signed out") {
            try await requestRaw(path: "/api/auth/sign-out", method: "POST", bodyData: try jsonData([String: String]()))
            currentUser = nil
        }
    }

    func requestPasswordReset(email: String) async {
        await run("Password reset email requested") {
            try await requestRaw(
                path: "/api/auth/request-password-reset",
                method: "POST",
                bodyData: try jsonData([
                    "email": email.trimmingCharacters(in: .whitespacesAndNewlines),
                    "redirectTo": "lnreader://reset-password",
                ])
            )
        }
    }

    func resetPassword(token: String, newPassword: String) async {
        await run("Password reset") {
            try await requestRaw(
                path: "/api/auth/reset-password",
                method: "POST",
                bodyData: try jsonData([
                    "token": token.trimmingCharacters(in: .whitespacesAndNewlines),
                    "newPassword": newPassword,
                ])
            )
        }
    }

    func push(profile: UserProfile, entries: [Entry], sources: [PluginListItem]) async {
        let payload = SyncPayload(
            profile: SyncProfilePayload(
                username: currentUser?.username,
                email: currentUser?.email,
                name: profile.name,
                image: profile.avatarData?.base64EncodedString()
            ),
            library: entries.filter { $0.inLibrary && !$0.isLocal }.map { SyncNovelPayload(entry: $0) },
            sources: sources.map { SyncSourcePayload(plugin: $0) }
        )

        await run("Synced to backend") {
            try await requestRaw(path: "/api/sync", method: "PUT", bodyData: try JSONEncoder().encode(payload))
        }
    }

    func restore(into context: ModelContext, pluginManager: PluginManager) async {
        await run("Restored backend data") {
            let envelope: SyncEnvelope = try await request(path: "/api/sync", method: "GET")
            currentUser = envelope.user
            guard let data = envelope.data else { return }

            try await pluginManager.installSyncedSources(data.sources)
            try apply(data: data, context: context)
        }
    }

    private func apply(data: RemoteSyncData, context: ModelContext) throws {
        let profiles = try context.fetch(FetchDescriptor<UserProfile>())
        let profile = profiles.first ?? UserProfile()
        if profiles.isEmpty {
            context.insert(profile)
        }
        if let name = data.profile.name, !name.isEmpty {
            profile.name = name
        }
        if let image = data.profile.image {
            profile.avatarData = Data(base64Encoded: image)
        }

        for remoteNovel in data.library {
            // The wire format still uses the v1 `pluginId`; v2 stores the
            // prefixed source key.
            let sourceKey = SourceKey.make(kind: .novel, id: remoteNovel.pluginId)
            let path = remoteNovel.path
            let predicate = #Predicate<Entry> { $0.url == path && $0.sourceKey == sourceKey }
            let existing = try context.fetch(FetchDescriptor(predicate: predicate)).first
            let novel = existing
                ?? Entry(kind: .novel, sourceKey: sourceKey, url: remoteNovel.path, title: remoteNovel.name)
            if existing == nil {
                context.insert(novel)
            }

            novel.title = remoteNovel.name
            novel.thumbnailURL = remoteNovel.cover
            novel.summary = remoteNovel.summary
            novel.author = remoteNovel.author
            novel.artist = remoteNovel.artist
            novel.status = EntryStatus.parse(remoteNovel.status)
            novel.genres = LNPluginSource.splitGenres(remoteNovel.genres)
            novel.inLibrary = remoteNovel.inLibrary
            novel.libraryOrder = remoteNovel.libraryPosition

            var existingChapters: [String: Chapter] = [:]
            for chapter in novel.chapters {
                existingChapters[chapter.url] = chapter
            }
            for remoteChapter in remoteNovel.chapters {
                let chapter = existingChapters[remoteChapter.path]
                    ?? Chapter(url: remoteChapter.path, name: remoteChapter.name)
                if chapter.entry == nil {
                    chapter.entry = novel
                    context.insert(chapter)
                }
                chapter.name = remoteChapter.name
                chapter.dateUpload = DateParsing.parse(remoteChapter.releaseTime)
                chapter.bookmark = remoteChapter.bookmark
                chapter.read = !remoteChapter.unread
                // Download availability is verified from local files, never copied from another device.
                chapter.chapterNumber = remoteChapter.chapterNumber ?? -1
                chapter.sourceOrder = remoteChapter.position
                chapter.progress = Double(remoteChapter.progress ?? 0)
                chapter.paragraphIndex = remoteChapter.lastReadParagraphIndex
            }
        }

        try context.save()
    }

    private func run(_ successMessage: String, operation: () async throws -> Void) async {
        isWorking = true
        lastError = nil
        defer { isWorking = false }

        do {
            try await operation()
            lastMessage = successMessage
        } catch {
            lastError = error.localizedDescription
        }
    }

    @discardableResult
    private func request<T: Decodable>(path: String, method: String) async throws -> T {
        let data = try await requestRaw(path: path, method: method, bodyData: nil)
        return try JSONDecoder().decode(T.self, from: data)
    }

    @discardableResult
    private func requestRaw(path: String, method: String, bodyData: Data?) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        if let scheme = baseURL.scheme, let host = baseURL.host {
            var origin = "\(scheme)://\(host)"
            if let port = baseURL.port {
                origin += ":\(port)"
            }
            request.setValue(origin, forHTTPHeaderField: "Origin")
        }
        
        if let bodyData {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = bodyData
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            let message = String(data: data, encoding: .utf8) ?? "Request failed"
            throw SyncError.requestFailed(message)
        }
        return data
    }

    private func jsonData(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }
}

private enum SyncError: LocalizedError {
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .requestFailed(let message): message
        }
    }
}

extension SyncNovelPayload {
    /// Maps a v2 entry onto the v1 wire format the backend still stores.
    init(entry: Entry) {
        self.path = entry.url
        self.pluginId = SourceKey.identifier(from: entry.sourceKey)
        self.name = entry.title
        self.cover = entry.thumbnailURL
        self.summary = entry.summary
        self.author = entry.author
        self.artist = entry.artist
        self.status = entry.status.legacyRawValue
        self.genres = entry.genres.isEmpty ? nil : entry.genres.joined(separator: ", ")
        self.inLibrary = entry.inLibrary
        // v1 field: only LN plugins paginate their chapter lists.
        self.totalPages = 0
        self.libraryPosition = entry.libraryOrder
        self.chapters = entry.chapters
            .sorted { $0.sourceOrder < $1.sourceOrder }
            .map { SyncChapterPayload(chapter: $0) }
    }
}

extension SyncChapterPayload {
    init(chapter: Chapter) {
        self.path = chapter.url
        self.name = chapter.name
        self.releaseTime = chapter.dateUpload?.formatted
        self.bookmark = chapter.bookmark
        self.unread = !chapter.read
        self.isDownloaded = chapter.isDownloaded
        self.chapterNumber = chapter.chapterNumber >= 0 ? chapter.chapterNumber : nil
        self.page = "1"
        self.position = chapter.sourceOrder
        self.progress = chapter.progress > 0 ? Int(chapter.progress) : nil
        self.lastReadParagraphIndex = chapter.paragraphIndex
    }
}

private extension EntryStatus {
    /// The v1 status names, which is what other clients still parse.
    var legacyRawValue: String {
        switch self {
        case .unknown: "Unknown"
        case .ongoing: "Ongoing"
        case .completed: "Completed"
        case .licensed: "Licensed"
        case .publishingFinished: "Publishing Finished"
        case .cancelled: "Cancelled"
        case .onHiatus: "On Hiatus"
        }
    }
}

extension SyncSourcePayload {
    init(plugin: PluginListItem) {
        self.id = plugin.id
        self.name = plugin.name
        self.site = plugin.site
        self.lang = plugin.lang
        self.version = plugin.version
        self.url = plugin.url
        self.iconUrl = plugin.iconUrl
    }
}
