// V2PagePipelineChecks.swift - Chapter image cache and page prefetch ordering.
//
// Both are pure/headless, so they run on macOS: the cache against a temporary
// directory, the plan against plain integers.

import Foundation

@main
struct V2PagePipelineChecks {

    static func main() async throws {
        try await checkCacheRoundTrip()
        try await checkCacheEviction()
        try await checkCacheHitRefreshesRecency()
        try await checkCacheRemoval()
        checkPrefetchOrder()
        checkPrefetchEdges()
        checkNextChapterTrigger()
        try await checkLoaderDeduplicates()
        try await checkLoaderServesFromCache()
        try await checkLoaderReadsFileURLs()
        checkMangaProgress()
        print("PASS: chapter cache (round-trip, LRU eviction, hit refresh, removal), "
            + "page prefetch (order, clamping, next-chapter trigger), "
            + "loader (de-duplication, cache hits, file URLs) and manga progress")
    }

    // MARK: - Cache

    private static func makeCache(limit: Int = 4096) throws -> (ChapterCache, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "lnr-cache-check-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (ChapterCache(directory: directory, limitBytes: limit), directory)
    }

    private static func payload(_ size: Int, seed: UInt8) -> Data {
        Data(repeating: seed, count: size)
    }

    private static func checkCacheRoundTrip() async throws {
        let (cache, directory) = try makeCache()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = "https://cdn.example.com/page-1.jpg"
        let miss = await cache.data(for: url)
        let emptyBefore = await cache.contains(url)
        precondition(miss == nil, "empty cache must miss")
        precondition(!emptyBefore)

        let data = payload(512, seed: 7)
        await cache.store(data, for: url)

        let stored = await cache.data(for: url)
        let size = await cache.currentSizeBytes()
        let cached = await cache.contains(url)
        precondition(cached)
        precondition(stored == data, "cached bytes must round-trip")
        precondition(size == 512)

        // Same URL, same key; a different URL must not collide.
        precondition(ChapterCache.key(for: url) == ChapterCache.key(for: url))
        precondition(ChapterCache.key(for: url) != ChapterCache.key(for: url + "?v=2"))

        // Empty payloads are ignored rather than cached as zero-byte pages.
        let emptyURL = "https://cdn.example.com/empty.jpg"
        await cache.store(Data(), for: emptyURL)
        let emptyCached = await cache.contains(emptyURL)
        precondition(!emptyCached)
    }

    private static func checkCacheEviction() async throws {
        // Four 1000-byte pages against a 2500-byte limit.
        let (cache, directory) = try makeCache(limit: 2500)
        defer { try? FileManager.default.removeItem(at: directory) }

        let urls = (0..<4).map { "https://cdn.example.com/p\($0).jpg" }
        for (index, url) in urls.enumerated() {
            await cache.store(payload(1000, seed: UInt8(index + 1)), for: url)
            // Distinct modification dates, so LRU order is deterministic.
            try await Task.sleep(for: .milliseconds(20))
        }

        // 4000 bytes written, limit 2500 → trimmed back under the limit.
        let size = await cache.currentSizeBytes()
        precondition(size <= 2500, "cache must stay under its limit, is \(size)")

        let oldest = await cache.contains(urls[0])
        let newest = await cache.contains(urls[3])
        precondition(!oldest, "the oldest page is evicted first")
        precondition(newest, "the newest page survives")
    }

    private static func checkCacheHitRefreshesRecency() async throws {
        let (cache, directory) = try makeCache(limit: 2500)
        defer { try? FileManager.default.removeItem(at: directory) }

        let urls = (0..<3).map { "https://cdn.example.com/hit\($0).jpg" }
        for (index, url) in urls.enumerated() {
            await cache.store(payload(800, seed: UInt8(index + 1)), for: url)
            try await Task.sleep(for: .milliseconds(20))
        }

        // Read the oldest one, then overflow the cache.
        _ = await cache.data(for: urls[0])
        try await Task.sleep(for: .milliseconds(20))
        await cache.store(payload(800, seed: 9), for: "https://cdn.example.com/new.jpg")

        let read = await cache.contains(urls[0])
        let untouched = await cache.contains(urls[1])
        precondition(read, "a page that was just read must not be evicted")
        precondition(!untouched, "the untouched page becomes the oldest and is evicted")
    }

    private static func checkCacheRemoval() async throws {
        let (cache, directory) = try makeCache()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = "https://cdn.example.com/remove-me.jpg"
        await cache.store(payload(256, seed: 3), for: url)
        await cache.remove(url)

        let gone = await cache.contains(url)
        let emptySize = await cache.currentSizeBytes()
        precondition(!gone)
        precondition(emptySize == 0)

        await cache.store(payload(256, seed: 4), for: url)
        await cache.removeAll()
        let afterClear = await cache.currentSizeBytes()
        precondition(afterClear == 0)
    }

    // MARK: - Prefetch plan

    private static func checkPrefetchOrder() {
        // Middle of a long chapter: current first, then forward, then back.
        let plan = PagePrefetchPlan.loadOrder(current: 10, pageCount: 100, ahead: 3, behind: 1)
        precondition(plan.first == 10, "the current page is always first")
        precondition(plan == [10, 11, 9, 12, 13], "unexpected order: \(plan)")
        precondition(Set(plan).count == plan.count, "no duplicates")
    }

    private static func checkPrefetchEdges() {
        // First page: nothing before it.
        let start = PagePrefetchPlan.loadOrder(current: 0, pageCount: 20, ahead: 2, behind: 1)
        precondition(start == [0, 1, 2], "unexpected: \(start)")

        // Last page: nothing after it.
        let end = PagePrefetchPlan.loadOrder(current: 19, pageCount: 20, ahead: 3, behind: 1)
        precondition(end == [19, 18], "unexpected: \(end)")

        // Out-of-range inputs clamp instead of trapping.
        precondition(PagePrefetchPlan.loadOrder(current: -5, pageCount: 3, ahead: 1, behind: 1) == [0, 1])
        precondition(PagePrefetchPlan.loadOrder(current: 99, pageCount: 3, ahead: 1, behind: 1) == [2, 1])
        precondition(PagePrefetchPlan.loadOrder(current: 0, pageCount: 0).isEmpty)
        precondition(PagePrefetchPlan.loadOrder(current: 0, pageCount: 5, ahead: 0, behind: 0) == [0])
    }

    private static func checkNextChapterTrigger() {
        precondition(!PagePrefetchPlan.shouldPreloadNextChapter(current: 10, pageCount: 20))
        precondition(PagePrefetchPlan.shouldPreloadNextChapter(current: 15, pageCount: 20))
        precondition(PagePrefetchPlan.shouldPreloadNextChapter(current: 19, pageCount: 20))
        precondition(!PagePrefetchPlan.shouldPreloadNextChapter(current: 0, pageCount: 0))
    }

    // MARK: - Loader

    /// Counts fetches across concurrent callers.
    private final class FetchCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0

        func increment() {
            lock.lock()
            value += 1
            lock.unlock()
        }

        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }

    private static func checkLoaderDeduplicates() async throws {
        let (cache, directory) = try makeCache()
        defer { try? FileManager.default.removeItem(at: directory) }

        let counter = FetchCounter()
        let loader = PageLoader(cache: cache, fetcher: { page, _ in
            counter.increment()
            try await Task.sleep(for: .milliseconds(60))
            return Data(repeating: 4, count: 128)
        })

        let page = SourcePage(index: 0, url: "https://cdn.example.com/dupe.jpg")

        // Both callers ask for the same page at the same time.
        async let first = loader.image(for: page, sourceKey: "builtin:sample")
        async let second = loader.image(for: page, sourceKey: "builtin:sample")
        let a = try await first
        let b = try await second

        precondition(a == b, "both callers get the same bytes")
        precondition(counter.count == 1, "concurrent requests collapse into one fetch, got \(counter.count)")
    }

    private static func checkLoaderServesFromCache() async throws {
        let (cache, directory) = try makeCache()
        defer { try? FileManager.default.removeItem(at: directory) }

        let counter = FetchCounter()
        let loader = PageLoader(cache: cache, fetcher: { _, _ in
            counter.increment()
            return Data(repeating: 5, count: 64)
        })

        let page = SourcePage(index: 1, url: "https://cdn.example.com/once.jpg")
        _ = try await loader.image(for: page, sourceKey: "builtin:sample")
        _ = try await loader.image(for: page, sourceKey: "builtin:sample")

        precondition(counter.count == 1, "second load must come from the cache")
        let cached = await cache.contains(page.url)
        precondition(cached)
    }

    private static func checkLoaderReadsFileURLs() async throws {
        let (cache, directory) = try makeCache()
        defer { try? FileManager.default.removeItem(at: directory) }

        // A file:// page must never hit the fetcher.
        let file = directory.appending(path: "page.png")
        let payload = Data(repeating: 9, count: 32)
        try payload.write(to: file)

        let counter = FetchCounter()
        let loader = PageLoader(cache: cache, fetcher: { _, _ in
            counter.increment()
            return Data()
        })

        let page = SourcePage(index: 0, url: file.absoluteString)
        let data = try await loader.image(for: page, sourceKey: "builtin:sample")

        precondition(data == payload, "file pages are read from disk")
        precondition(counter.count == 0, "file pages must not go to the network")
    }

    // MARK: - Manga progress

    private static func checkMangaProgress() {
        let first = MangaProgress.update(pageIndex: 0, pageCount: 10)
        precondition(first.progress == 10)
        precondition(first.pagesLeft == 9)
        precondition(!first.finished)
        precondition(first.lastPageRead == 0)

        let middle = MangaProgress.update(pageIndex: 4, pageCount: 10)
        precondition(middle.progress == 50)
        precondition(middle.pagesLeft == 5)

        let last = MangaProgress.update(pageIndex: 9, pageCount: 10)
        precondition(last.progress == 100)
        precondition(last.pagesLeft == 0)
        precondition(last.finished, "only the last page finishes a chapter")

        // Out-of-range and empty chapters must not trap or report success.
        let clamped = MangaProgress.update(pageIndex: 99, pageCount: 10)
        precondition(clamped.lastPageRead == 9)
        precondition(clamped.finished)

        let empty = MangaProgress.update(pageIndex: 3, pageCount: 0)
        precondition(empty.progress == 0)
        precondition(!empty.finished)
        precondition(empty.pagesLeft == 0)
    }
}
