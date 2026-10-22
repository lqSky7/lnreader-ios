// LibraryManager.swift
// Library operations: adding entries, updating chapters, recording progress.

import Foundation
import Network
import Observation
import SwiftData

/// Coordinates library-level operations: adding entries from a source,
/// refreshing chapter lists, and recording reading progress.
///
/// Source-agnostic by design: it works with `SourceEntry` / `SourceChapter`
/// values and the `SourceManager` registry, so a novel and a manga go through
/// exactly the same code path.
@Observable
@MainActor
final class LibraryManager {

    /// Whether a library-wide update is in progress.
    private(set) var isUpdating = false

    // MARK: - Adding and removing

    /// Add an entry to the library, or return the existing row.
    ///
    /// Chapters already known for the entry are left untouched, so re-adding a
    /// removed entry keeps its read state.
    @discardableResult
    func addToLibrary(
        entry sourceEntry: SourceEntry,
        chapters: [SourceChapter],
        context: ModelContext
    ) -> Entry {
        let sourceKey = sourceEntry.sourceKey
        let url = sourceEntry.url
        let predicate = #Predicate<Entry> { $0.sourceKey == sourceKey && $0.url == url }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1

        if let existing = try? context.fetch(descriptor).first {
            existing.inLibrary = true
            if existing.chapters.isEmpty {
                insertChapters(chapters, into: existing, context: context)
            }
            try? context.save()
            return existing
        }

        let entry = Entry(
            kind: sourceEntry.kind,
            sourceKey: sourceEntry.sourceKey,
            url: sourceEntry.url,
            title: sourceEntry.title
        )
        entry.thumbnailURL = sourceEntry.thumbnailURL
        entry.author = sourceEntry.author
        entry.artist = sourceEntry.artist
        entry.summary = sourceEntry.description
        entry.genres = sourceEntry.genres
        entry.status = sourceEntry.status
        entry.inLibrary = true
        entry.dateAdded = .now
        context.insert(entry)

        insertChapters(chapters, into: entry, context: context)
        try? context.save()
        return entry
    }

    /// Remove an entry from the library but keep its chapters and history.
    func removeFromLibrary(entry: Entry, context: ModelContext) {
        entry.inLibrary = false
        try? context.save()
    }

    private func insertChapters(
        _ chapters: [SourceChapter],
        into entry: Entry,
        context: ModelContext
    ) {
        for (index, sourceChapter) in chapters.enumerated() {
            let number = sourceChapter.chapterNumber > -1
                ? sourceChapter.chapterNumber
                : ChapterRecognition.parseChapterNumber(sourceChapter.name, mangaTitle: entry.title)
            let chapter = Chapter(
                url: sourceChapter.url,
                name: sourceChapter.name,
                chapterNumber: number,
                sourceOrder: index
            )
            chapter.scanlator = sourceChapter.scanlator
            chapter.dateUpload = sourceChapter.dateUpload
            chapter.entry = entry
            context.insert(chapter)
        }
    }

    // MARK: - Reading state

    /// Record that a chapter was opened.
    ///
    /// Opening is not reading: `read` only flips once the reader reaches the
    /// end, which is why this only touches history and the "recently read"
    /// timestamp.
    func recordHistory(entry: Entry, chapter: Chapter, context: ModelContext) {
        let chapterURL = chapter.url
        let predicate = #Predicate<History> { $0.chapterURL == chapterURL }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1

        if let existing = try? context.fetch(descriptor).first {
            existing.lastRead = .now
        } else {
            let history = History(chapterURL: chapter.url)
            history.chapter = chapter
            context.insert(history)
        }

        entry.lastReadAt = .now
        try? context.save()
    }

    /// Record how far the user has read into a chapter.
    ///
    /// Reaching `Chapter.finishedThreshold` marks the chapter read; a finished
    /// chapter keeps 100% and reopens from the top, and rereading it never
    /// moves it back to unread.
    func recordReadingPosition(
        chapter: Chapter,
        paragraphIndex: Int,
        percent: Int,
        context: ModelContext
    ) {
        let finished = chapter.read && chapter.progress >= 100
        let clamped = min(max(percent, 0), 100)

        if finished {
            chapter.paragraphIndex = clamped >= Int(Chapter.finishedThreshold) ? 0 : paragraphIndex
        } else if clamped >= Int(Chapter.finishedThreshold) {
            chapter.read = true
            chapter.progress = 100
            chapter.paragraphIndex = 0
        } else {
            chapter.progress = Double(clamped)
            chapter.paragraphIndex = paragraphIndex
        }

        // Keep the history row's timestamp current without creating one.
        chapter.history?.lastRead = .now
        chapter.entry?.lastReadAt = .now

        try? context.save()
    }

    /// Record a manga page turn.
    ///
    /// Separate from `recordReadingPosition` because a manga chapter is measured
    /// in pages, not paragraphs, and "finished" means the reader reached the
    /// last page rather than a percentage threshold.
    func recordMangaProgress(
        chapter: Chapter,
        pageIndex: Int,
        pageCount: Int,
        context: ModelContext
    ) {
        let update = MangaProgress.update(pageIndex: pageIndex, pageCount: pageCount)

        chapter.lastPageRead = update.lastPageRead
        chapter.pagesLeft = update.pagesLeft
        chapter.progress = update.progress
        if update.finished {
            chapter.read = true
        }

        chapter.history?.lastRead = .now
        chapter.entry?.lastReadAt = .now

        try? context.save()
    }

    // MARK: - Network state

    /// Whether the current connection is cellular.
    private func isCellularConnection() -> Bool {
        NetworkMonitor.shared.isCellular()
    }

    // MARK: - Library updates

    /// Refresh every library entry from its source.
    func updateLibrary(context: ModelContext, sourceManager: SourceManager, automatic: Bool = false) async {
        guard !isUpdating else { return }

        if UserDefaults.standard.object(forKey: "general.updateOnWifiOnly") as? Bool ?? true {
            await NetworkMonitor.shared.waitForPath()
            if !NetworkMonitor.shared.isOnWiFi() {
                print("📶 Library update skipped: Wi-Fi only setting is enabled and current network is cellular.")
                return
            }
        }

        isUpdating = true
        defer { isUpdating = false }

        let predicate = #Predicate<Entry> { $0.inLibrary }
        guard let entries = try? context.fetch(FetchDescriptor(predicate: predicate)),
              !entries.isEmpty
        else { return }

        // Fetch all sources concurrently (network-bound, 4 at a time), then
        // apply SwiftData changes sequentially on the MainActor context.
        struct UpdateJob: Sendable {
            let id: PersistentIdentifier
            let sourceKey: String
            let url: String
            let kind: ContentKind
            let title: String
        }
        struct UpdateWork {
            let source: any CatalogSource
            let job: UpdateJob
        }
        struct UpdateResult: Sendable {
            let id: PersistentIdentifier
            let details: SourceEntry?
            let chapters: [SourceChapter]
            let error: String?
        }

        var pending: [UpdateWork] = []
        for entry in entries where !entry.isLocal {
            guard !Task.isCancelled else { return }
            guard LibraryUpdatePolicy.permits(strategy: entry.updateStrategy, hasFetched: entry.lastUpdate != nil,
                status: entry.status, hasUnread: entry.hasUnread, automatic: automatic,
                unreadOnly: UserDefaults.standard.bool(forKey: "updates.unreadOnly"),
                skipCompleted: UserDefaults.standard.bool(forKey: "updates.skipCompleted")) else { continue }
            guard let source = sourceManager.source(forKey: entry.sourceKey) else { continue }
            let job = UpdateJob(
                id: entry.persistentModelID,
                sourceKey: entry.sourceKey,
                url: entry.url,
                kind: entry.kind,
                title: entry.title
            )
            pending.append(UpdateWork(source: source, job: job))
        }
        guard !pending.isEmpty else { return }

        let results = await withTaskGroup(of: UpdateResult.self, returning: [UpdateResult].self) { group in
            let maxConcurrent = 4
            var queue = pending[...]
            var collected: [UpdateResult] = []
            collected.reserveCapacity(pending.count)

            func submit(_ work: UpdateWork) {
                group.addTask {
                    let entry = SourceEntry(
                        sourceKey: work.job.sourceKey,
                        kind: work.job.kind,
                        url: work.job.url,
                        title: work.job.title
                    )
                    do {
                        try Task.checkCancellation()
                        let details = try await work.source.details(entry)
                        try Task.checkCancellation()
                        let chapters = try await work.source.chapters(entry)
                        return UpdateResult(
                            id: work.job.id, details: details, chapters: chapters, error: nil
                        )
                    } catch {
                        return UpdateResult(
                            id: work.job.id, details: nil, chapters: [], error: error.localizedDescription
                        )
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

        let byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.persistentModelID, $0) })
        var didChange = false
        for result in results {
            guard !Task.isCancelled else { return }
            guard let entry = byID[result.id] else { continue }
            if let details = result.details, result.error == nil {
                applyUpdate(entry, details: details, chapters: result.chapters, context: context)
                didChange = true
            } else {
                print("Failed to update \(entry.title): \(result.error ?? "unknown error")")
            }
        }
        if didChange {
            try? context.save()
        }
    }

    /// Merge source metadata and a chapter list into a stored entry.
    ///
    /// Metadata is overwritten from the source; the chapter list goes through
    /// `ChapterSourceSync`, which matches by URL, keeps read state, stamps new
    /// chapters for Updates and prunes chapters the source dropped.
    @discardableResult
    func applyUpdate(
        _ entry: Entry,
        details: SourceEntry,
        chapters: [SourceChapter],
        context: ModelContext,
        saveImmediately: Bool = true
    ) -> ChapterSyncResult {
        if !details.title.isEmpty { entry.title = details.title }
        if let thumbnail = details.thumbnailURL { entry.thumbnailURL = thumbnail }
        if let summary = details.description, !summary.isEmpty { entry.summary = summary }
        if let author = details.author { entry.author = author }
        if let artist = details.artist { entry.artist = artist }
        if !details.genres.isEmpty { entry.genres = details.genres }
        entry.status = details.status
        entry.lastUpdate = .now

        let result = ChapterSourceSync.merge(chapters, into: entry, context: context)

        if saveImmediately {
            try? context.save()
        }
        return result
    }

    /// Mark every "new chapter" badge as seen.
    func clearUpdates(context: ModelContext) {
        let predicate = #Predicate<Chapter> { $0.dateFetch != nil }
        if let chapters = try? context.fetch(FetchDescriptor(predicate: predicate)) {
            for chapter in chapters {
                chapter.dateFetch = nil
            }
            try? context.save()
        }
    }
}

// MARK: - Shared network path monitor

/// Singleton wrapper around NWPathMonitor. Creating a monitor per check
/// (plus a semaphore wait) blocks the caller and spins up threads;
/// share one long-lived monitor instead.
final class NetworkMonitor: @unchecked Sendable {
    static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.lnreader.network-monitor")
    private let lock = NSLock()
    private var _isCellular = false
    private var _isOnWiFi = false
    private var _isConnected = false
    private var _hasPath = false
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
            self._isOnWiFi = path.status == .satisfied && path.usesInterfaceType(.wifi)
            self._isConnected = path.status == .satisfied
            self._hasPath = true
            self.lock.unlock()
            NotificationCenter.default.post(name: Notification.Name("LNReaderNetworkChanged"), object: nil)
        }
        monitor.start(queue: queue)
    }

    func isCellular() -> Bool {
        ensureStarted()
        lock.lock()
        defer { lock.unlock() }
        return _isCellular
    }

    func isOnWiFi() -> Bool {
        ensureStarted()
        lock.lock(); defer { lock.unlock() }
        return _isOnWiFi
    }
    func isConnected() -> Bool {
        ensureStarted(); lock.lock(); defer { lock.unlock() }; return _isConnected
    }
    private func hasPath() -> Bool {
        lock.lock(); defer { lock.unlock() }; return _hasPath
    }
    func waitForPath() async {
        ensureStarted()
        for _ in 0..<20 {
            if hasPath() || Task.isCancelled { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }
}
