// MangaFireLiveChecks.swift - Drives the real MangaFire bundle through the host.
//
// Network-dependent, so it is not part of the regular check suite; run it with
// scripts/try-mangafire.sh. It exercises exactly the path the app takes: bundle
// -> JSC -> HTTP bridge -> adapter -> SourceEntry/Chapter/Page.

import Foundation

@main
struct MangaFireLiveChecks {

    static func main() async throws {
        guard let bundlePath = ProcessInfo.processInfo.environment["MANGA_BUNDLE"],
              let bundle = try? String(contentsOfFile: bundlePath, encoding: .utf8)
        else {
            fatalError("MANGA_BUNDLE is not set")
        }

        let manifest = ExtensionManifest(
            pkg: "all.mangafire",
            name: "MangaFire",
            lang: "en",
            versionId: 1,
            iconURL: nil,
            bundlePath: "mangafire.js",
            kind: .manga
        )
        let source = try JSBundleMangaSource(manifest: manifest, bundle: bundle)
        precondition(source.key == "mihon:all.mangafire")

        // Popular
        let popular = try await source.popular(page: 1, filters: FilterState())
        precondition(!popular.entries.isEmpty, "popular returned nothing")
        print("popular: \(popular.entries.count) entries, hasNext=\(popular.hasNextPage)")
        for entry in popular.entries.prefix(3) {
            print("  - \(entry.title)  [\(entry.url)]  \(entry.thumbnailURL ?? "no cover")")
        }

        // Latest
        let latest = try await source.latest(page: 1, filters: FilterState())
        precondition(!latest.entries.isEmpty, "latest returned nothing")
        print("latest: \(latest.entries.count) entries")

        // Search
        let found = try await source.search(query: "solo leveling", page: 1, filters: FilterState())
        precondition(!found.entries.isEmpty, "search returned nothing")
        print("search('solo leveling'): \(found.entries.count) entries, first=\(found.entries[0].title)")

        // Details
        let target = try unwrap(found.entries.first)
        let details = try await source.details(target)
        precondition(!details.title.isEmpty)
        print("details: \(details.title), status=\(details.status), genres=\(details.genres.prefix(4))")
        precondition(!details.genres.isEmpty, "details returned no genres")

        // Chapters
        let chapters = try await source.chapters(details)
        precondition(!chapters.isEmpty, "chapters returned nothing")
        print("chapters: \(chapters.count), first=\(chapters[0].name) #\(chapters[0].chapterNumber)")
        precondition(chapters[0].chapterNumber > 0, "chapter numbers were not parsed")

        // Pages
        let pages = try await source.pages(try unwrap(chapters.first))
        precondition(!pages.isEmpty, "pages returned nothing")
        print("pages: \(pages.count), first=\(pages[0].url.prefix(60))…")
        precondition(pages[0].url.hasPrefix("http"), "page URL is not absolute")

        print("PASS: MangaFire — popular, latest, search, details, chapters, pages over the live API")
    }

    private static func unwrap<T>(_ value: T?) throws -> T {
        guard let value else { throw CheckFailure.missingValue }
        return value
    }

    private enum CheckFailure: Error {
        case missingValue
    }
}
