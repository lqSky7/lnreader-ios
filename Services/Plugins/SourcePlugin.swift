import Foundation

// MARK: - Data Types

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

    /// Browse popular novels with pagination.
    func popularNovels(page: Int) async throws -> [PartialNovel]

    /// Search novels by query with pagination.
    func searchNovels(query: String, page: Int) async throws -> [PartialNovel]

    /// Fetch full novel details including chapter list.
    func parseNovel(path: String) async throws -> SourceNovel

    /// Fetch chapter HTML content.
    func parseChapter(path: String) async throws -> String
}
