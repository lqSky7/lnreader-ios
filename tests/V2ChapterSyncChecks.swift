// V2ChapterSyncChecks.swift - Chapter number parsing and list merging.
//
// The parsing cases mirror Yokai's `ChapterRecognitionTest` (Apache-2.0) so the
// port can be diffed against the reference behaviour. The merge cases drive a
// real in-memory store.

import Foundation
import SwiftData

@main
@MainActor
struct V2ChapterSyncChecks {

    static func main() throws {
        checkChapterRecognition()
        try checkMerge()
        try checkMissingChapterGuard()
        try checkReaddedChapterKeepsState()
        print("PASS: chapter recognition (Yokai cases) and source sync "
            + "(add/update/remove, delete guard, re-add keeps read state)")
    }

    // MARK: - Chapter numbers

    private static func checkChapterRecognition() {
        let cases: [(title: String, name: String, expected: Double)] = [
            // "Ch." prefix, with and without a space after the period.
            ("Mokushiroku Alice", "Mokushiroku Alice Vol.1 Ch.4: Misrepresentation", 4),
            ("Mokushiroku Alice", "Mokushiroku Alice Vol. 1 Ch. 4: Misrepresentation", 4),
            ("Mokushiroku Alice", "Mokushiroku Alice Vol.1 Ch.4.1: Misrepresentation", 4.1),
            ("Mokushiroku Alice", "Mokushiroku Alice Vol.1 Ch.4.a: Misrepresentation", 4.1),
            ("Mokushiroku Alice", "Mokushiroku Alice Vol.1 Ch.4.b: Misrepresentation", 4.2),
            ("Mokushiroku Alice", "Mokushiroku Alice Vol.1 Ch.4.extra: Misrepresentation", 4.99),

            // Plain numbers in the title.
            ("Bleach", "Bleach 567 Down With Snowwhite", 567),
            ("Bleach", "Bleach 567.1 Down With Snowwhite", 567.1),
            ("Bleach", "Bleach 567.b Down With Snowwhite", 567.2),
            ("Bleach", "Bleach 567.extra Down With Snowwhite", 567.99),

            // Title itself contains the number being parsed.
            ("Solanin", "Solanin 028 Vol. 2", 28),
            ("Solanin", "Solanin 028.1 Vol. 2", 28.1),
            ("Onepunch-Man", "Onepunch-Man Punch Ver002 028", 28),
            ("Onepunch-Man", "Onepunch-Man Punch Ver002 028.extra", 28.99),
            ("Onepunch-Man", "Onepunch-Man Punch Ver002 086 : Creeping Darkness [3]", 86),
            ("Ayame 14", "Ayame 14 1 - The summer of 14", 1),
            ("Ayame 14", "Vol.1 Ch.1: March 25 (First Day Cohabiting)", 1),

            // Version / volume / season noise.
            ("random", "Vol.1 Ch.5v.2: Alones", 5),
            ("random", "Vol.001 Ch.003: Kaguya Doesn't Know Much", 3),
            ("Ansatsu Kyoushitsu", "Ansatsu Kyoushitsu 011v002: Assembly Time", 11),
            ("D.I.C.E", "D.I.C.E[Season 001] Ep. 007", 7),
            ("The Gamer", "S3 - Chapter 20", 20),
            ("Tokyo ESP", "Tokyo ESP 027: Part 002: Chapter 001", 27),
            ("One-punch Man", "Mag Version 195.5", 195.5),

            // Punctuation and trailing text.
            ("random", "Fairy Tail 404: 00:00", 404),
            ("random", "Asu No Yoichi 19a", 19.1),
            ("Fairy Tail", "Fairy Tail 404.extravol002", 404.99),
            ("Fairy Tail", "Fairy Tail 404 extravol002", 404.99),
            ("Fairy Tail", "Fairy Tail 404.omakevol002", 404.98),
            ("Fairy Tail", "Fairy Tail 404.specialvol002", 404.97),
            ("One Piece", "One Piece 300,a", 300.1),
            ("One Piece", "One Piece Ch,123,extra", 123.99),
            ("One Piece", "One Piece the sunny, goes swimming 024,005", 24.005),
            ("Solo Leveling", "ch 122-a", 122.1),
            ("Solo Leveling", "Solo Leveling Ch.123-extra", 123.99),
            ("Solo Leveling", "Solo Leveling, 024-005", 24.005),
            ("Solo Leveling", "Ch.191-200 Read Online", 191.2),
            ("One Outs", "One Outs 001", 1),
            ("The Sister of the Woods with a Thousand Young", "The 1st Night", 1),
            ("The Sister of the Woods with a Thousand Young", "The 4th Night", 4),

            // Nothing to find.
            ("random", "Foo", -1),
        ]

        for testCase in cases {
            let parsed = ChapterRecognition.parseChapterNumber(
                testCase.name, mangaTitle: testCase.title
            )
            precondition(
                abs(parsed - testCase.expected) < 0.0001,
                "\(testCase.name) → \(parsed), expected \(testCase.expected)"
            )
        }

        // A number the source already gave us wins over parsing.
        precondition(
            ChapterRecognition.parseChapterNumber("Ch.4", mangaTitle: "", knownNumber: 9) == 9
        )
        // `-2` is the "source says it is special" sentinel and is preserved.
        precondition(
            ChapterRecognition.parseChapterNumber("Ch.4", mangaTitle: "", knownNumber: -2) == -2
        )
    }

    // MARK: - Merge

    private static func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        return try ModelContainer(
            for: schema,
            migrationPlan: LNReaderSchemaMigrationPlan.self,
            configurations: ModelConfiguration(
                "V2ChapterSyncChecks", schema: schema, isStoredInMemoryOnly: true
            )
        )
    }

    private static func sourceChapter(
        _ url: String,
        _ name: String,
        number: Double = -1
    ) -> SourceChapter {
        SourceChapter(url: url, name: name, chapterNumber: number)
    }

    private static func checkMerge() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let entry = Entry(kind: .manga, sourceKey: "mihon:1", url: "/manga/x", title: "X")
        context.insert(entry)

        // Initial add.
        let initial = ChapterSourceSync.merge(
            [
                sourceChapter("1", "Chapter 1", number: 1),
                sourceChapter("2", "Chapter 2", number: 2),
                sourceChapter("3", "Chapter 3", number: 3),
            ],
            into: entry,
            context: context
        )
        precondition(initial.added == 3, "fresh merge adds every chapter")
        precondition(initial.updated == 0 && initial.removed == 0)
        try context.save()
        precondition(entry.chapters.count == 3)

        // Rename one, add one, drop one.
        let second = ChapterSourceSync.merge(
            [
                sourceChapter("1", "Chapter 1", number: 1),
                sourceChapter("2", "Chapter 2 (fixed)", number: 2),
                sourceChapter("4", "Chapter 4", number: 4),
            ],
            into: entry,
            context: context
        )
        precondition(second.added == 1, "chapter 4 is new")
        precondition(second.updated == 1, "chapter 2 was renamed")
        precondition(second.removed == 1, "chapter 3 was dropped and is unread")
        try context.save()

        precondition(entry.chapters.count == 3)
        precondition(entry.chapters.contains { $0.url == "2" && $0.name == "Chapter 2 (fixed)" })

        // A merge that changes nothing must report nothing.
        let third = ChapterSourceSync.merge(
            [
                sourceChapter("1", "Chapter 1", number: 1),
                sourceChapter("2", "Chapter 2 (fixed)", number: 2),
                sourceChapter("4", "Chapter 4", number: 4),
            ],
            into: entry,
            context: context
        )
        precondition(third.isNoOp, "identical lists are a no-op, got \(third)")

        // Duplicate URLs in one payload collapse to one chapter.
        let fourth = ChapterSourceSync.merge(
            [
                sourceChapter("1", "Chapter 1", number: 1),
                sourceChapter("1", "Chapter 1", number: 1),
                sourceChapter("2", "Chapter 2 (fixed)", number: 2),
                sourceChapter("4", "Chapter 4", number: 4),
            ],
            into: entry,
            context: context
        )
        precondition(fourth.added == 0)
        precondition(entry.chapters.count == 3)

        // A chapter the source reports without a number gets one parsed.
        let fifth = ChapterSourceSync.merge(
            [
                sourceChapter("1", "Chapter 1", number: 1),
                sourceChapter("2", "Chapter 2 (fixed)", number: 2),
                sourceChapter("4", "Chapter 4", number: 4),
                sourceChapter("5", "Chapter 12: The Long Night"),
            ],
            into: entry,
            context: context
        )
        precondition(fifth.added == 1)
        let parsed = entry.chapters.first { $0.url == "5" }
        precondition(parsed?.chapterNumber == 12, "number parsed from the title")
    }

    private static func checkMissingChapterGuard() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let entry = Entry(kind: .novel, sourceKey: "ln:x", url: "novel/x", title: "X")
        context.insert(entry)
        ChapterSourceSync.merge(
            [
                sourceChapter("1", "Chapter 1", number: 1),
                sourceChapter("2", "Chapter 2", number: 2),
            ],
            into: entry,
            context: context
        )
        try context.save()

        let read = try unwrap(entry.chapters.first { $0.url == "1" })
        read.read = true
        read.progress = 100
        let bookmarked = try unwrap(entry.chapters.first { $0.url == "2" })
        bookmarked.bookmark = true
        try context.save()

        // Both chapters disappear from the source, but the user has a stake in
        // both, so neither may be deleted.
        let result = ChapterSourceSync.merge([], into: entry, context: context)
        precondition(result.removed == 0, "read and bookmarked chapters must survive")
        try context.save()
        precondition(entry.chapters.count == 2)
    }

    private static func checkReaddedChapterKeepsState() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let entry = Entry(kind: .novel, sourceKey: "ln:y", url: "novel/y", title: "Y")
        context.insert(entry)
        ChapterSourceSync.merge(
            [sourceChapter("1", "Chapter 1", number: 1)],
            into: entry,
            context: context
        )
        try context.save()

        let chapter = try unwrap(entry.chapters.first)
        chapter.read = true
        chapter.bookmark = true
        chapter.progress = 100
        try context.save()

        // Removed from the source, then re-added later.
        _ = ChapterSourceSync.merge([], into: entry, context: context)
        try context.save()

        let readd = ChapterSourceSync.merge(
            [sourceChapter("1", "Chapter 1", number: 1)],
            into: entry,
            context: context
        )
        precondition(readd.added == 0, "the kept chapter is matched, not re-added")
        try context.save()

        let after = try unwrap(entry.chapters.first)
        precondition(after.read, "re-added chapter keeps its read state")
        precondition(after.bookmark)
        precondition(after.progress == 100)
    }

    private static func unwrap<T>(_ value: T?) throws -> T {
        guard let value else { throw CheckFailure.missingValue }
        return value
    }

    private enum CheckFailure: Error {
        case missingValue
    }
}
