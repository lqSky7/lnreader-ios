// AllMangaLiveChecks.swift - Drives the real AllManga bundle through the host.
//
// Network-dependent, so it is not part of the regular check suite; run it with
// scripts/try-allmanga.sh. The page list goes through WebViewCapture, so this is
// the check that proves the web view path works against the live site.

import Foundation
#if canImport(AppKit)
import AppKit
#endif

@main
struct AllMangaLiveChecks {

    static func main() async throws {
        setvbuf(stdout, nil, _IOLBF, 0)
        #if canImport(AppKit)
        // WebKit wants an application object even for a headless web view.
        await MainActor.run { NSApplication.shared.setActivationPolicy(.accessory) }
        #endif

        guard let bundlePath = ProcessInfo.processInfo.environment["MANGA_BUNDLE"],
              let bundle = try? String(contentsOfFile: bundlePath, encoding: .utf8)
        else {
            fatalError("MANGA_BUNDLE is not set")
        }

        let manifest = ExtensionManifest(
            pkg: "all.allmanga",
            name: "AllManga",
            lang: "en",
            versionId: 1,
            iconURL: nil,
            bundlePath: "allmanga.js",
            kind: .manga
        )
        let source = try JSBundleMangaSource(manifest: manifest, bundle: bundle)
        precondition(source.key == "mihon:all.allmanga")

        let popular = try await source.popular(page: 1, filters: FilterState())
        precondition(!popular.entries.isEmpty, "popular returned nothing")
        print("popular: \(popular.entries.count) entries, hasNext=\(popular.hasNextPage)")

        let latest = try await source.latest(page: 1, filters: FilterState())
        precondition(!latest.entries.isEmpty, "latest returned nothing")
        print("latest: \(latest.entries.count) entries")

        let found = try await source.search(query: "solo leveling", page: 1, filters: FilterState())
        precondition(!found.entries.isEmpty, "search returned nothing")
        print("search: \(found.entries.count) entries, first=\(found.entries[0].title)")

        // The entry restored from a Mihon backup uses this exact URL shape.
        let target = SourceEntry(
            sourceKey: source.key, kind: .manga,
            url: ProcessInfo.processInfo.environment["MANGA_ENTRY"]
                ?? "/manga/skAAqyMtTckrjjsi3/my-blasted-reincarnated-life",
            title: "")
        let details = try await source.details(target)
        precondition(!details.title.isEmpty)
        print("details: \(details.title), status=\(details.status), genres=\(details.genres.prefix(4))")

        let chapters = try await source.chapters(details)
        precondition(!chapters.isEmpty, "chapters returned nothing")
        let first = chapters[chapters.count - 1]
        print("chapters: \(chapters.count), first=\(first.name) #\(first.chapterNumber) \(first.url) date=\(String(describing: first.dateUpload))")
        precondition(first.chapterNumber > 0, "chapter numbers were not parsed")

        let started = Date()
        let pages: [SourcePage]
        do {
            pages = try await source.pages(first)
        } catch {
            // The site asks a person to pass a check before it serves pages, and a
            // command-line run has nobody to do that. Say so rather than pass.
            print("catalogue: OK (popular, latest, search, details, chapters)")
            print("pages: NOT VERIFIED — \(error.localizedDescription)")
            exit(2)
        }
        precondition(!pages.isEmpty, "pages returned nothing")
        print("pages: \(pages.count) in \(String(format: "%.1f", Date().timeIntervalSince(started)))s, first=\(pages[0].url)")
        precondition(pages[0].url.hasPrefix("http"), "page URL is not absolute")

        // The first image must actually be fetchable with the headers we hand out.
        var request = URLRequest(url: URL(string: pages[0].url)!)
        for (name, value) in pages[0].headers { request.setValue(value, forHTTPHeaderField: name) }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        print("image: HTTP \(status), \(data.count) bytes")
        precondition(status == 200 && data.count > 1000, "first page image did not load")

        print("PASS: AllManga — popular, latest, search, details, chapters and web view pages over the live site")
    }
}
