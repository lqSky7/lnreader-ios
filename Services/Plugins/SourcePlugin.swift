import Foundation

// MARK: - Core Data Types

/// Partial novel info returned from search or browse results.
struct PartialNovel: Identifiable, Hashable, Sendable {
    /// Unique identifier derived from the novel's path.
    let id: String
    /// Display name of the novel.
    let name: String
    /// Source-relative path used to fetch full novel details.
    let path: String
    /// Optional URL string for the novel's cover image.
    let cover: String?

    init(name: String, path: String, cover: String? = nil) {
        self.id = path
        self.name = name
        self.path = path
        self.cover = cover
    }
}

/// Full novel info returned from `parseNovel`.
struct SourceNovel: Sendable {
    let name: String
    let path: String
    let cover: String?
    let genres: String?
    let summary: String?
    let author: String?
    let artist: String?
    let status: String?
    let chapters: [SourceChapter]
    /// Total number of paginated chapter pages, if the source paginates.
    let totalPages: Int?
}

/// Chapter info returned from a source plugin.
struct SourceChapter: Identifiable, Sendable {
    /// Unique identifier derived from the chapter's path.
    let id: String
    /// Display name of the chapter.
    let name: String
    /// Source-relative path used to fetch chapter content.
    let path: String
    /// Optional numeric chapter ordering value.
    let chapterNumber: Double?
    /// Optional human-readable release date string.
    let releaseTime: String?
    /// Optional page identifier for paginated chapter lists.
    let page: String?

    init(
        name: String,
        path: String,
        chapterNumber: Double? = nil,
        releaseTime: String? = nil,
        page: String? = nil
    ) {
        self.id = path
        self.name = name
        self.path = path
        self.chapterNumber = chapterNumber
        self.releaseTime = releaseTime
        self.page = page
    }
}

/// Result from `parsePage` — one page of a paginated chapter list.
struct SourcePage: Sendable {
    let chapters: [SourceChapter]
}

// MARK: - Image Request Init

/// Custom HTTP configuration for image/cover requests.
/// Mirrors Android's `Plugin.imageRequestInit` — some CDNs require a custom
/// Referer, authorization token, or non-default User-Agent to serve images.
struct ImageRequestInit: Sendable {
    let method: String?
    let headers: [String: String]

    static let `default` = ImageRequestInit(method: nil, headers: [:])
}

// MARK: - Filter Types

/// A single selectable option within a filter (the value sent to the source).
struct FilterOption: Sendable, Identifiable, Equatable, Hashable {
    let label: String
    let value: String
    var id: String { value }
}

/// A filter definition parsed from the plugin's `filters` property.
enum PluginFilter: Sendable, Identifiable {
    case textInput(key: String, label: String, defaultValue: String)
    case picker(key: String, label: String, defaultValue: String, options: [FilterOption])
    case checkboxGroup(key: String, label: String, defaultValues: [String], options: [FilterOption])
    case switchFilter(key: String, label: String, defaultValue: Bool)
    case excludableCheckboxGroup(
        key: String,
        label: String,
        defaultInclude: [String],
        defaultExclude: [String],
        options: [FilterOption]
    )

    var id: String { key }

    var key: String {
        switch self {
        case .textInput(let k, _, _),
            .picker(let k, _, _, _),
            .checkboxGroup(let k, _, _, _),
            .switchFilter(let k, _, _),
            .excludableCheckboxGroup(let k, _, _, _, _):
            return k
        }
    }

    var label: String {
        switch self {
        case .textInput(_, let l, _),
            .picker(_, let l, _, _),
            .checkboxGroup(_, let l, _, _),
            .switchFilter(_, let l, _),
            .excludableCheckboxGroup(_, let l, _, _, _):
            return l
        }
    }
}

/// The currently-selected value for one filter, passed to `popularNovels`.
enum SelectedFilterValue: Sendable {
    case text(String)
    case picker(String)
    case checkbox([String])
    case switchVal(Bool)
    case excludable(include: [String], exclude: [String])
}

/// Map of filter key → selected value passed to `popularNovels`.
typealias FilterValues = [String: SelectedFilterValue]

// MARK: - Plugin Settings

/// A user-configurable setting exposed by a plugin (API key, region, content filter, etc.).
enum PluginSetting: Sendable, Identifiable {
    case text(key: String, label: String, value: String)
    case switchSetting(key: String, label: String, value: Bool)
    case select(key: String, label: String, value: String, options: [FilterOption])
    case checkboxGroup(key: String, label: String, values: [String], options: [FilterOption])

    var id: String { key }

    var key: String {
        switch self {
        case .text(let k, _, _),
            .switchSetting(let k, _, _),
            .select(let k, _, _, _),
            .checkboxGroup(let k, _, _, _):
            return k
        }
    }

    var label: String {
        switch self {
        case .text(_, let l, _),
            .switchSetting(_, let l, _),
            .select(_, let l, _, _),
            .checkboxGroup(_, let l, _, _):
            return l
        }
    }
}

// MARK: - Protocol

/// A content source plugin that can browse, search, and read novels.
///
/// Conforming types fetch data from a particular website and return
/// normalized novel/chapter structures the app can display.
protocol SourcePlugin: Identifiable {
    /// Unique plugin identifier (e.g. `"readnovelfull"`).
    var id: String { get }
    /// Human-readable source name.
    var name: String { get }
    /// URL string for the plugin's icon image.
    var iconURL: String { get }
    /// Base URL of the source website.
    var siteURL: String { get }
    /// Display language of the source (e.g. `"English"`, `"العربية"`).
    var language: String { get }
    /// Semantic version of the plugin (e.g. `"2.2.0"`).
    var version: String { get }

    // MARK: Required Methods

    /// Browse popular (or latest) novels with optional browse filters.
    func popularNovels(
        page: Int,
        showLatest: Bool,
        filterValues: FilterValues?
    ) async throws -> [PartialNovel]

    /// Search novels by text query with pagination.
    func searchNovels(query: String, page: Int) async throws -> [PartialNovel]

    /// Fetch full novel details including chapter list.
    func parseNovel(path: String) async throws -> SourceNovel

    /// Fetch chapter HTML/text content.
    func parseChapter(path: String) async throws -> String
}

// MARK: - Default Implementations

extension SourcePlugin {

    // MARK: Convenience wrappers

    /// Convenience — browse popular novels with no filters (backward-compatible).
    func popularNovels(page: Int) async throws -> [PartialNovel] {
        try await popularNovels(page: page, showLatest: false, filterValues: nil)
    }

    // MARK: Optional Capabilities (overridden by JSSourcePlugin)

    /// Filter definitions exposed by this plugin. Empty if the plugin has none.
    var filters: [PluginFilter] { [] }

    /// Custom HTTP headers / method for image (cover) requests.
    var imageRequestInit: ImageRequestInit { .default }

    /// Whether this plugin requires a WebView login session
    /// (e.g. Patreon-gated or subscription-only sources).
    var webStorageUtilized: Bool { false }

    /// User-configurable plugin settings (API keys, region, adult content, etc.).
    var pluginSettings: [PluginSetting] { [] }

    /// Whether this plugin implements `parsePage` for paginated chapter lists.
    var hasParsePage: Bool { false }

    /// Resolve a source-relative path to a full absolute URL.
    ///
    /// Default implementation prepends `siteURL` for relative paths.
    func resolveUrl(path: String, isNovel: Bool) -> String {
        if path.hasPrefix("http://") || path.hasPrefix("https://") || path.hasPrefix("//") {
            return path
        }
        let base = siteURL.hasSuffix("/") ? String(siteURL.dropLast()) : siteURL
        let suffix = path.hasPrefix("/") ? path : "/\(path)"
        return base + suffix
    }

    /// Fetch one page of a paginated chapter list.
    ///
    /// Default returns an empty page; `JSSourcePlugin` overrides when
    /// the underlying JS plugin exposes `parsePage`.
    func parsePage(path: String, page: String) async throws -> SourcePage {
        SourcePage(chapters: [])
    }

    /// Fetch all chapters for a novel concurrently with concurrency throttling.
    func fetchAllChapters(path: String, totalPages: Int) async throws -> [SourceChapter] {
        print("📚 [\(id)] fetchAllChapters: path=\(path), totalPages=\(totalPages)")
        let maxConcurrent = 4
        var pagesData = [Int: [SourceChapter]]()

        try await withThrowingTaskGroup(of: (Int, [SourceChapter]).self) { group in
            var pageToFetch = 1

            // Spawn initial concurrent tasks
            for _ in 0..<min(maxConcurrent, totalPages) {
                let p = pageToFetch
                pageToFetch += 1
                group.addTask {
                    let pageResult = try await self.parsePage(path: path, page: String(p))
                    print("📚 [\(self.id)] Page \(p): \(pageResult.chapters.count) chapters")
                    return (p, pageResult.chapters)
                }
            }

            // As each finishes, spawn the next page task
            while let (p, chapters) = try await group.next() {
                pagesData[p] = chapters
                if pageToFetch <= totalPages {
                    let nextP = pageToFetch
                    pageToFetch += 1
                    group.addTask {
                        let pageResult = try await self.parsePage(path: path, page: String(nextP))
                        print("📚 [\(self.id)] Page \(nextP): \(pageResult.chapters.count) chapters")
                        return (nextP, pageResult.chapters)
                    }
                }
            }
        }

        // Determine page ordering: oldest first (1...N) or latest first (N...1)
        var shouldReversePages = false
        if totalPages > 1,
           let page1Chapters = pagesData[1], !page1Chapters.isEmpty,
           let lastPageChapters = pagesData[totalPages], !lastPageChapters.isEmpty {

            let firstOfPage1 = page1Chapters.first!
            let firstOfLastPage = lastPageChapters.first!

            if let num1 = firstOfPage1.chapterNumber, let numLast = firstOfLastPage.chapterNumber {
                shouldReversePages = num1 > numLast
            } else {
                let path1 = firstOfPage1.path
                let pathLast = firstOfLastPage.path
                shouldReversePages = path1.localizedStandardCompare(pathLast) == .orderedDescending
            }
        }

        // Construct the full chapters list.
        var allChapters: [SourceChapter] = []
        let pageRange = 1...totalPages
        let orderedPages = shouldReversePages ? Array(pageRange.reversed()) : Array(pageRange)

        for p in orderedPages {
            if let chapters = pagesData[p] {
                let taggedChapters = chapters.map { ch in
                    SourceChapter(
                        name: ch.name,
                        path: ch.path,
                        chapterNumber: ch.chapterNumber,
                        releaseTime: ch.releaseTime,
                        page: String(p)
                    )
                }
                allChapters.append(contentsOf: taggedChapters)
            }
        }
        print("📚 [\(id)] fetchAllChapters complete: \(allChapters.count) total chapters, reversed=\(shouldReversePages)")
        return allChapters
    }
}
