// ChapterSourceSync.swift - Merges a freshly fetched chapter list into an entry.
//
// One implementation for both kinds: the merge only looks at URLs, names and
// numbers, so a manga with 1,200 chapters and a novel with 30 take the same
// path. See docs/MANGA_SUPPORT_PLAN.md §8.

import Foundation
import SwiftData

/// What a merge changed, for logging and for deciding whether to save.
struct ChapterSyncResult: Equatable {
    var added = 0
    var updated = 0
    var removed = 0

    var isNoOp: Bool { added == 0 && updated == 0 && removed == 0 }
}

enum ChapterSourceSync {

    /// Merge `incoming` into `entry.chapters`.
    ///
    /// Rules:
    /// - Chapters match by URL. The incoming list's order becomes `sourceOrder`.
    /// - A chapter the source no longer lists is deleted **only** when the user
    ///   has no stake in it: unread, unbookmarked and without history. Deleting
    ///   those would throw away reading progress for a chapter the site merely
    ///   renamed or hid, and a re-added chapter would come back unread.
    /// - New chapters are stamped with `dateFetch`, which is what Updates reads.
    ///
    /// - Returns: counts of added, updated and removed chapters.
    @MainActor
    @discardableResult
    static func merge(
        _ incoming: [SourceChapter],
        into entry: Entry,
        context: ModelContext,
        removeMissing: Bool = true
    ) -> ChapterSyncResult {
        var result = ChapterSyncResult()

        // Dedupe the incoming list: sources occasionally repeat a chapter URL,
        // and the first occurrence is the one the source itself lists first.
        var seen = Set<String>()
        var unique: [SourceChapter] = []
        unique.reserveCapacity(incoming.count)
        for chapter in incoming where !chapter.url.isEmpty {
            if seen.insert(chapter.url).inserted {
                unique.append(chapter)
            }
        }

        var existingByURL: [String: Chapter] = [:]
        existingByURL.reserveCapacity(entry.chapters.count)
        for chapter in entry.chapters {
            existingByURL[chapter.url] = chapter
        }

        for (index, sourceChapter) in unique.enumerated() {
            if let existing = existingByURL[sourceChapter.url] {
                if update(existing, from: sourceChapter, order: index, entryTitle: entry.title) {
                    result.updated += 1
                }
            } else {
                let chapter = Chapter(
                    url: sourceChapter.url,
                    name: sourceChapter.name,
                    chapterNumber: resolvedNumber(for: sourceChapter, entryTitle: entry.title),
                    sourceOrder: index
                )
                chapter.scanlator = sourceChapter.scanlator
                chapter.dateUpload = sourceChapter.dateUpload
                // Marks the chapter as new; Updates reads this.
                chapter.dateFetch = .now
                chapter.entry = entry
                context.insert(chapter)
                result.added += 1
            }
        }

        if removeMissing {
            let incomingURLs = Set(unique.map(\.url))
            for chapter in entry.chapters where !incomingURLs.contains(chapter.url) {
                guard canDiscard(chapter) else { continue }
                context.delete(chapter)
                result.removed += 1
            }
        }

        return result
    }

    /// A missing chapter is only safe to drop when nothing depends on it.
    static func canDiscard(_ chapter: Chapter) -> Bool {
        !chapter.read && !chapter.bookmark && chapter.history == nil
    }

    // MARK: - Per-chapter update

    /// - Returns: whether anything actually changed.
    @discardableResult
    private static func update(
        _ chapter: Chapter,
        from source: SourceChapter,
        order: Int,
        entryTitle: String
    ) -> Bool {
        var changed = false

        if chapter.name != source.name {
            chapter.name = source.name
            changed = true
        }
        if chapter.scanlator != source.scanlator {
            chapter.scanlator = source.scanlator
            changed = true
        }
        if chapter.dateUpload != source.dateUpload {
            chapter.dateUpload = source.dateUpload
            changed = true
        }
        if chapter.sourceOrder != order {
            chapter.sourceOrder = order
            changed = true
        }

        // Keep a number the source gave us; fill in or repair a missing one.
        if source.chapterNumber > -1, chapter.chapterNumber != source.chapterNumber {
            chapter.chapterNumber = source.chapterNumber
            changed = true
        } else if chapter.chapterNumber <= -1 {
            let parsed = ChapterRecognition.parseChapterNumber(
                source.name, mangaTitle: entryTitle
            )
            if parsed > -1 {
                chapter.chapterNumber = parsed
                changed = true
            }
        }

        return changed
    }

    private static func resolvedNumber(for chapter: SourceChapter, entryTitle: String) -> Double {
        if chapter.chapterNumber > -1 { return chapter.chapterNumber }
        return ChapterRecognition.parseChapterNumber(chapter.name, mangaTitle: entryTitle)
    }
}
