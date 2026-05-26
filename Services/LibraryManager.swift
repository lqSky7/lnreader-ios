// LibraryManager.swift
// Manages library operations: adding/removing novels, updating chapters.

import Foundation
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
        for sourceChapter in sourceNovel.chapters {
            let chapter = Chapter(
                path: sourceChapter.path,
                name: sourceChapter.name
            )
            chapter.chapterNumber = sourceChapter.chapterNumber
            chapter.releaseTime = sourceChapter.releaseTime
            chapter.page = sourceChapter.page ?? "1"
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
        let entry = ReadingHistory(
            novelId: novel.persistentModelID.hashValue,
            chapterID: chapter.persistentModelID.hashValue,
            novelName: novel.name,
            novelCover: novel.cover,
            chapterName: chapter.name,
            pluginId: novel.pluginId
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
}
