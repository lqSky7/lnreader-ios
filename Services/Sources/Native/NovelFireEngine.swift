// NovelFireEngine.swift - The `[novelfire]` site template shared by Novel Fire and Novel Phoenix.
//
// Both sites run the same theme: `search-adv` for browsing, `search` for keywords, a DataTables
// style `ajax/listChapterDataAjax` for the chapter list and a `#content` block for chapter text.
// URLs are the site paths without the leading slash (`book/foo`, `book/foo/chapter-12`), the same
// shape the LNReader JS plugin stored.

import Foundation
import SwiftSoup

struct NovelFireEngine: Sendable {

    let sourceKey: String
    let client: SiteClient
    /// `sort` value used for Popular when the user has not picked one.
    let defaultSort: String

    init(sourceKey: String, baseURL: String, defaultSort: String) {
        self.sourceKey = sourceKey
        self.client = SiteClient(sourceKey: sourceKey, baseURL: baseURL)
        self.defaultSort = defaultSort
    }

    // MARK: Filters

    func filters() -> [SourceFilter] {
        func options(_ pairs: [(String, String)]) -> [FilterOption] {
            pairs.map { FilterOption(id: $0.1, name: $0.0) }
        }
        return [
            .multiSelect(id: "language", name: "Language", options: Self.languages, defaultSelection: []),
            .select(id: "genre_operator", name: "Genres (And/Or/Exclude)",
                    options: options([("AND", "and"), ("OR", "or"), ("EXCLUDE", "exclude")]), defaultOption: "and"),
            .multiSelect(id: "genres", name: "Genres", options: Self.genres, defaultSelection: []),
            .select(id: "chapters", name: "Chapters", options: options([
                ("All", "0"), ("<50", "1,49"), ("50-100", "50,100"), ("100-200", "100,200"),
                ("200-500", "200,500"), ("500-1000", "500,1000"), (">1000", "1001,1000000"),
            ]), defaultOption: "0"),
            .select(id: "rating_operator", name: "Rating (Min/Max)",
                    options: options([("min", "min"), ("max", "max")]), defaultOption: "min"),
            .select(id: "rating", name: "Rating", options: options([
                ("none", "0"), ("1", "1"), ("2", "2"), ("3", "3"), ("4", "4"), ("5", "5"),
            ]), defaultOption: "0"),
            .select(id: "status", name: "Translation Status",
                    options: options([("All", "-1"), ("Completed", "1"), ("Ongoing", "0")]), defaultOption: "-1"),
            .select(id: "sort", name: "Sort Results By", options: Self.sorts, defaultOption: defaultSort),
            .select(id: "tagcon", name: "Tags (And/Or)",
                    options: options([("AND", "and"), ("OR", "or")]), defaultOption: "and"),
            .text(id: "author", name: "Author", hint: nil, defaultValue: ""),
        ]
    }

    // MARK: Browsing

    func browse(page: Int, latest: Bool, filters: FilterState) async throws -> EntriesPage {
        func option(_ id: String, _ fallback: String) -> String {
            if case .option(let value)? = filters[id], !value.isEmpty { return value }
            return fallback
        }
        func options(_ id: String) -> [String] {
            if case .options(let set)? = filters[id] { return set.sorted { (Int($0) ?? 0) < (Int($1) ?? 0) } }
            return []
        }

        var query: [(String, String)] = []
        for value in options("language") { query.append(("country_id[]", value)) }
        query.append(("ctgcon", option("genre_operator", "and")))
        for value in options("genres") { query.append(("categories[]", value)) }
        query.append(("totalchapter", option("chapters", "0")))
        query.append(("ratcon", option("rating_operator", "min")))
        query.append(("rating", option("rating", "0")))
        query.append(("status", option("status", "-1")))
        query.append(("sort", latest ? "date" : option("sort", defaultSort)))
        query.append(("tagcon", option("tagcon", "and")))
        if case .text(let author)? = filters["author"], !author.isEmpty { query.append(("author", author)) }
        query.append(("page", String(page)))

        let document = try await document("search-adv?" + Self.queryString(query))
        return EntriesPage(entries: try novels(in: document, selector: ".novel-item"), hasNextPage: true)
            .trimmed()
    }

    func search(query: String, page: Int) async throws -> EntriesPage {
        let document = try await document(
            "search?" + Self.queryString([("keyword", query), ("page", String(page))])
        )
        return EntriesPage(entries: try novels(in: document, selector: ".novel-list.chapters .novel-item"), hasNextPage: true)
            .trimmed()
    }

    private func novels(in document: Document, selector: String) throws -> [SourceEntry] {
        var seen = Set<String>()
        var entries: [SourceEntry] = []
        for item in try document.select(selector).array() {
            let href = (try? item.select("> a").first()?.attr("href")).flatMap { $0.isEmpty ? nil : $0 }
                ?? (try? item.select("h4 a").first()?.attr("href")).flatMap { $0.isEmpty ? nil : $0 }
            guard let href, let path = path(of: href), seen.insert(path).inserted else { continue }
            let title = (try? item.select("a").first()?.attr("title")).flatMap { $0.isEmpty ? nil : $0 }
                ?? item.firstText("h4") ?? path
            let image = try item.select(".novel-cover > img").first()
            let cover = [try image?.attr("data-src"), try image?.attr("src")]
                .compactMap { $0 }.first { !$0.isEmpty }
            entries.append(SourceEntry(
                sourceKey: sourceKey, kind: .novel, url: path, title: title,
                thumbnailURL: cover.map(client.absolute)
            ))
        }
        return entries
    }

    // MARK: Details

    func details(_ entry: SourceEntry) async throws -> SourceEntry {
        let (entry, _) = try await detailsAndPostID(entry)
        return entry
    }

    private func detailsAndPostID(_ entry: SourceEntry) async throws -> (SourceEntry, String?) {
        let document = try await document(entry.url)
        let postID = try document.select("#novel-report").first()?.attr("report-post_id")

        let title = document.firstText(".novel-title") ?? entry.title
        let image = try document.select(".cover > img").first()
        let cover = [try image?.attr("data-src"), try image?.attr("src")]
            .compactMap { $0 }.first { !$0.isEmpty }
        let genres = try document.select(".categories .property-item").array()
            .compactMap { try? $0.text().trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let statusText = document.firstText(".header-stats .ongoing")
            ?? document.firstText(".header-stats .completed") ?? "Unknown"

        return (
            SourceEntry(
                sourceKey: sourceKey, kind: .novel, url: entry.url, title: title,
                thumbnailURL: cover.map(client.absolute) ?? entry.thumbnailURL,
                author: document.firstText(".author .property-item > span"),
                description: try summary(of: document),
                genres: genres,
                status: EntryStatus.parse(statusText)
            ),
            postID.flatMap { $0.isEmpty ? nil : $0 }
        )
    }

    private func summary(of document: Document) throws -> String? {
        guard let content = try document.select(".summary .content").first() else { return nil }
        try content.select(".expand").remove()
        try content.select("br").after("\n")
        try content.select("p").before("\n").after("\n\n")
        let lines = try content.text(trimAndNormaliseWhitespace: false)
            .components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let text = lines.joined(separator: "\n")
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    // MARK: Chapters

    func chapters(_ entry: SourceEntry) async throws -> [SourceChapter] {
        let (_, postID) = try await detailsAndPostID(entry)
        if let postID {
            do { return try await ajaxChapters(path: entry.url, postID: postID) } catch SourceError.entryNotFound {
                // Ajax interface missing: fall through to the paged HTML list.
            }
        }
        return try await pagedChapters(path: entry.url)
    }

    private struct ChapterRows: Decodable {
        struct Row: Decodable {
            let title: String?
            let slug: String?
            let nSort: Double?

            enum CodingKeys: String, CodingKey { case title, slug, nSort = "n_sort" }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                title = try? container.decode(String.self, forKey: .title)
                slug = try? container.decode(String.self, forKey: .slug)
                if let number = try? container.decode(Double.self, forKey: .nSort) {
                    nSort = number
                } else if let text = try? container.decode(String.self, forKey: .nSort) {
                    nSort = Double(text)
                } else {
                    nSort = nil
                }
            }
        }
        let data: [Row]?
    }

    private func ajaxChapters(path: String, postID: String) async throws -> [SourceChapter] {
        let query: [(String, String)] = [
            ("draw", "1"),
            ("columns[0][data]", "n_sort"), ("columns[0][name]", "cmm_posts_detail.n_sort"),
            ("columns[0][searchable]", "true"), ("columns[0][orderable]", "true"),
            ("columns[0][search][value]", ""), ("columns[0][search][regex]", "false"),
            ("columns[1][data]", "bookmark_created_at"), ("columns[1][name]", "bookmark_chapters.created_at"),
            ("columns[1][searchable]", "false"), ("columns[1][orderable]", "true"),
            ("columns[1][search][value]", ""), ("columns[1][search][regex]", "false"),
            ("order[0][column]", "0"), ("order[0][dir]", "asc"), ("order[0][name]", "cmm_posts_detail.n_sort"),
            ("start", "0"), ("length", "-1"),
            ("search[value]", ""), ("search[regex]", "false"),
            ("post_id", postID), ("only_bookmark", "false"),
            ("_", String(Int(Date().timeIntervalSince1970 * 1000))),
        ]
        let response = try await client.send("ajax/listChapterDataAjax?" + Self.queryString(query))
        let body = response.text
        if response.statusCode == 429 || body.contains("You are being rate limited") {
            throw SourceError.emptyResponse("chapters (rate limited, try again shortly)")
        }
        if body.contains("Page Not Found 404") { throw SourceError.entryNotFound(path) }

        let rows = try response.decoded(ChapterRows.self).data ?? []
        let chapters: [SourceChapter] = rows.compactMap { row in
            guard let number = row.nSort, let raw = row.title ?? row.slug else { return nil }
            let name = ((try? SwiftSoup.parseBodyFragment(raw).text()) ?? raw)
                .replacingOccurrences(of: "[\u{200B}-\u{200D}\u{FEFF}]", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            return SourceChapter(url: "\(path)/chapter-\(Self.numberString(number))", name: name, chapterNumber: number)
        }
        return chapters.sorted { $0.chapterNumber < $1.chapterNumber }
    }

    /// Fallback for books without a post id: the HTML list at `<book>/chapters?page=N`.
    private func pagedChapters(path: String) async throws -> [SourceChapter] {
        var result: [SourceChapter] = []
        var seen = Set<String>()
        for page in 1...200 {
            let document = try await document("\(path)/chapters?page=\(page)")
            var added = 0
            for link in try document.select(".chapter-list li a").array() {
                guard let href = try? link.attr("href"), let chapterPath = self.path(of: href),
                      seen.insert(chapterPath).inserted else { continue }
                let title = (try? link.attr("title")).flatMap { $0.isEmpty ? nil : $0 } ?? "No Title Found"
                result.append(SourceChapter(url: chapterPath, name: title))
                added += 1
            }
            if added == 0 { break }
        }
        return result
    }

    // MARK: Chapter text

    func chapterHTML(_ chapter: SourceChapter) async throws -> String {
        var document = try await self.document(chapter.url)
        if try document.select("#content").isEmpty(),
           let target = try redirectTarget(in: document) {
            document = try await self.document(target)
        }
        guard let content = try document.select("#content").first() else {
            throw SourceError.parseFailed("chapter content container (#content) not found for \(chapter.url)")
        }
        // The site seeds the text with `nf…` decoy elements; keep only ordinary prose tags.
        for element in try content.select(":not(p, h1, span, i, b, u, img, a, div, strong)").array() {
            let tag = element.tagName()
            if tag.count > 5, tag.hasPrefix("nf") { try element.remove() }
        }
        let html = try content.html().replacingOccurrences(of: "&nbsp;", with: " ")
        guard !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SourceError.emptyResponse("chapter text")
        }
        return html
    }

    private func redirectTarget(in document: Document) throws -> String? {
        let script = try document.select("script").array().map { $0.data() }.joined()
        guard let match = script.range(of: #"window\.location\.href\s*=\s*["']([^"']+)["']"#, options: .regularExpression),
              let quote = script[match].firstIndex(where: { $0 == "\"" || $0 == "'" }) else { return nil }
        let value = script[script.index(after: quote)..<script[match].index(before: match.upperBound)]
        return String(value).replacingOccurrences(of: "\\/", with: "/")
    }

    // MARK: Helpers

    private func document(_ pathOrURL: String) async throws -> Document {
        let response = try await client.send(pathOrURL)
        guard response.isSuccess else {
            throw SourceError.emptyResponse("page (HTTP \(response.statusCode))")
        }
        let document = try SwiftSoup.parse(response.text, response.url.absoluteString)
        if (try document.title()).contains("Cloudflare") {
            throw SourceError.emptyResponse("page (Cloudflare is blocking requests)")
        }
        return document
    }

    /// Path without the leading slash, from a relative or absolute link.
    private func path(of href: String) -> String? {
        guard let url = URL(string: client.absolute(href)) else { return nil }
        let path = String(url.path.drop(while: { $0 == "/" }))
        return path.isEmpty ? nil : path
    }

    private static func queryString(_ pairs: [(String, String)]) -> String {
        pairs.map { "\($0.0.queryEscaped)=\($0.1.queryEscaped)" }.joined(separator: "&")
    }

    private static func numberString(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }

    private static let languages = [
        FilterOption(id: "1", name: "Chinese Novel"), FilterOption(id: "3", name: "Japanese Novel"),
        FilterOption(id: "4", name: "English Novel"),
    ]

    private static let sorts: [FilterOption] = [
        ("Last Updated (Newest)", "date"), ("Rank (Top)", "rank-top"), ("Rating Score (Top)", "rating-score-top"),
        ("Review Count (Most)", "review"), ("Comment Count (Most)", "comment"),
        ("Bookmark Count (Most)", "bookmark"), ("Today Views (Most)", "today-view"),
        ("Monthly Views (Most)", "monthly-view"), ("Total Views (Most)", "total-view"),
        ("Chapter Count (Most)", "chapter-count-most"), ("Title (A>Z)", "abc"), ("Title (Z>A)", "cba"),
    ].map { FilterOption(id: $0.1, name: $0.0) }

    private static let genres: [FilterOption] = [
        ("Action", "3"), ("Adult", "28"), ("Adventure", "4"), ("Anime", "46"), ("Arts", "47"), ("Comedy", "5"),
        ("Drama", "24"), ("Eastern", "44"), ("Ecchi", "26"), ("Fan-fiction", "48"), ("Fantasy", "6"),
        ("Game", "19"), ("Gender Bender", "25"), ("Harem", "7"), ("Historical", "12"), ("Horror", "37"),
        ("Isekai", "49"), ("Josei", "2"), ("Lgbt+", "45"), ("Magic", "50"), ("Magical realism", "51"),
        ("Manhua", "52"), ("Martial Arts", "15"), ("Mature", "8"), ("Mecha", "34"), ("Military", "53"),
        ("Modern life", "54"), ("Movies", "55"), ("Mystery", "16"), ("Other", "64"), ("Psychological", "9"),
        ("Realistic fiction", "56"), ("Reincarnation", "43"), ("Romance", "1"), ("School Life", "21"),
        ("Sci-fi", "20"), ("Seinen", "10"), ("Shoujo", "38"), ("Shoujo ai", "57"), ("Shounen", "17"),
        ("Shounen Ai", "39"), ("Slice of Life", "13"), ("Smut", "29"), ("Sports", "42"),
        ("Supernatural", "18"), ("System", "58"), ("Tragedy", "32"), ("Urban", "63"), ("Urban life", "59"),
        ("Video games", "60"), ("War", "61"), ("Wuxia", "31"), ("Xianxia", "23"), ("Xuanhuan", "22"),
        ("Yaoi", "14"), ("Yuri", "62"),
    ].map { FilterOption(id: $0.1, name: $0.0) }
}

private extension EntriesPage {
    /// The site never says whether another page exists; an empty page means the end.
    func trimmed() -> EntriesPage { EntriesPage(entries: entries, hasNextPage: !entries.isEmpty) }
}
