// PornPicsSource.swift - PornPics (pornpics.com), an explicit photo-gallery site.
//
// Port of keiyoushi's `all/pornpics`, English variant. Each gallery is one entry with a single
// "Gallery" chapter; the chapter's pages are the gallery's full-size image links.
//
// Entry urls are the gallery path (`/galleries/123456/`), which is what the Kotlin extension
// stores, so a Mihon `.tachibk` backup resolves onto this source.

import Foundation
import SwiftSoup

final class PornPicsSource: MangaSource {

    /// Upstream pins this id for the English source instead of deriving it from the name.
    static let mihonID: Int64 = 1_459_635_082_044_256_286

    let key = SourceKey.makeBuiltin(id: "pornpics")
    let kind = ContentKind.manga
    let name = "PornPics"
    let lang = "en"
    let iconAsset: String? = "PornPicsIcon"
    let isAdult = true
    let supportsLatest = true
    let filtersAreRemote = true

    func filtersAreComplete(_ filters: [SourceFilter]) -> Bool {
        let ids = Set(filters.map(\.id))
        return ["category", "tag", "star", "channel"].allSatisfy(ids.contains)
    }

    private let site = SiteClient(
        sourceKey: SourceKey.makeBuiltin(id: "pornpics"),
        baseURL: "https://www.pornpics.com"
    )

    /// Upstream asks for one more gallery than it shows, so a full page means there is a next one.
    private static let pageSize = 19
    private static let galleryLink = "#main li.thumbwook > a.rel-link"
    private static let jsonHeaders = ["Accept": "application/json"]

    // MARK: Filters

    private static let sortOptions = [
        FilterOption(id: "popular", name: "Popular"),
        FilterOption(id: "recent", name: "Recent"),
    ]

    private static let categoryTypes = [
        FilterOption(id: "categories", name: "Categories"),
        FilterOption(id: "tags", name: "Tags"),
        FilterOption(id: "stars", name: "Porn stars"),
        FilterOption(id: "channels", name: "Channels"),
    ]

    func filters() async throws -> [SourceFilter] {
        var result: [SourceFilter] = [
            .select(id: "sort", name: "Sort", options: Self.sortOptions, defaultOption: "popular"),
            .header(
                id: "browseHint",
                name: "With the search box empty, the category picked below is browsed"
            ),
            .select(
                id: "categoryType", name: "Category type",
                options: Self.categoryTypes, defaultOption: "categories"
            ),
        ]

        // The category lists are site data. A failed fetch leaves the sort filter usable.
        if let document = try? await site.html("/tags/") {
            let links = Self.links(in: document)
            Self.append(
                &result, id: "category", name: "Category",
                links: links.filter { !$0.id.contains("/tags/") }
            )
            Self.append(
                &result, id: "tag", name: "Tag",
                links: links.filter { $0.id.contains("/tags/") }
            )
        }
        if let document = try? await site.html("/pornstars/list/") {
            Self.append(&result, id: "star", name: "Porn star", links: Self.links(in: document))
        }
        if let document = try? await site.html("/channels/list/") {
            Self.append(&result, id: "channel", name: "Channel", links: Self.links(in: document))
        }
        return result
    }

    /// The `#main-list` links of a category page, de-duplicated and sorted by name.
    private static func links(in document: Document) -> [FilterOption] {
        guard let elements = try? document.select("#main-list .list-item > a") else { return [] }
        var seen = Set<String>()
        return elements.compactMap { element -> FilterOption? in
            guard let link = try? element.attr("href"), !link.isEmpty else { return nil }
            var name = (try? element.attr("title")) ?? ""
            if name.isEmpty { name = (try? element.text()) ?? "" }
            if name.isEmpty { name = link }
            guard seen.insert(link).inserted else { return nil }
            return FilterOption(id: link, name: name)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func append(
        _ filters: inout [SourceFilter], id: String, name: String, links: [FilterOption]
    ) {
        guard let first = links.first else { return }
        filters.append(.select(id: id, name: name, options: links, defaultOption: first.id))
    }

    // MARK: Browsing

    func popular(page: Int, filters: FilterState) async throws -> EntriesPage {
        try await listing(page: page, period: 1)
    }

    func latest(page: Int, filters: FilterState) async throws -> EntriesPage {
        try await listing(page: page, period: 2)
    }

    func search(query: String, page: Int, filters: FilterState) async throws -> EntriesPage {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return try await textSearch(trimmed, page: page, filters: filters) }
        if let category = Self.selectedCategory(filters) {
            return try await categoryListing(category, page: page, filters: filters)
        }
        return try await listing(page: page, period: Self.isRecent(filters) ? 2 : 1)
    }

    /// The "pics" listing: `period` 1 is popular, 2 is latest.
    private func listing(page: Int, period: Int) async throws -> EntriesPage {
        let path = "/popular/api/galleries/list/?limit=\(Self.pageSize + 1)"
            + "&offset=\(Self.offset(page))&lang=en&period=\(period)"
            + "&category_id=\(2585 + period)"
        let response = try await site.send(path, headers: Self.jsonHeaders)
        return entriesPage(from: try response.decoded([GalleryDTO].self))
    }

    private func textSearch(
        _ query: String, page: Int, filters: FilterState
    ) async throws -> EntriesPage {
        var path = "/search/srch.php?lang=en"
        if Self.isRecent(filters) { path += "&date=latest" }
        path += "&limit=\(Self.pageSize + 1)&offset=\(Self.offset(page))&q=\(query.queryEscaped)"
        let response = try await site.send(path, headers: Self.jsonHeaders)
        return entriesPage(from: try response.decoded([GalleryDTO].self))
    }

    /// Page one of a category is HTML; later pages return the same JSON the API does.
    private func categoryListing(
        _ path: String, page: Int, filters: FilterState
    ) async throws -> EntriesPage {
        // The link may come back absolute or site-relative; both become a path.
        var url = path.hasPrefix("http") ? path.sourceRelative : path
        if !url.hasPrefix("/") { url = "/" + url }
        if !url.hasSuffix("/") { url += "/" }
        if Self.isRecent(filters) { url += "recent/" }
        url += "?lang=en"
        if Self.isRecent(filters) { url += "&date=latest" }
        url += "&limit=\(Self.pageSize + 1)&offset=\(Self.offset(page))"

        if page > 1 {
            let response = try await site.send(url, headers: Self.jsonHeaders)
            return entriesPage(from: try response.decoded([GalleryDTO].self))
        }
        let document = try await site.html(url)
        return entriesPage(fromEntries: try entries(in: document))
    }

    private static func offset(_ page: Int) -> Int { (page - 1) * pageSize }

    private static func isRecent(_ filters: FilterState) -> Bool {
        if case .option(let value)? = filters["sort"] { return value == "recent" }
        return false
    }

    /// The href of the category the type selector points at, `nil` when none is picked.
    private static func selectedCategory(_ filters: FilterState) -> String? {
        guard case .option(let type)? = filters["categoryType"] else { return nil }
        let id: String
        switch type {
        case "tags": id = "tag"
        case "stars": id = "star"
        case "channels": id = "channel"
        default: id = "category"
        }
        guard case .option(let link)? = filters[id], !link.isEmpty else { return nil }
        return link
    }

    // MARK: Details

    func details(_ entry: SourceEntry) async throws -> SourceEntry {
        let document = try await site.html(entry.url)
        let image = Self.firstElement(in: document, selector: "\(Self.galleryLink) img")
        let alt = Self.attribute(of: image, named: "alt")
        let thumbnail = Self.attribute(of: image, named: "data-src").map(site.absolute)
        let info = Self.firstElement(in: document, selector: "div.gallery-info.to-gall-info")

        let authors = Self.texts(info, "div.gallery-info__item:nth-child(2) a")
        let genres = Self.texts(info, "div.gallery-info__item:not(:nth-child(2)) a")
        let description = Self.texts(info, ".info-rate, .info-views").joined(separator: " ")

        return SourceEntry(
            sourceKey: key,
            kind: kind,
            url: entry.url,
            title: document.firstText(".gallery-title h1") ?? alt ?? entry.title,
            thumbnailURL: entry.thumbnailURL ?? thumbnail,
            author: authors.isEmpty ? nil : authors.joined(separator: ", "),
            artist: nil,
            description: description.isEmpty ? nil : description,
            genres: genres,
            status: .completed
        )
    }

    func chapters(_ entry: SourceEntry) async throws -> [SourceChapter] {
        [SourceChapter(url: entry.url, name: "Gallery", chapterNumber: 1)]
    }

    // MARK: Pages

    func pages(_ chapter: SourceChapter) async throws -> [SourcePage] {
        let document = try await site.html(chapter.url)
        guard let anchors = try? document.select(Self.galleryLink) else { return [] }
        var pages: [SourcePage] = []
        for anchor in anchors {
            guard let href = try? anchor.absUrl("href"), !href.isEmpty else { continue }
            pages.append(
                SourcePage(
                    index: pages.count, url: href, headers: ["Referer": site.baseURL + "/"]
                )
            )
        }
        return pages
    }

    // MARK: Parsing

    private func entries(in document: Document) throws -> [SourceEntry] {
        try document.select(Self.galleryLink).compactMap { element -> SourceEntry? in
            guard let href = try? element.absUrl("href"), !href.isEmpty else { return nil }
            let image = Self.firstElement(in: element, selector: "img")
            let alt = Self.attribute(of: image, named: "alt")
            let thumbnail = Self.attribute(of: image, named: "data-src").map(site.absolute)
            let relative = href.sourceRelative
            return SourceEntry(
                sourceKey: key,
                kind: kind,
                url: relative,
                title: alt ?? relative,
                thumbnailURL: thumbnail
            )
        }
    }

    private func entriesPage(from galleries: [GalleryDTO]) -> EntriesPage {
        entriesPage(fromEntries: galleries.map { gallery in
            let thumbnail = gallery.thumbnailUrl.isEmpty
                ? nil
                : site.absolute(gallery.thumbnailUrl)
            return SourceEntry(
                sourceKey: key,
                kind: kind,
                url: gallery.url.sourceRelative,
                title: gallery.title,
                thumbnailURL: thumbnail
            )
        })
    }

    /// A full page carries the extra probe item, which is dropped before display.
    private func entriesPage(fromEntries entries: [SourceEntry]) -> EntriesPage {
        let hasNext = entries.count > Self.pageSize
        return EntriesPage(
            entries: hasNext ? Array(entries.dropLast()) : entries,
            hasNextPage: hasNext
        )
    }

    private static func firstElement(in root: Element, selector: String) -> Element? {
        (try? root.select(selector))?.first()
    }

    private static func attribute(of element: Element?, named name: String) -> String? {
        guard let element, let value = try? element.attr(name) else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func texts(_ root: Element?, _ selector: String) -> [String] {
        guard let root, let elements = try? root.select(selector) else { return [] }
        return elements.compactMap { try? $0.text() }.filter { !$0.isEmpty }
    }
}

// MARK: - API shape

/// One gallery from `/popular/api/galleries/list/` and `/search/srch.php`.
private struct GalleryDTO: Decodable, Sendable {

    let desc: String
    let url: String
    let thumbnailUrl: String

    enum CodingKeys: String, CodingKey {
        case desc
        case url = "g_url"
        case thumbnailUrl = "t_url"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        desc = (try? container.decode(String.self, forKey: .desc)) ?? ""
        url = (try? container.decode(String.self, forKey: .url)) ?? ""
        thumbnailUrl = (try? container.decode(String.self, forKey: .thumbnailUrl)) ?? ""
    }

    /// Upstream falls back to the url slug when the site sends no description.
    var title: String {
        if !desc.isEmpty { return desc }
        let slug = url.split(separator: "/").last.map(String.init) ?? ""
        let words = slug.split(separator: "-")
            .map(String.init)
            .filter { word in !word.allSatisfy { $0.isNumber } }
        guard let first = words.first else { return slug }
        let head = first.prefix(1).uppercased() + String(first.dropFirst())
        return ([head] + words.dropFirst()).joined(separator: " ")
    }
}
