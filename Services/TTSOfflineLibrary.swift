import AVFoundation
import Combine
import CryptoKit
import Foundation

// Explicit downloads live in Application Support and are never automatically evicted.
enum TTSStorage {
    static var root: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LNReaderAudio", isDirectory: true) }
    static func directory(_ id: String) -> URL { root.appendingPathComponent(id, isDirectory: true) }
    static func audio(_ id: String) -> URL { directory(id).appendingPathComponent("audio.m4a") }
    static func validID(_ id: String) -> Bool { id.count == 64 && id.allSatisfy(\.isHexDigit) }
    static func chapterText(bookId: String, chapterId: String) -> URL {
        let id = SHA256.hash(data: Data((bookId + "\u{0}" + chapterId).utf8)).map { String(format: "%02x", $0) }.joined()
        return root.appendingPathComponent("chapters", isDirectory: true).appendingPathComponent(id + ".json")
    }
    static func verify(staged: URL, manifest: TTSManifest) async throws {
        try manifest.validate()
        let valid = try await Task.detached(priority: .utility) {
            let handle = try FileHandle(forReadingFrom: staged)
            defer { try? handle.close() }
            var hash = SHA256(), size: Int64 = 0
            while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty { hash.update(data: data); size += Int64(data.count) }
            return size == manifest.audioBytes && hash.finalize().map { String(format: "%02x", $0) }.joined() == manifest.audioSHA256
        }.value
        guard valid else { throw TTSError.corruptDownload }
        let actual = try await AVURLAsset(url: staged).load(.duration).seconds
        guard actual.isFinite, abs(actual - manifest.duration) < 0.25 else { throw TTSError.corruptDownload }
    }
    static func commit(staged: URL, manifest: TTSManifest) throws {
        let folder = directory(manifest.id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var safeManifest = manifest; safeManifest.audioURL = nil
        try JSONEncoder().encode(safeManifest).write(to: folder.appendingPathComponent("manifest.json"), options: .atomic)
        let textPath = chapterText(bookId: manifest.bookId, chapterId: manifest.chapterId)
        try FileManager.default.createDirectory(at: textPath.deletingLastPathComponent(), withIntermediateDirectories: true)
        let text = TTSChapterText(bookId: manifest.bookId, chapterId: manifest.chapterId, contentRevision: manifest.contentRevision, title: manifest.title, position: manifest.position, blocks: manifest.blocks)
        try JSONEncoder().encode(text).write(to: textPath, options: .atomic)
        let destination = audio(manifest.id)
        if FileManager.default.fileExists(atPath: destination.path) { _ = try FileManager.default.replaceItemAt(destination, withItemAt: staged) }
        else { try FileManager.default.moveItem(at: staged, to: destination) }
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: destination.path)
        #endif
    }
}

private final class TTSInstallEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func begin() { lock.lock(); count += 1; lock.unlock() }
    func finish() { lock.lock(); count -= 1; lock.unlock() }
    var isEmpty: Bool { lock.lock(); defer { lock.unlock() }; return count == 0 }
}

@MainActor
final class TTSOfflineLibrary: NSObject, ObservableObject {
    static let shared = TTSOfflineLibrary()
    @Published private(set) var records: [TTSDownloadRecord] = []
    @Published private(set) var voices = TTSVoice.presets
    @Published private(set) var engineState: TTSEngineState?
    @Published var errorMessage: String?
    @Published private(set) var isRefreshing = false
    var backgroundCompletion: (() -> Void)? { didSet { finishBackgroundEventsIfPossible() } }
    private var backgroundEventsFinished = false
    private nonisolated let installEvents = TTSInstallEvents()
    private var refreshTask: Task<Void, Never>?
    private var lastProgressSave = Date.distantPast
    private var lastVoiceRefresh = Date.distantPast
    private lazy var session: URLSession = {
        #if os(iOS)
        let config = URLSessionConfiguration.background(withIdentifier: "com.lnreader.audio.downloads.v1")
        config.sessionSendsLaunchEvents = true; config.isDiscretionary = false
        #else
        let config = URLSessionConfiguration.default
        #endif
        config.httpCookieStorage = .shared; config.httpMaximumConnectionsPerHost = 3; config.waitsForConnectivity = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    private var indexURL: URL { TTSStorage.root.appendingPathComponent("downloads.json") }
    private override init() {
        super.init()
        do {
            try FileManager.default.createDirectory(at: TTSStorage.root, withIntermediateDirectories: true)
            if let data = try? Data(contentsOf: indexURL), let saved = try? JSONDecoder().decode([TTSDownloadRecord].self, from: data) { records = saved }
            if let data = try? Data(contentsOf: TTSStorage.root.appendingPathComponent("voices.json")), let saved = try? JSONDecoder().decode([TTSVoice].self, from: data) { voices = saved }
            // Recover a completed atomic package if iOS terminated us before the index commit.
            for directory in try FileManager.default.contentsOfDirectory(at: TTSStorage.root, includingPropertiesForKeys: nil) where TTSStorage.validID(directory.lastPathComponent) {
                let id = directory.lastPathComponent
                guard let data = try? Data(contentsOf: directory.appendingPathComponent("manifest.json")),
                      let manifest = try? JSONDecoder().decode(TTSManifest.self, from: data),
                      manifest.id == id, (try? manifest.validate()) != nil,
                      let attributes = try? FileManager.default.attributesOfItem(atPath: TTSStorage.audio(id).path),
                      (attributes[.size] as? NSNumber)?.int64Value == manifest.audioBytes else { continue }
                let rendition = TTSRendition(id: id, voiceId: manifest.voiceId, status: "ready", bookId: manifest.bookId, chapterId: manifest.chapterId, bookTitle: manifest.bookTitle, title: manifest.title, position: manifest.position, contentRevision: manifest.contentRevision, completedChunks: 0, totalChunks: 0, error: nil, manifestURL: nil)
                if let index = records.firstIndex(where: { $0.id == id }) {
                    records[index].state = "downloaded"; records[index].manifest = manifest; records[index].error = nil
                    records[index].bytesExpected = manifest.audioBytes; records[index].bytesReceived = manifest.audioBytes
                } else {
                    records.append(.init(id: id, rendition: rendition, state: "downloaded", bytesReceived: manifest.audioBytes, bytesExpected: manifest.audioBytes, isPreview: manifest.bookId == "qwen-previews", backendURL: TTSAPIClient().baseURL.absoluteString, manifest: manifest))
                }
            }
            for index in records.indices where records[index].isAvailable {
                if !TTSStorage.validID(records[index].id) || !FileManager.default.fileExists(atPath: TTSStorage.audio(records[index].id).path) {
                    records[index].state = "failed"; records[index].error = "Local audio is missing. Download again to repair."
                }
            }
        } catch { errorMessage = error.localizedDescription }
        save()
        Task { await reconcileTransfers(); startRefreshLoop() }
    }
    func reconnectBackgroundSession() { _ = session }
    private func finishBackgroundEventsIfPossible() {
        guard backgroundEventsFinished, installEvents.isEmpty, let completion = backgroundCompletion else { return }
        backgroundEventsFinished = false; backgroundCompletion = nil; completion()
    }
    private func save() {
        do { try JSONEncoder().encode(records).write(to: indexURL, options: .atomic) }
        catch { errorMessage = "Could not save audio downloads: \(error.localizedDescription)" }
    }
    func downloads(bookId: String, chapterId: String? = nil) -> [TTSDownloadRecord] {
        records.filter { !$0.isPreview && $0.rendition.bookId == bookId && (chapterId == nil || $0.rendition.chapterId == chapterId) }
    }
    func downloaded(bookId: String, chapterId: String, voiceId: String? = nil) -> TTSDownloadRecord? {
        downloads(bookId: bookId, chapterId: chapterId).filter { $0.isAvailable && (voiceId == nil || $0.rendition.voiceId == voiceId) }.sorted { $0.updatedAt > $1.updatedAt }.first
    }
    func localManifest(_ id: String) throws -> TTSManifest {
        guard TTSStorage.validID(id), records.contains(where: { $0.id == id && $0.isAvailable }), FileManager.default.fileExists(atPath: TTSStorage.audio(id).path) else { throw TTSError.missingAudio }
        let value = try JSONDecoder().decode(TTSManifest.self, from: Data(contentsOf: TTSStorage.directory(id).appendingPathComponent("manifest.json")))
        try value.validate(); return value
    }
    func localText(bookId: String, chapterId: String) -> TTSChapterText? {
        guard let data = try? Data(contentsOf: TTSStorage.chapterText(bookId: bookId, chapterId: chapterId)) else { return nil }
        return try? JSONDecoder().decode(TTSChapterText.self, from: data)
    }
    var migratedDefaultVoice: String {
        let value = UserDefaults.standard.string(forKey: "tts.voice") ?? "qwen-ryan"
        return TTSVoice.presets.contains { $0.id == value } ? value : "qwen-ryan"
    }
    private func selectionKey(_ bookId: String, _ chapterId: String) -> String {
        "tts.selection." + SHA256.hash(data: Data((bookId + "\u{0}" + chapterId).utf8)).map { String(format: "%02x", $0) }.joined()
    }
    func selectedVoice(bookId: String, chapterId: String) -> String {
        UserDefaults.standard.string(forKey: selectionKey(bookId, chapterId)) ?? UserDefaults.standard.string(forKey: selectionKey(bookId, "__book_default__")) ?? migratedDefaultVoice
    }
    func selectVoice(_ id: String, bookId: String, chapterId: String) { UserDefaults.standard.set(id, forKey: selectionKey(bookId, chapterId)); objectWillChange.send() }
    func setBookVoice(_ id: String, bookId: String) { selectVoice(id, bookId: bookId, chapterId: "__book_default__") }
    func refreshVoices() async {
        lastVoiceRefresh = Date()
        do {
            let client = TTSAPIClient(); voices = try await client.voices()
            try JSONEncoder().encode(voices).write(to: TTSStorage.root.appendingPathComponent("voices.json"), options: .atomic)
            for voice in voices {
                if let preview = voice.preview, preview.status == "ready", !records.contains(where: { $0.id == preview.id && ($0.isAvailable || $0.state == "downloading") }) { track(preview, client: client, preview: true) }
            }
            errorMessage = nil
            await refresh()
        } catch { errorMessage = error.localizedDescription }
    }
    func prepare(chapter: TTSChapterRequest, voiceIds: [String]) async throws {
        let client = TTSAPIClient()
        let renditions = try await client.prepare(chapter: chapter, voices: voiceIds)
        if let revision = renditions.first?.contentRevision {
            let blocks = chapter.blocks.map { $0.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            let text = TTSChapterText(bookId: chapter.bookId, chapterId: chapter.chapterId, contentRevision: revision, title: chapter.title, position: chapter.position, blocks: blocks)
            let path = TTSStorage.chapterText(bookId: chapter.bookId, chapterId: chapter.chapterId)
            try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(text).write(to: path, options: .atomic)
        }
        for rendition in renditions { track(rendition, client: client) }
        await refresh()
    }
    private func track(_ rendition: TTSRendition, client: TTSAPIClient, preview: Bool = false) {
        if let index = records.firstIndex(where: { $0.id == rendition.id }) {
            guard !records[index].isAvailable && records[index].state != "downloading" else { return }
            records[index].rendition = rendition; records[index].state = "waiting"; records[index].error = nil
        } else { records.append(.init(id: rendition.id, rendition: rendition, state: "waiting", isPreview: preview, backendURL: client.baseURL.absoluteString)) }
        save()
    }
    private func startRefreshLoop() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(12)); guard let self else { return }; await self.refresh()
            }
        }
    }
    func refresh() async {
        guard !isRefreshing else { return }; isRefreshing = true; defer { isRefreshing = false }
        if Date().timeIntervalSince(lastVoiceRefresh) > 30 && voices.contains(where: { $0.preview?.status != "ready" }) { await refreshVoices() }
        do { engineState = try await TTSAPIClient().engine() }
        catch { engineState = TTSEngineState(status: "unavailable", message: error.localizedDescription, updatedAt: "", retryAt: nil) }
        let waiting = records.filter { $0.state == "waiting" }
        var snapshots: [String: [TTSRendition]] = [:]
        for record in waiting {
            do {
                let client = TTSAPIClient(backendURL: record.backendURL)
                let current: TTSRendition?
                if record.isPreview { current = record.rendition }
                else {
                    let key = record.backendURL + "\u{0}" + record.rendition.bookId
                    if snapshots[key] == nil { snapshots[key] = try await client.renditions(bookId: record.rendition.bookId) }
                    current = snapshots[key]?.first { $0.id == record.id }
                }
                guard let index = records.firstIndex(where: { $0.id == record.id && $0.state == "waiting" }) else { continue }
                guard let current else {
                    records[index].state = "failed"
                    records[index].error = "This preparation was removed from the server queue. Retry to prepare it again."
                    continue
                }
                records[index].rendition = current
                records[index].error = current.error
                if ["failed", "cancelled", "evicted"].contains(current.status) { records[index].state = "failed"; records[index].error = current.error ?? "Preparation stopped" }
                else if current.status == "ready" { try await beginDownload(current, client: client) }
            } catch {
                if let index = records.firstIndex(where: { $0.id == record.id }) { records[index].error = error.localizedDescription }
            }
        }
        save()
    }
    private func beginDownload(_ rendition: TTSRendition, client: TTSAPIClient) async throws {
        let manifest = try await client.manifest(rendition)
        guard let index = records.firstIndex(where: { $0.id == rendition.id && $0.state == "waiting" }) else { return }
        let space = try TTSStorage.root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage ?? 0
        guard space > manifest.audioBytes + 20 * 1024 * 1024 else { throw TTSError.request("Free some storage before downloading more audio.") }
        guard let path = manifest.audioURL else { throw TTSError.invalidManifest }
        records[index].manifest = manifest; records[index].state = "downloading"; records[index].bytesExpected = manifest.audioBytes
        let transferID = rendition.id + ":" + UUID().uuidString
        records[index].transferID = transferID
        let resumePath = TTSStorage.root.appendingPathComponent(rendition.id + ".resume")
        let task: URLSessionDownloadTask
        if let resumeData = try? Data(contentsOf: resumePath) {
            task = session.downloadTask(withResumeData: resumeData)
            try? FileManager.default.removeItem(at: resumePath)
        } else {
            var request = URLRequest(url: try client.url(path))
            request.allowsCellularAccess = !(UserDefaults.standard.object(forKey: "tts.wifiOnly") as? Bool ?? true)
            task = session.downloadTask(with: request)
        }
        task.taskDescription = transferID
        save(); task.resume()
    }
    func retry(_ id: String) async {
        guard let record = records.first(where: { $0.id == id }), record.state != "downloading", !record.isAvailable else { return }
        do {
            let client = TTSAPIClient(backendURL: record.backendURL)
            let current = try await client.renditions(bookId: record.rendition.bookId, chapterId: record.rendition.chapterId).first { $0.id == id }
            if current == nil {
                guard let text = localText(bookId: record.rendition.bookId, chapterId: record.rendition.chapterId) else { throw TTSError.request("The server queue was reset. Open this chapter's audio downloads and prepare it again.") }
                let input = TTSChapterRequest(bookId: text.bookId, bookTitle: record.rendition.bookTitle, chapterId: text.chapterId, title: text.title, position: text.position, blocks: text.blocks)
                for row in try await client.prepare(chapter: input, voices: [record.rendition.voiceId]) { track(row, client: client) }
            } else if ["failed", "cancelled", "evicted"].contains(current!.status) { try await client.action("retry", renditionId: id) }
            guard let index = records.firstIndex(where: { $0.id == id }), records[index].state != "downloading" else { return }
            records[index].state = "waiting"; records[index].error = nil; save(); await refresh()
        } catch { errorMessage = error.localizedDescription }
    }
    func pause(_ id: String) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        let transferID = records[index].transferID
        records[index].state = "paused"; save()
        session.getAllTasks { tasks in
            for task in tasks where task.taskDescription == transferID {
                if let download = task as? URLSessionDownloadTask {
                    download.cancel { [weak self] data in
                        Task { @MainActor in
                            guard let self, self.records.contains(where: { $0.id == id && $0.state == "paused" && $0.transferID == transferID }), let data else { return }
                            try? data.write(to: TTSStorage.root.appendingPathComponent(id + ".resume"), options: .atomic)
                        }
                    }
                } else { task.cancel() }
            }
        }
    }
    func delete(_ id: String) async {
        guard TTSStorage.validID(id) else { return }
        let oldTransfer = records.first(where: { $0.id == id })?.transferID
        if ReaderTTSManager.shared.manifest?.id == id { ReaderTTSManager.shared.stop() }
        records.removeAll { $0.id == id }; save()
        try? FileManager.default.removeItem(at: TTSStorage.root.appendingPathComponent(id + ".resume"))
        do { if FileManager.default.fileExists(atPath: TTSStorage.directory(id).path) { try FileManager.default.removeItem(at: TTSStorage.directory(id)) } }
        catch { errorMessage = error.localizedDescription }
        let tasks = await session.allTasks
        tasks.filter { $0.taskDescription == oldTransfer && oldTransfer != nil || $0.taskDescription == id }.forEach { $0.cancel() }
    }
    private func reconcileTransfers() async {
        let active = Set(await session.allTasks.compactMap(\.taskDescription))
        for index in records.indices where records[index].state == "downloading" && !active.contains(records[index].transferID ?? records[index].id) { records[index].state = "waiting" }
        save()
    }
}

extension TTSOfflineLibrary: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let transferID = downloadTask.taskDescription, let id = transferID.split(separator: ":").first.map(String.init), TTSStorage.validID(id) else { return }
        installEvents.begin()
        let staged = TTSStorage.root.appendingPathComponent("incoming-\(UUID().uuidString).m4a")
        do {
            guard let response = downloadTask.response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { throw TTSError.request("Download authorization expired. Retry this download.") }
            try FileManager.default.moveItem(at: location, to: staged)
            Task { @MainActor [weak self] in
                guard let self else { return }
                defer { self.installEvents.finish(); self.finishBackgroundEventsIfPossible() }
                guard let record = self.records.first(where: { $0.id == id && $0.state == "downloading" && $0.transferID == transferID }), let manifest = record.manifest else { try? FileManager.default.removeItem(at: staged); return }
                do {
                    try await TTSStorage.verify(staged: staged, manifest: manifest)
                    guard let index = self.records.firstIndex(where: { $0.id == id && $0.state == "downloading" && $0.transferID == transferID }) else { try? FileManager.default.removeItem(at: staged); return }
                    try TTSStorage.commit(staged: staged, manifest: manifest)
                    self.records[index].state = "downloaded"; self.records[index].bytesReceived = manifest.audioBytes; self.records[index].error = nil; self.records[index].updatedAt = Date(); self.save()
                } catch {
                    try? FileManager.default.removeItem(at: staged)
                    if let index = self.records.firstIndex(where: { $0.id == id && $0.state == "downloading" && $0.transferID == transferID }) { self.records[index].state = "failed"; self.records[index].error = error.localizedDescription; self.save() }
                }
            }
        } catch {
            Task { @MainActor [weak self] in
                guard let self else { return }
                defer { self.installEvents.finish(); self.finishBackgroundEventsIfPossible() }
                guard let index = self.records.firstIndex(where: { $0.id == id && $0.state == "downloading" && $0.transferID == transferID }) else { return }
                self.records[index].state = "failed"; self.records[index].error = error.localizedDescription; self.save()
            }
        }
    }
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let transferID = downloadTask.taskDescription else { return }
        Task { @MainActor [weak self] in
            guard let self, let index = self.records.firstIndex(where: { $0.transferID == transferID && $0.state == "downloading" }) else { return }
            self.records[index].bytesReceived = totalBytesWritten
            if Date().timeIntervalSince(self.lastProgressSave) > 2 { self.lastProgressSave = Date(); self.save() }
        }
    }
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let transferID = task.taskDescription else { return }
        Task { @MainActor [weak self] in
            guard let self, let index = self.records.firstIndex(where: { $0.transferID == transferID && $0.state == "downloading" }) else { return }
            let id = self.records[index].id
            if let resumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
                try? resumeData.write(to: TTSStorage.root.appendingPathComponent(id + ".resume"), options: .atomic)
            }
            self.records[index].state = "failed"; self.records[index].error = error.localizedDescription; self.save()
        }
    }
    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor [weak self] in self?.backgroundEventsFinished = true; self?.finishBackgroundEventsIfPossible() }
    }
}
