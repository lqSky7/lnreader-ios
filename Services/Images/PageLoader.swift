// PageLoader.swift - Fetches, caches and de-duplicates chapter page images.
//
// Swift owns all image I/O: the source only produces URLs (and occasionally
// headers), which is what keeps a JS extension from ever touching image bytes.

import Foundation

/// Loads page images through `ChapterCache`.
///
/// Three responsibilities, all of which need to be single-instance per reader:
/// - serve from cache when possible,
/// - collapse concurrent requests for the same page into one fetch (the pager
///   and the prefetch both ask for page N at the same moment),
/// - read `file://` pages straight from disk, which is how local books, CBZ
///   archives and the offline sample source are served.
actor PageLoader {

    struct Configuration: Sendable {
        /// Pages to prefetch ahead of the current one.
        var ahead = 6
        /// Pages to keep behind, for scrolling back.
        var behind = 1

        static let `default` = Configuration()
    }

    /// Fetches a non-file page. Injected so tests never touch the network.
    typealias Fetcher = @Sendable (SourcePage, String) async throws -> Data

    private let cache: ChapterCache
    private let configuration: Configuration
    private let fetcher: Fetcher

    /// One entry per page currently being fetched.
    private var inFlight: [String: Task<Data, Error>] = [:]

    init(
        cache: ChapterCache = .shared,
        configuration: Configuration = .default,
        fetcher: Fetcher? = nil
    ) {
        self.cache = cache
        self.configuration = configuration
        self.fetcher = fetcher ?? PageLoader.httpFetcher
    }

    // MARK: - Loading

    /// Bytes for one page, from cache when possible.
    func image(for page: SourcePage, sourceKey: String) async throws -> Data {
        let key = page.url

        if let cached = await cache.data(for: key) {
            return cached
        }
        // Someone is already fetching this page: join them instead of issuing
        // a second request.
        if let existing = inFlight[key] {
            return try await existing.value
        }

        let task = Task<Data, Error> { [cache, fetcher] in
            let data = try await PageLoader.load(page, sourceKey: sourceKey, fetcher: fetcher)
            await cache.store(data, for: key)
            return data
        }
        inFlight[key] = task

        defer { inFlight[key] = nil }
        return try await task.value
    }

    /// Start loading the pages around `current` without waiting for them.
    ///
    /// Failures are ignored on purpose: prefetching is an optimisation, and a
    /// failed prefetch must not surface as a reader error.
    func prefetch(_ pages: [SourcePage], current: Int, sourceKey: String) {
        let order = PagePrefetchPlan.loadOrder(
            current: current,
            pageCount: pages.count,
            ahead: configuration.ahead,
            behind: configuration.behind
        )

        for index in order {
            let page = pages[index]
            if inFlight[page.url] != nil { continue }
            Task { [weak self] in
                _ = try? await self?.image(for: page, sourceKey: sourceKey)
            }
        }
    }

    // MARK: - Fetching

    private static func load(
        _ page: SourcePage,
        sourceKey: String,
        fetcher: Fetcher
    ) async throws -> Data {
        // Local books, CBZ archives and the sample source hand back file URLs.
        if let url = URL(string: page.url), url.isFileURL {
            do {
                return try Data(contentsOf: url)
            } catch {
                throw HTTPError.transport("Could not read \(url.lastPathComponent)")
            }
        }
        return try await fetcher(page, sourceKey)
    }

    /// Default fetcher: one request through the shared HTTP stack, with the
    /// per-page headers a CDN may require.
    private static let httpFetcher: Fetcher = { page, sourceKey in
        guard let url = URL(string: page.url) else {
            throw HTTPError.invalidURL(page.url)
        }
        let request = HTTPRequest(url: url, headers: page.headers)
        return try await HTTPClient.shared.send(request, sourceKey: sourceKey).data
    }
}
