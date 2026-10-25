// HeanCmsSource.swift - The HeanCMS theme engine, ported from keiyoushi's lib-multisrc/heancms.
//
// HeanCMS sites are a JSON API on an `api.` host plus a Next.js front. `HeanCmsEngine` holds the whole
// theme; a site is a source that owns a `HeanCmsConfig` and forwards to it. Stored urls are Mihon's:
// entries "/<subdirectory>/<slug>#<seriesId>", chapters "/<subdirectory>/<seriesSlug>/<chapterSlug>#<id>".
// Login and paid chapters (a bearer token) are not supported; paid chapters are hidden.

import Foundation
import SwiftSoup

struct HeanCmsConfig: Sendable {
    let sourceKey: String
    let baseURL: String
    var apiURL: String
    var coverPath = ""
    var cdnURL: String
    var mangaSubDirectory = "series"
    var latestSortBy = "desc"
    /// Details look up the series' listing badge, which marks doujinshi and manga.
    var fetchBadge = false

    init(sourceKey: String, baseURL: String, fetchBadge: Bool = false) {
        self.sourceKey = sourceKey
        self.baseURL = baseURL
        self.apiURL = baseURL.replacingOccurrences(of: "://", with: "://api.")
        self.cdnURL = self.apiURL
        self.fetchBadge = fetchBadge
    }
}

struct HeanCmsEngine: Sendable {

    let config: HeanCmsConfig
    private let site: SiteClient
    private let api: SiteClient

    private static let acceptJSON = "application/json, text/plain, */*"
    private static let acceptImage = "image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8"
    private static let chaptersPerPage = 1000

    init(_ config: HeanCmsConfig) {
        self.config = config
        site = SiteClient(sourceKey: config.sourceKey, baseURL: config.baseURL, headers: ["Referer": config.baseURL + "/"])
        api = SiteClient(sourceKey: config.sourceKey, baseURL: config.apiURL, headers: ["Referer": config.baseURL + "/"])
    }

    // MARK: Filters

    private static let statuses = [
        FilterOption(id: "All", name: "All"),
        FilterOption(id: "Ongoing", name: "Ongoing"),
        FilterOption(id: "Hiatus", name: "On hiatus"),
        FilterOption(id: "Dropped", name: "Dropped"),
        FilterOption(id: "Completed", name: "Completed"),
    ]

    private static let sorts = [
        FilterOption(id: "title", name: "Title"),
        FilterOption(id: "total_views", name: "Views"),
        FilterOption(id: "latest", name: "Latest"),
        FilterOption(id: "created_at", name: "Created at"),
    ]

    func filters() async throws -> [SourceFilter] {
        var result: [SourceFilter] = [
            .select(id: "status", name: "Status", options: Self.statuses, defaultOption: "All"),
            .sort(id: "sort", name: "Sort By", options: Self.sorts, defaultIndex: 1, defaultAscending: false),
        ]
        // Genres come from the site; a failed fetch leaves the other two filters usable.
        if let tags = try? await api.json([Tag].self, "/tags"), !tags.isEmpty {
            result.append(.multiSelect(
                id: "genres", name: "Genres",
                options: tags.map { FilterOption(id: String($0.id), name: $0.name) }, defaultSelection: []
            ))
        }
        return result
    }

    // MARK: Browsing

    func popular(page: Int) async throws -> EntriesPage {
        try await query(page: page, query: "", status: "All", order: "desc", orderBy: "total_views", tagIDs: "[]")
    }

    func latest(page: Int) async throws -> EntriesPage {
        try await query(page: page, query: "", status: "All", order: config.latestSortBy, orderBy: "latest", tagIDs: "[]")
    }

    func search(query text: String, page: Int, filters: FilterState) async throws -> EntriesPage {
        var status = "All"
        if case .option(let value)? = filters["status"] { status = value }
        var order = "desc"
        var orderBy = "total_views"
        if case .sort(let index, let ascending)? = filters["sort"], Self.sorts.indices.contains(index) {
            order = ascending ? "asc" : "desc"
            orderBy = Self.sorts[index].id
        }
        var tags = "[]"
        if case .options(let ids)? = filters["genres"], !ids.isEmpty {
            // Upstream lists them in the filter's order, which is the API's tag order (ascending id).
            let sorted = ids.sorted { (Int($0) ?? 0, $0) < (Int($1) ?? 0, $1) }
            tags = "[" + sorted.joined(separator: ",") + "]"
        }
        return try await query(page: page, query: text, status: status, order: order, orderBy: orderBy, tagIDs: tags)
    }

    private func query(
        page: Int, query text: String, status: String, order: String, orderBy: String, tagIDs: String
    ) async throws -> EntriesPage {
        let path = "/query?query_string=\(text.queryEscaped)&status=\(status.queryEscaped)&order=\(order)"
            + "&orderBy=\(orderBy)&series_type=Comic&page=\(page)&perPage=12"
            + "&tags_ids=\(tagIDs.queryEscaped)&adult=true"
        let result = try await api.json(QueryResult.self, path)
        let entries = result.data.map { entry(from: $0, format: $0.format) }
        return EntriesPage(entries: entries, hasNextPage: result.meta?.hasNextPage ?? false)
    }

    // MARK: Details

    func details(_ entry: SourceEntry) async throws -> SourceEntry {
        let slug = Self.slug(of: entry.url)
        let series = try await api.json(Series.self, "/series/\(slug)", headers: ["Accept": Self.acceptJSON])

        // The series endpoint has no badge; look it up in the listing once per entry.
        var format: String?
        if config.fetchBadge {
            let path = "/query?query_string=\(series.title.queryEscaped)&status=All&order=desc&orderBy=total_views"
                + "&series_type=Comic&page=1&perPage=12&tags_ids=%5B%5D&adult=true"
            let found = try await api.json(QueryResult.self, path)
            format = found.data.first { $0.id == series.id }?.format
        }
        return self.entry(from: series, format: format ?? series.format)
    }

    func chapters(_ entry: SourceEntry) async throws -> [SourceChapter] {
        guard let hash = entry.url.lastIndex(of: "#") else {
            throw SourceError.parseFailed("entry url has no series id: \(entry.url)")
        }
        let seriesID = String(entry.url[entry.url.index(after: hash)...])
        let seriesSlug = Self.slug(of: entry.url)

        var all: [Chapter] = []
        var page = 1
        while true {
            let path = "/chapter/query?page=\(page)&perPage=\(Self.chaptersPerPage)&series_id=\(seriesID)"
            let result = try await api.json(ChapterPayload.self, path, headers: ["Accept": Self.acceptJSON])
            all += result.data
            if !result.meta.hasNextPage { break }
            page += 1
        }

        let now = Date()
        return all.compactMap { chapter in
            // Paid chapters need a login; they are hidden rather than listed as unreadable.
            guard (chapter.price ?? 0) == 0 else { return nil }
            let date = chapter.createdAt.flatMap(Self.parseDate)
            if let date, date > now { return nil }
            var name = chapter.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if let title = chapter.title { name += " - " + title.trimmingCharacters(in: .whitespacesAndNewlines) }
            return SourceChapter(
                url: "/\(config.mangaSubDirectory)/\(seriesSlug)/\(chapter.slug)#\(chapter.id)",
                name: name, dateUpload: date
            )
        }
    }

    // MARK: Pages

    func pages(_ chapter: SourceChapter) async throws -> [SourcePage] {
        let path = chapter.url.replacingOccurrences(of: "/\(config.mangaSubDirectory)/", with: "/chapter/")
        // Upstream hands the url (fragment included) to OkHttp, which drops it.
        let clean = path.components(separatedBy: "#").first ?? path
        let result = try await api.json(PagePayload.self, clean)
        if result.paywall == true, result.chapter.chapterData == nil {
            throw SourceError.parseFailed("Paid chapter unavailable.")
        }
        let images = result.chapter.chapterData?.images ?? []
        return images.enumerated().map { index, image in
            SourcePage(index: index, url: absolute(image), headers: [
                "Referer": config.baseURL + "/", "Accept": Self.acceptImage,
            ])
        }
    }

    // MARK: Mapping

    private func entry(from series: Series, format: String) -> SourceEntry {
        SourceEntry(
            sourceKey: config.sourceKey, kind: .manga,
            url: "/\(config.mangaSubDirectory)/\(series.slug)#\(series.id)",
            title: series.title,
            thumbnailURL: series.thumbnail.isEmpty ? nil : absolute(series.thumbnail),
            author: series.author.flatMap(Self.credit), artist: series.studio.flatMap(Self.credit),
            description: series.buildDescription(),
            genres: series.tags.map(\.name).sorted() + [format],
            status: Self.status(series.status)
        )
    }

    private func absolute(_ path: String) -> String {
        if path.hasPrefix("https://") || path.hasPrefix("http://") { return path }
        return "\(config.cdnURL)/\(config.coverPath)\(path)"
    }

    private static func slug(of url: String) -> String {
        let last = url.components(separatedBy: "/").last ?? url
        return last.components(separatedBy: "#").first ?? last
    }

    private static func credit(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == "-" ? nil : trimmed
    }

    private static func status(_ raw: String?) -> EntryStatus {
        switch raw {
        case "Ongoing": .ongoing
        case "Hiatus": .onHiatus
        case "Dropped": .cancelled
        case "Completed", "Finished": .completed
        default: .unknown
        }
    }

    private static func parseDate(_ raw: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }

    // MARK: DTOs

    private struct Tag: Decodable { let id: Int; let name: String }

    private struct Meta: Decodable {
        let currentPage: Int
        let lastPage: Int
        var hasNextPage: Bool { currentPage < lastPage }
        enum CodingKeys: String, CodingKey { case currentPage = "current_page", lastPage = "last_page" }
    }

    private struct QueryResult: Decodable {
        let data: [Series]
        let meta: Meta?
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            data = try c.decodeIfPresent([Series].self, forKey: .data) ?? []
            meta = try c.decodeIfPresent(Meta.self, forKey: .meta)
        }
        enum CodingKeys: String, CodingKey { case data, meta }
    }

    private struct Series: Decodable {
        let id: Int
        let slug: String
        let author: String?
        let description: String?
        let studio: String?
        let status: String?
        let thumbnail: String
        let title: String
        let tags: [Tag]
        let alternativeNames: String?
        let rating: Double?
        let ratingsCount: Int?
        let releaseSchedule: [String: Bool]?
        let releaseYear: String?
        let badge: String?

        enum CodingKeys: String, CodingKey {
            case id, author, description, studio, status, thumbnail, title, tags, rating, badge
            case slug = "series_slug", alternativeNames = "alternative_names", ratingsCount = "ratings_count"
            case releaseSchedule = "release_schedule", releaseYear = "release_year"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(Int.self, forKey: .id)
            slug = try c.decode(String.self, forKey: .slug)
            author = try? c.decodeIfPresent(String.self, forKey: .author)
            description = try? c.decodeIfPresent(String.self, forKey: .description)
            studio = try? c.decodeIfPresent(String.self, forKey: .studio)
            status = try? c.decodeIfPresent(String.self, forKey: .status)
            thumbnail = try c.decodeIfPresent(String.self, forKey: .thumbnail) ?? ""
            title = try c.decode(String.self, forKey: .title)
            tags = (try? c.decodeIfPresent([Tag].self, forKey: .tags)) ?? []
            alternativeNames = try? c.decodeIfPresent(String.self, forKey: .alternativeNames)
            rating = Self.number(c, .rating)
            ratingsCount = try? c.decodeIfPresent(Int.self, forKey: .ratingsCount)
            releaseSchedule = try? c.decodeIfPresent([String: Bool].self, forKey: .releaseSchedule)
            releaseYear = Self.string(c, .releaseYear)
            badge = try? c.decodeIfPresent(String.self, forKey: .badge)
        }

        private static func number(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Double? {
            if let value = try? c.decodeIfPresent(Double.self, forKey: key) { return value }
            return (try? c.decodeIfPresent(String.self, forKey: key)).flatMap(Double.init)
        }

        private static func string(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> String? {
            if let value = try? c.decodeIfPresent(String.self, forKey: key) { return value }
            return (try? c.decodeIfPresent(Int.self, forKey: key)).map(String.init)
        }

        /// Badge text is free-form ("DOUJINSHI", "Doujinhsi", "DOUJIN").
        var format: String {
            let text = badge?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            if text.hasPrefix("douj") { return "Doujinshi" }
            if text == "manga" { return "Manga" }
            return "Manhwa"
        }

        func buildDescription() -> String {
            var out = ""
            if let description, let body = try? SwiftSoup.parseBodyFragment(description) {
                let paragraphs = ((try? body.select("p").array().map { try $0.text() }) ?? []).joined(separator: "\n\n")
                let text = paragraphs.isEmpty
                    ? ((try? body.text()) ?? "").replacingOccurrences(of: "\n", with: "\n\n") : paragraphs
                if text != "-" { out = text }
            }

            var info: [String] = []
            if let rating {
                var line = "Rating: " + String(format: "%.2f", rating)
                if let ratingsCount { line += " (\(ratingsCount) ratings)" }
                info.append(line)
            }
            if status == "Ongoing", let schedule = releaseSchedule {
                let days = ["mon": "Monday", "tue": "Tuesday", "wed": "Wednesday", "thu": "Thursday",
                            "fri": "Friday", "sat": "Saturday", "sun": "Sunday"]
                let order = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
                let names = order.filter { schedule[$0] == true }.compactMap { days[$0] }
                if !names.isEmpty { info.append("Updates: " + names.joined(separator: ", ")) }
            }
            if let year = releaseYear, !year.trimmingCharacters(in: .whitespaces).isEmpty {
                info.append("Released: \(year)")
            }
            if !info.isEmpty {
                if !out.isEmpty { out += "\n\n" }
                out += info.joined(separator: "\n")
            }

            let alts = (alternativeNames ?? "").components(separatedBy: "|")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0 != title }
            if !alts.isEmpty {
                if !out.isEmpty { out += "\n\n" }
                out += "Alternative names:\n" + alts.map { "- \($0)" }.joined(separator: "\n")
            }
            return out
        }
    }

    private struct ChapterPayload: Decodable {
        let data: [Chapter]
        let meta: Meta
    }

    private struct Chapter: Decodable {
        let id: Int
        let name: String
        let title: String?
        let slug: String
        let createdAt: String?
        let price: Int?
        enum CodingKeys: String, CodingKey {
            case id, price, title
            case name = "chapter_name", slug = "chapter_slug", createdAt = "created_at"
        }
    }

    private struct PagePayload: Decodable {
        struct Inner: Decodable {
            struct DataBlock: Decodable { let images: [String]? }
            let chapterData: DataBlock?
            enum CodingKeys: String, CodingKey { case chapterData = "chapter_data" }
        }
        let chapter: Inner
        let paywall: Bool?
    }
}
