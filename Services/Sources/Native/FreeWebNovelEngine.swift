// FreeWebNovelEngine.swift - The `[readnovelfull]` template of the LNReader plugins, ported to Swift.
//
// The JS plugin family shares one scraper configured per site; this keeps that split so another
// ReadNovelFull-style site is a new `Configuration`. Paths have no leading slash (`novel/some-title`),
// exactly what the plugin stored.

import Foundation
import SwiftSoup

struct FreeWebNovelEngine: Sendable {

    struct Configuration: Sendable {
        let sourceKey: String
        let baseURL: String
        let latestPage: String
        let searchPage: String
        let searchKey: String
        /// Listing pages that have no page 2 (the plugin's `noPages`).
        let singlePageListings: Set<String>
        let chapterListing: String
        let chapterParam: String
        let defaultType: String
        let types: [FilterOption]
        let genres: [FilterOption]
    }

    let config: Configuration
    let site: SiteClient
    private let state = ListingState()

    init(_ config: Configuration) {
        self.config = config
        self.site = SiteClient(sourceKey: config.sourceKey, baseURL: config.baseURL)
    }

    // MARK: Filters

    static let typeFilterID = "type"
    static let genreFilterID = "genres"

    func filters() -> [SourceFilter] {
        [
            .select(id: Self.typeFilterID, name: "Novel Type", options: config.types, defaultOption: config.defaultType),
            .select(id: Self.genreFilterID, name: "Genre", options: config.genres, defaultOption: nil),
        ]
    }

    private func option(_ id: String, in filters: FilterState, fallback: String) -> String {
        if case .option(let value)? = filters[id] { return value }
        return fallback
    }

    // MARK: Listings

    func popular(page: Int, filters: FilterState) async throws -> EntriesPage {
        let genre = option(Self.genreFilterID, in: filters, fallback: "")
        let type = option(Self.typeFilterID, in: filters, fallback: config.defaultType)
        if page != 1, genre.isEmpty, config.singlePageListings.contains(type) {
            return EntriesPage(entries: [])
        }
        return try await listing(genre.isEmpty ? type : genre, page: page)
    }

    func latest(page: Int) async throws -> EntriesPage {
        try await listing(config.latestPage, page: page)
    }

    private func listing(_ base: String, page: Int) async throws -> EntriesPage {
        let path = page > 1 ? "\(base)/\(page)" : base
        let doc = try await html(path)
        let entries = Self.parseNovels(doc, site: site, sourceKey: config.sourceKey)
        // Past the last page the site repeats the final one; an identical page means the end.
        let paths = entries.map(\.url)
        if await state.isRepeat(page: page, paths: paths) { return EntriesPage(entries: []) }
        return EntriesPage(entries: entries, hasNextPage: !entries.isEmpty)
    }

    func search(query: String, page: Int) async throws -> EntriesPage {
        await state.waitForSearchSlot()
        let path = "\(config.searchPage)?\(config.searchKey)=\(query.queryEscaped)&page=\(page)"
        let response: HTTPResponse
        do {
            response = try await site.send(path)
        } catch HTTPError.badStatus(let code, _) where code == 404 && page > 1 {
            return EntriesPage(entries: [])
        }
        let text = response.text
        if let alert = Self.alertMessage(in: text) { throw SourceError.parseFailed(alert) }
        let doc = try SwiftSoup.parse(text, response.url.absoluteString)
        let entries = Self.parseNovels(doc, site: site, sourceKey: config.sourceKey)
        return EntriesPage(entries: entries, hasNextPage: !entries.isEmpty)
    }

    private static func alertMessage(in html: String) -> String? {
        guard let open = html.range(of: "alert("),
              let close = html.range(of: ")", range: open.upperBound..<html.endIndex) else { return nil }
        let message = html[open.upperBound..<close.lowerBound].trimmingCharacters(in: CharacterSet(charactersIn: "'\" "))
        return message.isEmpty ? nil : message
    }

    private func html(_ path: String) async throws -> Document {
        try await site.html(path)
    }

    // MARK: Details and chapters

    func details(_ entry: SourceEntry) async throws -> SourceEntry {
        let doc = try await html(entry.url)
        return Self.parseDetails(doc, entry: entry, site: site)
    }

    func chapters(_ entry: SourceEntry) async throws -> [SourceChapter] {
        let doc = try await html(entry.url)

        let inline = Self.inlineChapters(doc)
        let totalChapters = Self.totalChapters(doc)
        if !inline.isEmpty, totalChapters == nil { return inline }

        guard let bookID = Self.bookID(doc, path: entry.url) else { return inline }
        let listing = config.chapterListing
        let body: String
        if let totalChapters {
            let acode = doc.firstAttr("span[class*=disqus]", "data-disqus-identifier")
                ?? entry.url.split(separator: "/").last.map(String.init) ?? ""
            let response = try await site.postForm(
                listing,
                [(config.chapterParam, bookID), ("acode", acode), ("cid", String(Int.random(in: 0..<max(totalChapters, 1))))],
                headers: ["X-Requested-With": "XMLHttpRequest"]
            )
            body = response.text
        } else {
            body = try await site.text("\(listing)?\(config.chapterParam)=\(bookID)")
        }
        return Self.parseChapterFragment(body, site: site)
    }

    func chapterHTML(_ chapter: SourceChapter) async throws -> String {
        let doc = try await html(chapter.url)
        guard let container = try doc.select(".txt, #chr-content, #chapter-content").first() else {
            throw SourceError.parseFailed("chapter text container not found")
        }
        for junk in try container.select("sub, iframe, div.ads, div[class*=ads], div[class*=unlock-buttons], script") {
            try junk.remove()
        }
        try Self.stripWatermarks(in: container)
        return try container.outerHtml()
    }

    // MARK: Parsing

    static func parseNovels(_ doc: Document, site: SiteClient, sourceKey: String) -> [SourceEntry] {
        let scope: Element = ((try? doc.select(".col-content, [class*=archive]").first()) ?? nil) ?? doc
        var entries: [SourceEntry] = []
        var seen = Set<String>()
        for link in (try? scope.select("h3 a[href]")) ?? Elements() {
            guard let href = try? link.attr("href"), let path = pathname(href, site: site),
                  seen.insert(path).inserted else { continue }
            var name = (try? link.attr("title")) ?? ""
            if name.isEmpty { name = (try? link.text()) ?? "" }
            name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }

            var cover: String?
            var ancestor: Element? = link.parent()
            for _ in 0..<4 where cover == nil {
                if let image = try? ancestor?.select("img").first() { cover = imageURL(image, site: site) }
                ancestor = ancestor?.parent()
            }
            entries.append(SourceEntry(sourceKey: sourceKey, kind: .novel, url: path, title: name, thumbnailURL: cover))
        }
        return entries
    }

    private static func imageURL(_ image: Element, site: SiteClient) -> String? {
        for name in ["data-src", "data-cfsrc", "data-original", "src"] {
            if let value = try? image.attr(name), !value.isEmpty, !value.hasPrefix("data:") {
                return site.absolute(value)
            }
        }
        return nil
    }

    /// The plugin's path: URL pathname without the leading slash.
    private static func pathname(_ href: String, site: SiteClient) -> String? {
        guard let url = URL(string: site.absolute(href)), !url.path.isEmpty else { return nil }
        let path = String(url.path.drop(while: { $0 == "/" }))
        return path.isEmpty ? nil : path
    }

    private static func parseDetails(_ doc: Document, entry: SourceEntry, site: SiteClient) -> SourceEntry {
        let image = try? doc.select(".books img, .m-imgtxt img").first()
        var title = ((try? image?.attr("title")) ?? "")
        if title.isEmpty { title = doc.firstText(".m-imgtxt h1.tit, h1.tit") ?? entry.title }
        let cover = image.flatMap { imageURL($0, site: site) } ?? entry.thumbnailURL

        var author: String?
        var genres: [String] = []
        var status: String?
        for item in (try? doc.select("ul.info-meta li, .info li")) ?? Elements() {
            let text = ((try? item.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard let colon = text.firstIndex(of: ":") else { continue }
            let label = text[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = text[text.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            let parts = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            switch label {
            case "author": author = parts.joined(separator: ", ")
            case "genre":
                let links = ((try? item.select("a")) ?? Elements()).compactMap { try? $0.text() }
                genres = links.isEmpty ? parts : links.map { $0.trimmingCharacters(in: .whitespaces) }
            case "status": status = value
            default: break
            }
        }

        var summary: String?
        if let node = try? doc.select(".m-desc .inner, .desc-text, div.inner").first() {
            _ = try? node.select("br").after("\u{1}")
            summary = ((try? node.text()) ?? "")
                .replacingOccurrences(of: "\u{1}", with: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return SourceEntry(
            sourceKey: entry.sourceKey, kind: .novel, url: entry.url, title: title, thumbnailURL: cover,
            author: author, description: summary, genres: genres, status: EntryStatus.parse(status)
        )
    }

    /// Chapters printed on the novel page, `ul#idData`. Numbered by position like the plugin does.
    private static func inlineChapters(_ doc: Document) -> [SourceChapter] {
        var list: [SourceChapter] = []
        for link in (try? doc.select("ul#idData a[href]")) ?? Elements() {
            let number = list.count + 1
            let href = (try? link.attr("href")) ?? ""
            let title = (try? link.attr("title")) ?? ""
            let path = href.hasPrefix("/") ? String(href.dropFirst()) : href
            guard !path.isEmpty else { continue }
            list.append(SourceChapter(
                url: path, name: title.isEmpty ? "Chapter \(number)" : title, chapterNumber: Double(number)
            ))
        }
        return list
    }

    /// Total from `#indexListPage[data-total-chapters]` or the `window.chapterPagination` script.
    private static func totalChapters(_ doc: Document) -> Int? {
        if let raw = doc.firstAttr("#indexListPage", "data-total-chapters"), let count = Int(raw) { return count }
        for script in (try? doc.select("script")) ?? Elements() {
            let code = script.data()
            guard code.contains("window.chapterPagination"), let range = code.range(of: "totalChapters:") else { continue }
            let digits = code[range.upperBound...].drop(while: { $0 == " " }).prefix(while: \.isNumber)
            if let count = Int(digits) { return count }
        }
        return nil
    }

    private static func bookID(_ doc: Document, path: String) -> String? {
        if let id = doc.firstAttr("a.set-case", "data-articleid") { return id }
        for script in (try? doc.select("script")) ?? Elements() {
            let code = script.data()
            guard let range = code.range(of: "sourceid=") else { continue }
            let digits = code[range.upperBound...].prefix(while: \.isNumber)
            if !digits.isEmpty { return String(digits) }
        }
        let digits = path.drop(while: { !$0.isNumber }).prefix(while: \.isNumber)
        return digits.isEmpty ? nil : String(digits)
    }

    /// The chapter archive answers with JSON `{"html": ...}` or bare markup of `<a>` / `<option>` rows.
    private static func parseChapterFragment(_ body: String, site: SiteClient) -> [SourceChapter] {
        var markup = body
        if let data = body.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let html = object["html"] as? String {
            markup = html
        }
        guard let fragment = try? SwiftSoup.parseBodyFragment(markup) else { return [] }
        var list: [SourceChapter] = []
        for row in (try? fragment.select("a[href], option[value]")) ?? Elements() {
            let isLink = row.tagName() == "a"
            guard let target = try? row.attr(isLink ? "href" : "value"), !target.isEmpty,
                  let path = pathname(target, site: site) else { continue }
            var name = isLink ? ((try? row.attr("title")) ?? "") : ""
            if name.isEmpty { name = ((try? row.text()) ?? "") }
            name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { list.append(SourceChapter(url: path, name: name)) }
        }
        return list
    }

    // MARK: Watermarks

    /// The site sprinkles "freewebnovel.com" through chapters in look-alike Unicode. The plugin matches
    /// each letter's variants with one enormous regex; folding a candidate token to plain letters first
    /// gets the same result with a readable rule.
    private static func stripWatermarks(in container: Element) throws {
        guard let token = try? NSRegularExpression(pattern: "[^\\s<>]{9,}") else { return }
        for node in container.textNodes() { try clean(node, with: token) }
        for child in try container.select("*") {
            for node in child.textNodes() { try clean(node, with: token) }
        }
    }

    private static func clean(_ node: TextNode, with token: NSRegularExpression) throws {
        let text = node.getWholeText()
        let source = text as NSString
        var result = text
        let matches = token.matches(in: text, range: NSRange(location: 0, length: source.length)).reversed()
        for match in matches {
            let word = source.substring(with: match.range)
            let folded = word.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
                .precomposedStringWithCompatibilityMapping.lowercased()
            if folded.contains("freewebnovel") {
                result = (result as NSString).replacingCharacters(in: match.range, with: "")
            }
        }
        if result != text { node.text(result) }
    }
}

// MARK: - Listing state

/// Per-source memory the plugin kept on the instance: the last listing page (to spot the repeated
/// final page) and the time of the last search (the site throttles searches).
private actor ListingState {
    private var last: (page: Int, paths: [String])?
    private var lastSearch: Date?
    private let searchInterval: TimeInterval = 3.4

    func isRepeat(page: Int, paths: [String]) -> Bool {
        defer { last = (page, paths) }
        guard let last, page > last.page, !paths.isEmpty else { return false }
        return last.paths == paths
    }

    func waitForSearchSlot() async {
        if let lastSearch {
            let wait = searchInterval - Date().timeIntervalSince(lastSearch)
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
        }
        lastSearch = Date()
    }
}
