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

    var backendURL: String = UserDefaults.standard.string(forKey: "sync.backendURL") ?? "https://lnreader-sync-sky788.azurewebsites.net"

    private var baseURL: URL {
        URL(string: backendURL.trimmingCharacters(in: .whitespacesAndNewlines)) ?? URL(string: "https://lnreader-sync-sky788.azurewebsites.net")!
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

    func push(profile: UserProfile, novels: [Novel], sources: [PluginListItem]) async {
        let payload = SyncPayload(
            profile: SyncProfilePayload(
                username: currentUser?.username,
                email: currentUser?.email,
                name: profile.name,
                image: profile.avatarData?.base64EncodedString()
            ),
            library: novels.filter { $0.inLibrary && !$0.isLocal }.map { SyncNovelPayload(novel: $0) },
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
            let path = remoteNovel.path
            let pluginId = remoteNovel.pluginId
            let predicate = #Predicate<Novel> { $0.path == path && $0.pluginId == pluginId }
            let existing = try context.fetch(FetchDescriptor(predicate: predicate)).first
            let novel = existing ?? Novel(path: remoteNovel.path, pluginId: remoteNovel.pluginId, name: remoteNovel.name)
            if existing == nil {
                context.insert(novel)
            }

            novel.name = remoteNovel.name
            novel.cover = remoteNovel.cover
            novel.summary = remoteNovel.summary
            novel.author = remoteNovel.author
            novel.artist = remoteNovel.artist
            novel.status = NovelStatus(rawValue: remoteNovel.status) ?? .unknown
            novel.genres = remoteNovel.genres
            novel.inLibrary = remoteNovel.inLibrary
            novel.totalPages = remoteNovel.totalPages
            novel.libraryPosition = remoteNovel.libraryPosition

            var existingChapters: [String: Chapter] = [:]
            for chapter in novel.chapters {
                existingChapters[chapter.path] = chapter
            }
            for remoteChapter in remoteNovel.chapters {
                let chapter = existingChapters[remoteChapter.path] ?? Chapter(path: remoteChapter.path, name: remoteChapter.name)
                if chapter.novel == nil {
                    chapter.novel = novel
                    context.insert(chapter)
                }
                chapter.name = remoteChapter.name
                chapter.releaseTime = remoteChapter.releaseTime
                chapter.bookmark = remoteChapter.bookmark
                chapter.unread = remoteChapter.unread
                chapter.isDownloaded = remoteChapter.isDownloaded
                chapter.chapterNumber = remoteChapter.chapterNumber
                chapter.page = remoteChapter.page
                chapter.position = remoteChapter.position
                chapter.progress = remoteChapter.progress
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
    init(novel: Novel) {
        self.path = novel.path
        self.pluginId = novel.pluginId
        self.name = novel.name
        self.cover = novel.cover
        self.summary = novel.summary
        self.author = novel.author
        self.artist = novel.artist
        self.status = novel.status.rawValue
        self.genres = novel.genres
        self.inLibrary = novel.inLibrary
        self.totalPages = novel.totalPages
        self.libraryPosition = novel.libraryPosition
        self.chapters = novel.chapters.sorted { $0.position < $1.position }.map { SyncChapterPayload(chapter: $0) }
    }
}

extension SyncChapterPayload {
    init(chapter: Chapter) {
        self.path = chapter.path
        self.name = chapter.name
        self.releaseTime = chapter.releaseTime
        self.bookmark = chapter.bookmark
        self.unread = chapter.unread
        self.isDownloaded = chapter.isDownloaded
        self.chapterNumber = chapter.chapterNumber
        self.page = chapter.page
        self.position = chapter.position
        self.progress = chapter.progress
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
