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
    private func isCellularConnection() -> Bool {
        let monitor = NWPathMonitor()
        let semaphore = DispatchSemaphore(value: 0)
        var isCellular = false
        monitor.pathUpdateHandler = { path in
            isCellular = path.usesInterfaceType(.cellular)
            semaphore.signal()
        }
        let queue = DispatchQueue(label: "NetworkMonitorTemp")
        monitor.start(queue: queue)
        _ = semaphore.wait(timeout: .now() + 0.1)
        monitor.cancel()
        return isCellular
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
        guard let novels = try? context.fetch(descriptor) else { return }

        for novel in novels {
            let pluginId = novel.pluginId
            let path = novel.path
            guard let source = pluginManager.plugin(for: pluginId) else { continue }

            do {
                var sourceNovel = try await source.parseNovel(path: path)
                if source.hasParsePage, let totalPages = sourceNovel.totalPages, totalPages > 1 {
                    print("🔌 [\(pluginId)] Paginated chapters detected during library update, fetching \(totalPages) pages...")
                    let allChapters = try await source.fetchAllChapters(path: path, totalPages: totalPages)
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
                updateNovel(novel, sourceNovel: sourceNovel, context: context)
            } catch {
                print("Failed to update novel \(novel.name): \(error.localizedDescription)")
            }
        }
    }

    /// Update a single novel's chapters and metadata from source.
    func updateNovel(_ novel: Novel, sourceNovel: SourceNovel, context: ModelContext) {
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

        let existingChapters = novel.chapters
        let existingPaths = Set(existingChapters.map { $0.path })

        for (index, sourceChapter) in sourceNovel.chapters.enumerated() {
            if existingPaths.contains(sourceChapter.path) {
                if let existing = existingChapters.first(where: { $0.path == sourceChapter.path }) {
                    existing.name = sourceChapter.name
                    existing.releaseTime = sourceChapter.releaseTime
                    existing.chapterNumber = sourceChapter.chapterNumber
                    existing.position = index
                }
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
        try? context.save()
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
