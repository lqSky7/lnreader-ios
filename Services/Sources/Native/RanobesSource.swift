// RanobesSource.swift - Native port of the LNReader `ranobes` plugin (https://ranobes.top).
//
// Paths match what the JS plugin stored, so library entries saved under `ln:ranobes` keep resolving:
// a novel is `/novels/<id>-<slug>.html`, a chapter is the link on the site minus the origin.

import Foundation
import SwiftSoup

final class RanobesSource: NovelSource {
    let key = SourceKey.makeBuiltin(id: "ranobes")
    let kind = ContentKind.novel
    let name = "Ranobes"
    let lang = "English"

    private let site = SiteClient(sourceKey: SourceKey.makeBuiltin(id: "ranobes"), baseURL: "https://ranobes.top")
    private static let chaptersPerPage = 25

    // MARK: Browsing

    func popular(page: Int, filters: FilterState) async throws -> EntriesPage {
        try await list("/novels/page/\(page)/")
    }

    func search(query: String, page: Int, filters: FilterState) async throws -> EntriesPage {
        try await list("/search/\(query.queryEscaped)/page/\(page)")
    }

    private func list(_ path: String) async throws -> EntriesPage {
        let doc = try await page(path)
        let entries = try Self.parseNovels(doc, site: site, sourceKey: key)
        return EntriesPage(entries: entries, hasNextPage: !entries.isEmpty)
    }

    // MARK: Details

    func details(_ entry: SourceEntry) async throws -> SourceEntry {
        let doc = try await page(entry.url)
        return Self.parseDetails(doc, entry: entry, site: site)
    }

    func chapters(_ entry: SourceEntry) async throws -> [SourceChapter] {
        let doc = try await page(entry.url)
        let total = Self.totalChapterPages(doc)
        let listBase = Self.chapterListBase(for: entry.url)

        // Page 1 of the site's list is the newest chapters, so pages are fetched in order and
        // stitched oldest first. The JSON bundle is newest first inside a page too.
        var pages: [Int: [SourceChapter]] = [:]
        try await withThrowingTaskGroup(of: (Int, [SourceChapter]).self) { group in
            var next = 1
            func spawn() {
                guard next <= total else { return }
                let number = next
                next += 1
                group.addTask { (number, try await self.chapterPage(listBase, number)) }
            }
            for _ in 0..<min(4, total) { spawn() }
            while let (number, list) = try await group.next() {
                pages[number] = list
                spawn()
            }
        }
        var all: [SourceChapter] = []
        for number in stride(from: total, through: 1, by: -1) { all += pages[number] ?? [] }

        if all.isEmpty { all = Self.chapterLinks(on: doc, site: site).reversed() }
        return all
    }

    // MARK: Chapter text

    func chapterHTML(_ chapter: SourceChapter) async throws -> String {
        let html = try await pageText(chapter.url)
        // Same cut the plugin makes: from the text container to the footer that follows it.
        if let start = html.range(of: "<div class=\"text\" id=\"arrticle\">"),
           let end = html.range(of: "<div class=\"category grey ellipses\">", range: start.lowerBound..<html.endIndex) {
            return String(html[start.lowerBound..<end.lowerBound])
        }
        let doc = try SwiftSoup.parse(html)
        if let body = try doc.select("#arrticle").first() { return try body.outerHtml() }
        throw SourceError.parseFailed("chapter text container not found")
    }

    // MARK: Fetching

    /// A page as text. The site answers a challenge with a 200 and a "Just a moment" title.
    private func pageText(_ path: String) async throws -> String {
        let text = try await site.text(path)
        if let title = Self.title(of: text), Self.challengeTitles.contains(title) {
            throw HTTPError.cloudflareChallenge(url: site.absolute(path))
        }
        return text
    }

    private func page(_ path: String) async throws -> Document {
        try SwiftSoup.parse(try await pageText(path), site.baseURL)
    }

    private static let challengeTitles: Set<String> = [
        "Bot Verification", "You are being redirected...", "Un instant...", "Just a moment...", "Redirecting...",
    ]

    private static func title(of html: String) -> String? {
        guard let open = html.range(of: "<title>"),
              let close = html.range(of: "</title>", range: open.upperBound..<html.endIndex) else { return nil }
        return html[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Chapter list

    /// `/novels/123-slug.html` -> `/chapters/123`, as the plugin builds it.
    private static func chapterListBase(for novelPath: String) -> String {
        let id = novelPath.split(separator: "-").first.map(String.init) ?? novelPath
        return "/chapters" + id.replacingOccurrences(of: "novels/", with: "")
    }

    private func chapterPage(_ base: String, _ number: Int) async throws -> [SourceChapter] {
        let text = try await pageText("\(base)/page/\(number)")
        if let fromJSON = Self.chaptersFromBundle(text, site: site), !fromJSON.isEmpty {
            return fromJSON.reversed()
        }
        let doc = try SwiftSoup.parse(text, site.baseURL)
        var list: [SourceChapter] = []
        for row in try doc.select("div.cat_block.cat_line") {
            guard let link = try row.select("a[title][href]").first() else { continue }
            let date = try row.select("small").first()?.text()
            list.append(SourceChapter(
                url: Self.relative(try link.attr("href"), site: site),
                name: try link.attr("title"),
                dateUpload: DateParsing.parse(date)
            ))
        }
        return list
    }

    private struct ChapterBundle: Decodable {
        struct Item: Decodable {
            let title: String
            let date: String?
            let link: String
        }
        let chapters: [Item]?
    }

    /// The `window.__DATA__ = {...}` script the chapter list pages embed, newest chapter first.
    private static func chaptersFromBundle(_ html: String, site: SiteClient) -> [SourceChapter]? {
        guard let marker = html.range(of: "window.__DATA__ ="),
              let open = html.range(of: "{", range: marker.upperBound..<html.endIndex),
              let close = html.range(of: "</script>", range: open.lowerBound..<html.endIndex),
              let end = html.range(of: "}", options: .backwards, range: open.lowerBound..<close.lowerBound),
              let data = String(html[open.lowerBound..<end.upperBound]).data(using: .utf8),
              let bundle = try? JSONDecoder().decode(ChapterBundle.self, from: data),
              let items = bundle.chapters else { return nil }
        return items.map {
            SourceChapter(
                url: relative($0.link, site: site), name: $0.title, dateUpload: DateParsing.parse($0.date)
            )
        }
    }

    /// Chapters listed on the novel page itself (newest first), the fallback when the list pages fail.
    private static func chapterLinks(on doc: Document, site: SiteClient) -> [SourceChapter] {
        var list: [SourceChapter] = []
        for link in (try? doc.select("a[rel=chapter]")) ?? Elements() {
            let name = link.firstText("span.title.ellipses") ?? link.firstText("span.title") ?? ""
            guard !name.isEmpty, let href = try? link.attr("href") else { continue }
            list.append(SourceChapter(
                url: relative(href, site: site), name: name,
                dateUpload: DateParsing.parse(link.firstText("span.grey"))
            ))
        }
        return list
    }

    /// 25 chapters a page; the count sits in the "Glossary + illustrations ..." row of the novel page.
    private static func totalChapterPages(_ doc: Document) -> Int {
        for item in (try? doc.select("li[title]")) ?? Elements() {
            let title = (try? item.attr("title")) ?? ""
            guard title == "Glossary + illustrations + division of chapters, etc."
                    || title == "Глоссарий + иллюстраций + разделение глав и т.д." else { continue }
            let digits = ((try? item.text()) ?? "").filter(\.isNumber)
            if let count = Int(digits), count > 0 { return (count + chaptersPerPage - 1) / chaptersPerPage }
        }
        return 1
    }

    // MARK: Parsing

    private static func relative(_ href: String, site: SiteClient) -> String {
        href.hasPrefix(site.baseURL) ? String(href.dropFirst(site.baseURL.count)) : href
    }

    static func parseNovels(_ doc: Document, site: SiteClient, sourceKey: String) throws -> [SourceEntry] {
        var entries: [SourceEntry] = []
        var seen = Set<String>()
        for card in try doc.select(".short-cont") {
            guard let link = try card.select("h2.title a[href]").first() else { continue }
            let path = relative(try link.attr("href"), site: site)
            guard !path.isEmpty, seen.insert(path).inserted else { continue }

            // The cover is a CSS background on a <figure> next to the title.
            var cover: String?
            var scope: Element? = card
            for _ in 0..<3 where cover == nil {
                if let style = try scope?.select("figure[style]").first()?.attr("style") {
                    cover = backgroundURL(in: style, site: site)
                }
                scope = scope?.parent()
            }
            entries.append(SourceEntry(
                sourceKey: sourceKey, kind: .novel, url: path,
                title: try link.text().trimmingCharacters(in: .whitespacesAndNewlines), thumbnailURL: cover
            ))
        }
        return entries
    }

    private static func backgroundURL(in style: String, site: SiteClient) -> String? {
        guard let open = style.range(of: "url("),
              let close = style.range(of: ")", range: open.upperBound..<style.endIndex) else { return nil }
        let raw = style[open.upperBound..<close.lowerBound].trimmingCharacters(in: CharacterSet(charactersIn: "'\" "))
        return raw.isEmpty ? nil : site.absolute(raw)
    }

    private static func parseDetails(_ doc: Document, entry: SourceEntry, site: SiteClient) -> SourceEntry {
        let poster = try? doc.select(".poster img").first()
        let title = (try? poster?.attr("alt")).flatMap { $0.isEmpty ? nil : $0 } ?? entry.title
        let cover = (try? poster?.attr("src")).flatMap { $0.isEmpty ? nil : site.absolute($0) } ?? entry.thumbnailURL

        var summary: String?
        if let node = try? doc.select("div.moreless.cont-text.showcont-h, [itemprop=description].cont-text.showcont-h").first() {
            _ = try? node.select("br").after("\u{1}")
            summary = ((try? node.text()) ?? "")
                .replacingOccurrences(of: "\u{1}", with: "\n")
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var status: String?
        for item in (try? doc.select("li[title]")) ?? Elements() {
            let label = (try? item.attr("title")) ?? ""
            guard label.contains("Original status") || label.contains("Статус оригинала") else { continue }
            let value = item.firstText("a") ?? ""
            status = (value == "Ongoing" || value == "В процессе") ? "Ongoing" : "Completed"
            break
        }

        let genres = ((try? doc.select("#mc-fs-genre a")) ?? Elements()).compactMap { try? $0.text() }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }

        return SourceEntry(
            sourceKey: entry.sourceKey, kind: .novel, url: entry.url, title: title, thumbnailURL: cover,
            author: doc.firstText("[itemprop=creator]"), description: summary,
            genres: genres, status: EntryStatus.parse(status)
        )
    }
}
