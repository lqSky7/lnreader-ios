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
    /// The server timestamp this upload is based on.
    ///
    /// The backend compares it with its own `updatedAt` and answers 409 when its
    /// copy is newer, which is what makes the server authoritative instead of
    /// whichever device happened to push last. Omitted on a device that has
    /// never synced, which the backend treats as a legacy write.
    var clientUpdatedAt: String?
}

private struct SyncEnvelope: Decodable {
    let user: AuthenticatedUser
    let data: RemoteSyncData?
}

private struct RemoteSyncData: Decodable {
    let profile: SyncProfilePayload
    let library: [SyncNovelPayload]
    let sources: [SyncSourcePayload]
    /// When the server last accepted a write. Absent on older backends.
    let updatedAt: String?
}

/// `PUT /api/sync` success body.
private struct PushResult: Decodable {
    let ok: Bool
    let updatedAt: String?
}

/// `PUT /api/sync` 409 body: the write was stale, and this is the copy that won.
private struct ConflictBody: Decodable {
    let error: String
    let serverUpdatedAt: String
    let data: RemoteSyncData
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

    // MARK: - Sync position

    /// Whether this account has a sync position on this device.
    ///
    /// Stored rather than derived from `lastSyncedAt`, because `@Observable`
    /// only tracks stored properties and the position lives in `UserDefaults`.
    private(set) var hasSynced = false

    /// The server's `updatedAt` from the last write or pull this device accepted.
    ///
    /// Sent back as `clientUpdatedAt` so the backend can tell whether this device
    /// is working from the current copy or from a stale one. Kept per account so
    /// signing into a different account cannot inherit another user's position.
    private var lastSyncedAt: Date? {
        get {
            guard let key = lastSyncedKey else { return nil }
            return UserDefaults.standard.object(forKey: key) as? Date
        }
        set {
            guard let key = lastSyncedKey else { return }
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
            hasSynced = newValue != nil
        }
    }

    /// Re-read the position after `currentUser` changes, since the key is per account.
    private func refreshSyncPosition() {
        hasSynced = lastSyncedAt != nil
    }

    private var lastSyncedKey: String? {
        currentUser.map { "sync.lastSyncedAt.\($0.id)" }
    }

    /// The backend writes `Date.toISOString()`, which always carries milliseconds.
    private static let wireFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func wireTimestamp(_ date: Date) -> String {
        wireFormatter.string(from: date)
    }

    private static func date(fromWire value: String?) -> Date? {
        guard let value else { return nil }
        return wireFormatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    func loadSession() async {
        do {
            let envelope: SyncEnvelope = try await request(path: "/api/sync", method: "GET")
            currentUser = envelope.user
            refreshSyncPosition()
            lastError = nil
        } catch {
            currentUser = nil
            refreshSyncPosition()
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
            refreshSyncPosition()
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

    /// Upload the library, deferring to the server when it holds newer data.
    ///
    /// The server is the source of truth: a write based on a copy the server has
    /// since replaced is rejected, and the server's version is applied here
    /// instead of being overwritten. A device that has never synced also refuses
    /// to replace a populated server document with an empty one.
    func push(profile: UserProfile, entries: [Entry], sources: [any CatalogSource], context: ModelContext) async {
        let library = entries.filter { $0.inLibrary && !$0.isLocal }

        if library.isEmpty, lastSyncedAt == nil, await serverHasData() {
            await pull(into: context, force: false)
            return
        }

        let payload = SyncPayload(
            profile: SyncProfilePayload(
                username: currentUser?.username,
                email: currentUser?.email,
                name: profile.name,
                image: profile.avatarData?.base64EncodedString()
            ),
            library: library.map { SyncNovelPayload(entry: $0) },
            sources: sources.map { SyncSourcePayload(source: $0) },
            clientUpdatedAt: lastSyncedAt.map(Self.wireTimestamp)
        )

        var tookServerCopy = false

        await run("Synced to backend") {
            do {
                let data = try await requestRaw(
                    path: "/api/sync",
                    method: "PUT",
                    bodyData: try JSONEncoder().encode(payload)
                )
                if let result = try? JSONDecoder().decode(PushResult.self, from: data),
                   let syncedAt = Self.date(fromWire: result.updatedAt) {
                    lastSyncedAt = syncedAt
                }
            } catch SyncError.conflict(let body) {
                // Someone wrote after this device last read. Applying the winning
                // copy loses nothing that the server does not already hold.
                try apply(data: body.data, context: context)
                if let syncedAt = Self.date(fromWire: body.serverUpdatedAt) {
                    lastSyncedAt = syncedAt
                }
                tookServerCopy = true
            }
        }

        if tookServerCopy {
            lastMessage = "Backend had newer data, so its copy was applied here"
        }
    }

    /// True when the account already has a document on the server.
    private func serverHasData() async -> Bool {
        struct Meta: Decodable { let updatedAt: String? }
        guard let meta: Meta = try? await request(path: "/api/sync/meta", method: "GET") else { return false }
        return meta.updatedAt != nil
    }

    /// Apply the server's copy when it is newer than the one this device has.
    ///
    /// `force` ignores that comparison, for an explicit "Restore" tap. `quiet`
    /// swallows failures, for the launch path where a network error must not
    /// surface as an error banner or block the app.
    @discardableResult
    func pull(into context: ModelContext, force: Bool = false, quiet: Bool = false) async -> Bool {
        if quiet {
            return (try? await performPull(into: context, force: force)) ?? false
        }

        var applied = false
        await run("Restored backend data") {
            applied = try await performPull(into: context, force: force)
        }
        return applied
    }

    private func performPull(into context: ModelContext, force: Bool) async throws -> Bool {
        let envelope: SyncEnvelope = try await request(path: "/api/sync", method: "GET")
        currentUser = envelope.user
        refreshSyncPosition()

        guard let data = envelope.data else { return false }

        let serverAt = Self.date(fromWire: data.updatedAt)
        if !force, let serverAt, let lastSyncedAt, serverAt <= lastSyncedAt {
            return false
        }

        try apply(data: data, context: context)
        lastSyncedAt = serverAt
        return true
    }

    /// Pull regardless of position. The explicit "Restore" action.
    func restore(into context: ModelContext) async {
        await pull(into: context, force: true)
    }

    /// The wire format carries genres as one comma-separated string.
    private static func splitGenres(_ raw: String?) -> [String] {
        guard let raw else { return [] }
        return raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
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
            // The wire format still calls the source id `pluginId`; v2 stores the prefixed source key.
            let sourceKey = SourceKey.makeBuiltin(id: remoteNovel.pluginId)
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
            novel.genres = Self.splitGenres(remoteNovel.genres)
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

    @discardableResult
    private func run(_ successMessage: String, operation: () async throws -> Void) async -> Bool {
        isWorking = true
        lastError = nil
        defer { isWorking = false }

        do {
            try await operation()
            lastMessage = successMessage
            return true
        } catch {
            lastError = error.localizedDescription
            return false
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
        guard let http = response as? HTTPURLResponse else {
            throw SyncError.requestFailed("No response from the backend")
        }
        guard 200..<300 ~= http.statusCode else {
            // 409 carries the copy that won, so the caller can adopt it instead
            // of retrying the write.
            if http.statusCode == 409, let conflict = try? JSONDecoder().decode(ConflictBody.self, from: data) {
                throw SyncError.conflict(conflict)
            }
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
    /// The server rejected a stale write and returned the copy that won.
    case conflict(ConflictBody)

    var errorDescription: String? {
        switch self {
        case .requestFailed(let message): message
        case .conflict(let body): body.error
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
    init(source: any CatalogSource) {
        self.id = SourceKey.identifier(from: source.key)
        self.name = source.name
        self.site = ""
        self.lang = source.lang
        self.version = "native"
        self.url = ""
        self.iconUrl = source.iconURL ?? ""
    }
}
