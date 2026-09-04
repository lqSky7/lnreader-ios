// LibraryManager.swift
// Manages library operations: adding/removing novels, updating chapters.

import Foundation
import Network
import Observation
import SwiftData

/// Coordinates library-level operations such as adding novels from sources,
/// updating chapters, and managing reading progress.
@Observable
@MainActor
final class LibraryManager {

    /// Whether a library-wide update is in progress.
    private(set) var isUpdating = false

    /// Add a novel to the library from source data, inserting into SwiftData.
    func addToLibrary(
        sourceNovel: SourceNovel,
        pluginId: String,
        context: ModelContext
    ) {
        // Check if novel already exists
        let path = sourceNovel.path
        let predicate = #Predicate<Novel> { $0.path == path && $0.pluginId == pluginId }
        let descriptor = FetchDescriptor(predicate: predicate)

        if let existing = try? context.fetch(descriptor).first {
            existing.inLibrary = true
            return
        }

        let novel = Novel(
            path: sourceNovel.path,
            pluginId: pluginId,
            name: sourceNovel.name,
            cover: sourceNovel.cover,
            summary: sourceNovel.summary,
            author: sourceNovel.author,
            artist: sourceNovel.artist,
            status: NovelStatus(rawValue: sourceNovel.status ?? "") ?? NovelStatus.unknown,
            genres: sourceNovel.genres
        )
        novel.inLibrary = true
        novel.totalPages = sourceNovel.totalPages ?? 0
        context.insert(novel)

        // Insert chapters
        for (index, sourceChapter) in sourceNovel.chapters.enumerated() {
            let chapter = Chapter(
                path: sourceChapter.path,
                name: sourceChapter.name
            )
            chapter.chapterNumber = sourceChapter.chapterNumber
            chapter.releaseTime = sourceChapter.releaseTime
            chapter.page = sourceChapter.page ?? "1"
            chapter.position = index
            chapter.novel = novel
            context.insert(chapter)
        }

        try? context.save()
    }

    /// Remove a novel from the library (keeps data but marks as not in library).
    func removeFromLibrary(novel: Novel, context: ModelContext) {
        novel.inLibrary = false
        try? context.save()
    }

    /// Record a reading history entry.
    func recordHistory(
        novel: Novel,
        chapter: Chapter,
        context: ModelContext
    ) {
        // Delete any existing history entries for this novel to only keep the latest
        let targetPath = novel.path
        let targetPlugin = novel.pluginId
        let predicate = #Predicate<ReadingHistory> { $0.novelPath == targetPath && $0.pluginId == targetPlugin }
        let descriptor = FetchDescriptor(predicate: predicate)
        if let existingEntries = try? context.fetch(descriptor) {
            for entry in existingEntries {
                context.delete(entry)
            }
        }

        let entry = ReadingHistory(
            novelId: novel.persistentModelID.hashValue,
            chapterID: chapter.persistentModelID.hashValue,
            novelPath: novel.path,
            chapterPath: chapter.path,
            novelName: novel.name,
            novelCover: novel.cover,
            chapterName: chapter.name,
            pluginId: novel.pluginId,
            progress: chapter.progress
        )
        context.insert(entry)

        novel.lastReadAt = .now
        chapter.readTime = .now
        chapter.unread = false

        try? context.save()
    }

    /// Update reading progress for a chapter.
    func updateProgress(
        chapter: Chapter,
        progress: Int,
        position: Int,
        context: ModelContext
    ) {
        chapter.progress = progress
        chapter.position = position
        try? context.save()
    }

    /// Check if the current network connection is cellular.
    /// Uses a shared NWPathMonitor instead of spinning one up per call
    /// (the old code created a monitor + semaphore + thread on every update).
    private func isCellularConnection() -> Bool {
        NetworkMonitor.shared.isCellular()
    }

    /// Update all novels in the library by fetching the latest details and chapters from sources.
    func updateLibrary(context: ModelContext, pluginManager: PluginManager) async {
        guard !isUpdating else { return }

        // Wi-Fi only restriction check
        if UserDefaults.standard.object(forKey: "general.updateOnWifiOnly") as? Bool ?? true {
            if isCellularConnection() {
                print("📶 Library update skipped: Wi-Fi only setting is enabled and current network is cellular.")
                return
            }
        }

        isUpdating = true
        defer { isUpdating = false }

        let predicate = #Predicate<Novel> { $0.inLibrary }
        let descriptor = FetchDescriptor(predicate: predicate)
        guard let novels = try? context.fetch(descriptor), !novels.isEmpty else { return }

        // Fetch all sources CONCURRENTLY (network-bound, max 4 at a time),
        // then apply SwiftData updates SEQUENTIALLY on the MainActor context.
        // The old code awaited each novel one-by-one: N novels × latency.
        //
        // Concurrency-safety: plugin instances are snapshotted on the MainActor
        // before the group (same pattern as GlobalSearchView) and each child
        // task only touches its own snapshot plus its Sendable job. Chapter
        // results are Sendable value types; failures travel as plain strings
        // so the group's result type stays Sendable under Swift 6 checking.
        struct UpdateJob: Sendable {
            let id: PersistentIdentifier
            let pluginId: String
            let path: String
            let name: String
        }
        struct UpdateWork {
            let source: any SourcePlugin
            let hasParsePage: Bool
            let job: UpdateJob
        }
        var pending: [UpdateWork] = []
        for novel in novels {
            let job = UpdateJob(id: novel.persistentModelID, pluginId: novel.pluginId, path: novel.path, name: novel.name)
            if let source = pluginManager.plugin(for: job.pluginId) {
                pending.append(UpdateWork(source: source, hasParsePage: source.hasParsePage, job: job))
            }
        }
        guard !pending.isEmpty else { return }

        typealias UpdateResult = (id: PersistentIdentifier, novel: SourceNovel?, error: String?)
        let results = await withTaskGroup(of: UpdateResult.self, returning: [UpdateResult].self) { group in
            let maxConcurrent = 4
            var queue = pending[...]
            var collected: [UpdateResult] = []
            collected.reserveCapacity(pending.count)

            func submit(_ work: UpdateWork) {
                group.addTask {
                    do {
                        var sourceNovel = try await work.source.parseNovel(path: work.job.path)
                        if work.hasParsePage, let totalPages = sourceNovel.totalPages, totalPages > 1 {
                            #if DEBUG
                            print("🔌 [\(work.job.pluginId)] Paginated chapters detected during library update, fetching \(totalPages) pages...")
                            #endif
                            let allChapters = try await work.source.fetchAllChapters(path: work.job.path, totalPages: totalPages)
                            sourceNovel = SourceNovel(
                                name: sourceNovel.name,
                                path: sourceNovel.path,
                                cover: sourceNovel.cover,
                                genres: sourceNovel.genres,
                                summary: sourceNovel.summary,
                                author: sourceNovel.author,
                                artist: sourceNovel.artist,
                                status: sourceNovel.status,
                                chapters: allChapters,
                                totalPages: sourceNovel.totalPages
                            )
                        }
                        return (work.job.id, sourceNovel, nil)
                    } catch {
                        return (work.job.id, nil, error.localizedDescription)
                    }
                }
            }

            for _ in 0..<min(maxConcurrent, queue.count) {
                submit(queue.removeFirst())
            }
            while let result = await group.next() {
                collected.append(result)
                if !queue.isEmpty {
                    submit(queue.removeFirst())
                }
            }
            return collected
        }

        let byID = Dictionary(uniqueKeysWithValues: novels.map { ($0.persistentModelID, $0) })
        var didChange = false
        for result in results {
            guard let novel = byID[result.id] else { continue }
            if let sourceNovel = result.novel {
                updateNovel(novel, sourceNovel: sourceNovel, context: context, saveImmediately: false)
                didChange = true
            } else {
                print("Failed to update novel \(novel.name): \(result.error ?? "unknown error")")
            }
        }
        if didChange {
            try? context.save()
        }
    }

    /// Update a single novel's chapters and metadata from source.
    func updateNovel(_ novel: Novel, sourceNovel: SourceNovel, context: ModelContext, saveImmediately: Bool = true) {
        novel.name = sourceNovel.name
        if let cover = sourceNovel.cover {
            novel.cover = cover
        }
        if let summary = sourceNovel.summary {
            novel.summary = summary
        }
        if let author = sourceNovel.author {
            novel.author = author
        }
        if let artist = sourceNovel.artist {
            novel.artist = artist
        }
        novel.status = NovelStatus(rawValue: sourceNovel.status ?? "") ?? .unknown
        novel.genres = sourceNovel.genres
        novel.totalPages = sourceNovel.totalPages ?? 0
        novel.lastUpdatedAt = .now

        // O(n) lookup via dictionary. The old `first(where:)` inside the loop
        // was O(n²) — painful for 2000-chapter novels on every library update.
        let existingByPath = Dictionary(uniqueKeysWithValues: novel.chapters.map { ($0.path, $0) })

        for (index, sourceChapter) in sourceNovel.chapters.enumerated() {
            if let existing = existingByPath[sourceChapter.path] {
                existing.name = sourceChapter.name
                existing.releaseTime = sourceChapter.releaseTime
                existing.chapterNumber = sourceChapter.chapterNumber
                existing.position = index
            } else {
                let newChapter = Chapter(
                    path: sourceChapter.path,
                    name: sourceChapter.name
                )
                newChapter.chapterNumber = sourceChapter.chapterNumber
                newChapter.releaseTime = sourceChapter.releaseTime
                newChapter.page = sourceChapter.page ?? "1"
                newChapter.position = index
                newChapter.updatedTime = .now // Marks it as an update!
                newChapter.novel = novel
                context.insert(newChapter)
            }
        }
        if saveImmediately {
            try? context.save()
        }
    }

    /// Clear all updates by setting updatedTime to nil for all chapters.
    func clearUpdates(context: ModelContext) {
        let predicate = #Predicate<Chapter> { $0.updatedTime != nil }
        let descriptor = FetchDescriptor(predicate: predicate)
        if let chapters = try? context.fetch(descriptor) {
            for chapter in chapters {
                chapter.updatedTime = nil
            }
            try? context.save()
        }
    }
}

// MARK: - Shared network path monitor

/// Singleton wrapper around NWPathMonitor. Creating a monitor per check
/// (plus a semaphore wait) blocks the caller and spins up threads;
/// share one long-lived monitor instead.
final class NetworkMonitor: Sendable {
    static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.lnreader.network-monitor")
    private let lock = NSLock()
    private var _isCellular = false
    private var started = false

    private init() {}

    private func ensureStarted() {
        lock.lock()
        defer { lock.unlock() }
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.lock.lock()
            self._isCellular = path.usesInterfaceType(.cellular)
            self.lock.unlock()
        }
        monitor.start(queue: queue)
    }

    func isCellular() -> Bool {
        ensureStarted()
        lock.lock()
        defer { lock.unlock() }
        return _isCellular
    }
}
