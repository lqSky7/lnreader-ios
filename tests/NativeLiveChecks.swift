// NativeLiveChecks.swift - Runs native sources against their live sites.
//
// Network-dependent; run with scripts/try-native.sh. Prints one line per source:
// `PASS <key> <summary>` or `FAIL <key> <step>: <error>`. Exit status is always 0.

import Foundation

@main
struct NativeLiveChecks {

    static func main() async {
        let env = ProcessInfo.processInfo.environment
        let wanted = (env["SOURCES"] ?? "").split(separator: ",").map { String($0) }
        let query = env["QUERY"] ?? "love"
        for source in NativeSources.all() {
            if !wanted.isEmpty && !wanted.contains(where: { source.key.hasSuffix($0) }) { continue }
            print(await check(source, query: query))
        }
    }

    private static func check(_ source: any CatalogSource, query: String) async -> String {
        var step = "popular"
        do {
            let popular = try await withTimeout { try await source.popular(page: 1, filters: FilterState()) }
            guard let first = popular.entries.first else { return "FAIL \(source.key) popular: empty" }

            step = "latest"
            var latestCount = -1
            if source.supportsLatest {
                latestCount = try await withTimeout { try await source.latest(page: 1, filters: FilterState()) }.entries.count
            }

            step = "search"
            let found = try await withTimeout { try await source.search(query: query, page: 1, filters: FilterState()) }
            if found.entries.isEmpty { return "FAIL \(source.key) search: no results for \(query)" }

            step = "details"
            let detailed = try await withTimeout { try await source.details(first) }
            if detailed.title.isEmpty { return "FAIL \(source.key) details: empty title" }

            step = "chapters"
            let chapters = try await withTimeout { try await source.chapters(first) }
            guard let chapter = chapters.last ?? chapters.first else {
                return "FAIL \(source.key) chapters: empty for \(first.url)"
            }

            var tail = ""
            if let manga = source as? any MangaSource {
                step = "pages"
                let pages = try await withTimeout { try await manga.pages(chapter) }
                if pages.isEmpty { return "FAIL \(source.key) pages: empty for \(chapter.url)" }
                step = "image"
                let request = try await manga.imageRequest(pages[0])
                let (data, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status != 200 || data.count < 1000 { return "FAIL \(source.key) image: HTTP \(status), \(data.count) bytes" }
                tail = "pages=\(pages.count) image=\(data.count)B"
            } else if let novel = source as? any NovelSource {
                step = "chapterHTML"
                let html = try await withTimeout { try await novel.chapterHTML(chapter) }
                if html.count < 200 { return "FAIL \(source.key) chapterHTML: \(html.count) chars for \(chapter.url)" }
                tail = "html=\(html.count) chars"
            }
            return "PASS \(source.key) popular=\(popular.entries.count) latest=\(latestCount) search=\(found.entries.count) "
                + "chapters=\(chapters.count) \(tail) first=\(first.url)"
        } catch {
            return "FAIL \(source.key) \(step): \(error.localizedDescription)"
        }
    }

    private static func withTimeout<T: Sendable>(
        seconds: Double = 60, _ work: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await work() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw SourceError.emptyResponse("response within \(Int(seconds))s")
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }
}
