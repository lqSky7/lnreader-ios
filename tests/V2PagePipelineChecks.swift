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
        print("PASS: chapter cache (round-trip, LRU eviction, hit refresh, removal) "
            + "and page prefetch (order, clamping, next-chapter trigger)")
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
}
