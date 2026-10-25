// SourceMigrationChecks.swift - The `ln:` / `mihon:` -> `builtin:` source key migration.
//
// Builds a store, a downloaded chapter and per-series settings under old keys, runs the migration, and
// checks that all three followed and that a second launch does nothing. Touches the real
// UserDefaults and Application Support under unique names, and cleans them up.

import Foundation
import SwiftData

@main
struct SourceMigrationChecks {

    @MainActor
    static func main() throws {
        let tag = UUID().uuidString
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "migration.nativeSources.done")

        let schema = Schema(versionedSchema: SchemaV1.self)
        let container = try ModelContainer(
            for: schema, migrationPlan: LNReaderSchemaMigrationPlan.self,
            configurations: ModelConfiguration(tag, schema: schema, isStoredInMemoryOnly: true))
        let context = ModelContext(container)

        let novel = Entry(kind: .novel, sourceKey: "ln:novelfire", url: "book/\(tag)", title: "Novel")
        let manga = Entry(kind: .manga, sourceKey: "mihon:all.mangafire", url: "/manga/\(tag)", title: "Manga")
        let clash = Entry(kind: .manga, sourceKey: "mihon:all.allmanga", url: "/manga/clash", title: "Old")
        let existing = Entry(kind: .manga, sourceKey: "builtin:allmanga", url: "/manga/clash", title: "New")
        let orphan = Entry(kind: .novel, sourceKey: "ln:readnovelfull", url: "novel/x", title: "Orphan")
        let local = Entry(kind: .novel, sourceKey: SourceKey.local, url: "local://\(tag)", title: "Local")
        for entry in [novel, manga, clash, existing, orphan, local] { context.insert(entry) }
        try context.save()

        // A downloaded chapter under the old key.
        let chapterURL = "book/\(tag)/chapter-1"
        let oldFolder = OfflineChapters.folder(sourceKey: "ln:novelfire", entryURL: novel.url, chapterURL: chapterURL)
        try FileManager.default.createDirectory(at: oldFolder, withIntermediateDirectories: true)
        try Data("<p>text</p>".utf8).write(to: oldFolder.appendingPathComponent("chapter.html"))
        let manifest = OfflineChapters.Manifest(
            sourceKey: "ln:novelfire", entryURL: novel.url, chapterURL: chapterURL, kind: .novel, files: ["chapter.html"])
        try JSONEncoder().encode(manifest).write(to: oldFolder.appendingPathComponent("manifest.json"))
        expect(OfflineChapters.novel(sourceKey: "ln:novelfire", entryURL: novel.url, chapterURL: chapterURL) != nil, "fixture readable under the old key")

        defaults.set(Data("a".utf8), forKey: "scanlators.ln:novelfire::\(novel.url)")
        defaults.set(Data("b".utf8), forKey: "mangareader.mihon:all.mangafire::\(manga.url)")

        let summary = LegacySourceMigration.runIfNeeded(context: context)
        let result = try unwrap(summary)

        expect(novel.sourceKey == "builtin:novelfire", "novel key moved")
        expect(manga.sourceKey == "builtin:mangafire", "manga key moved")
        expect(clash.sourceKey == "mihon:all.allmanga" && existing.sourceKey == "builtin:allmanga", "a clash leaves both alone")
        expect(orphan.sourceKey == "ln:readnovelfull" && local.sourceKey == SourceKey.local, "unported and local keys untouched")
        expect(result.entriesMoved == 2 && result.entriesConflicting == 1, "entry counts")
        expect(result.orphaned == ["ln:readnovelfull": 1], "orphans reported")

        expect(OfflineChapters.novel(sourceKey: "builtin:novelfire", entryURL: novel.url, chapterURL: chapterURL) == "<p>text</p>", "download followed the key")
        expect(!FileManager.default.fileExists(atPath: oldFolder.path), "old download folder gone")
        expect(result.downloadsMoved >= 1, "download counted")

        expect(defaults.data(forKey: "scanlators.builtin:novelfire::\(novel.url)") == Data("a".utf8), "scanlator rules moved")
        expect(defaults.data(forKey: "mangareader.builtin:mangafire::\(manga.url)") == Data("b".utf8), "reader overrides moved")
        expect(defaults.object(forKey: "scanlators.ln:novelfire::\(novel.url)") == nil, "old settings key removed")

        expect(LegacySourceMigration.runIfNeeded(context: context) == nil, "second launch does nothing")

        // Clean up.
        try? FileManager.default.removeItem(at: OfflineChapters.folder(sourceKey: "builtin:novelfire", entryURL: novel.url, chapterURL: chapterURL))
        defaults.removeObject(forKey: "scanlators.builtin:novelfire::\(novel.url)")
        defaults.removeObject(forKey: "mangareader.builtin:mangafire::\(manga.url)")
        defaults.removeObject(forKey: "migration.nativeSources.done")
        print("PASS: source migration — keys, downloads, settings, clash, orphans, idempotent")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError("FAIL: \(message)") }
    }

    private static func unwrap<T>(_ value: T?) throws -> T {
        guard let value else { fatalError("FAIL: expected a value") }
        return value
    }
}
