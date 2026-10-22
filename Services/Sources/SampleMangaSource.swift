// SampleMangaSource.swift - A built-in source that serves generated pages.
//
// Purpose: exercise the whole manga path — browse, detail, reader, cache,
// progress — before the Kotlin/JS extensions exist. It never touches the
// network: pages are drawn locally on first use and served as `file://` URLs.
//
// Debug builds only. It is a development aid, not a product feature.

#if DEBUG
import Foundation
import UIKit

final class SampleMangaSource: MangaSource {

    static let identifier = "sample-manga"

    // MARK: Identity

    var key: String { SourceKey.makeBuiltin(id: Self.identifier) }
    var kind: ContentKind { .manga }
    var name: String { "Sample Manga (offline)" }
    var lang: String { "English" }
    var supportsLatest: Bool { true }

    // MARK: Catalogue

    private let entryURL = "/sample-manga/aurora"
    private static let chapterCount = 3
    private static let pagesPerChapter = 8

    private var sampleEntry: SourceEntry {
        SourceEntry(
            sourceKey: key,
            kind: .manga,
            url: entryURL,
            title: "Aurora Drift",
            author: "LNReader",
            description: "Generated pages used to test the manga reader, the image "
                + "cache and progress tracking without any network access.",
            genres: ["Test"],
            status: .ongoing
        )
    }

    func popular(page: Int, filters: FilterState) async throws -> EntriesPage {
        EntriesPage(entries: page == 1 ? [sampleEntry] : [], hasNextPage: false)
    }

    func latest(page: Int, filters: FilterState) async throws -> EntriesPage {
        try await popular(page: page, filters: filters)
    }

    func search(query: String, page: Int, filters: FilterState) async throws -> EntriesPage {
        guard page == 1 else { return EntriesPage(entries: []) }
        let matches = query.isEmpty
            || sampleEntry.title.localizedCaseInsensitiveContains(query)
        return EntriesPage(entries: matches ? [sampleEntry] : [], hasNextPage: false)
    }

    func details(_ entry: SourceEntry) async throws -> SourceEntry {
        guard entry.url == entryURL else { throw SourceError.entryNotFound(entry.url) }
        return sampleEntry
    }

    func chapters(_ entry: SourceEntry) async throws -> [SourceChapter] {
        guard entry.url == entryURL else { throw SourceError.entryNotFound(entry.url) }
        return (1...Self.chapterCount).map { number in
            SourceChapter(
                url: "\(entryURL)/chapter-\(number)",
                name: "Chapter \(number)",
                chapterNumber: Double(number),
                dateUpload: Date.now.addingTimeInterval(Double(number - Self.chapterCount) * 86_400)
            )
        }
    }

    // MARK: Pages

    func pages(_ chapter: SourceChapter) async throws -> [SourcePage] {
        let directory = try Self.pageDirectory()
        let slug = chapter.url.split(separator: "/").last.map(String.init) ?? "chapter"
        let title = chapter.name

        // Drawing is CPU work; keep it off the main actor so opening a chapter
        // does not hitch the UI.
        try await Task.detached(priority: .userInitiated) {
            for index in 0..<Self.pagesPerChapter {
                let file = directory.appending(path: "\(slug)-\(index).png")
                if !FileManager.default.fileExists(atPath: file.path) {
                    let data = try Self.drawPage(
                        number: index + 1,
                        of: Self.pagesPerChapter,
                        chapter: title
                    )
                    try data.write(to: file, options: .atomic)
                }
            }
        }.value

        return (0..<Self.pagesPerChapter).map { index in
            let file = directory.appending(path: "\(slug)-\(index).png")
            return SourcePage(index: index, url: file.absoluteString)
        }
    }

    // MARK: Page rendering

    private static func pageDirectory() throws -> URL {
        let directory = URL.applicationSupportDirectory
            .appending(path: "SampleManga", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Draws a numbered page so the reader shows something identifiable and the
    /// cache has real image bytes to store.
    private static func drawPage(number: Int, of total: Int, chapter: String) throws -> Data {
        let size = CGSize(width: 1000, height: 1500)
        let renderer = UIGraphicsImageRenderer(size: size)

        let image = renderer.image { context in
            let cg = context.cgContext
            let colours = [
                UIColor.systemIndigo.cgColor,
                UIColor.systemPurple.cgColor,
                UIColor.systemTeal.cgColor,
            ]
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colours as CFArray,
                locations: [0, 0.55, 1]
            )
            if let gradient {
                cg.drawLinearGradient(
                    gradient,
                    start: .zero,
                    end: CGPoint(x: size.width, y: size.height),
                    options: []
                )
            }

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center

            let numberAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 220, weight: .bold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraph,
            ]
            let label = "\(number)" as NSString
            let labelSize = label.size(withAttributes: numberAttributes)
            label.draw(
                in: CGRect(
                    x: 0,
                    y: (size.height - labelSize.height) / 2 - 60,
                    width: size.width,
                    height: labelSize.height
                ),
                withAttributes: numberAttributes
            )

            let captionAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 44, weight: .semibold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.9),
                .paragraphStyle: paragraph,
            ]
            ("\(chapter) · \(number) / \(total)" as NSString).draw(
                in: CGRect(x: 0, y: size.height / 2 + 120, width: size.width, height: 60),
                withAttributes: captionAttributes
            )
        }

        guard let data = image.pngData() else {
            throw SourceError.parseFailed("Could not encode sample page \(number)")
        }
        return data
    }
}
#endif
