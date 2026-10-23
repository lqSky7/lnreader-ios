// V2ExtensionChecks.swift - Runs a JS extension bundle through the real host.
//
// The fixture server is a plain directory of HTML served by `python3 -m
// http.server`; the bundle under test uses only the public contract
// (`http.get`, `dom.*`), so this exercises the same path a transpiled extension
// would take: bundle → JSC → HTTP bridge → SwiftSoup → SourceEntry/Chapter/Page.

import Foundation

@main
struct V2ExtensionChecks {

    static func main() async throws {
        guard let base = ProcessInfo.processInfo.environment["FIXTURE_BASE_URL"], !base.isEmpty else {
            fatalError("FIXTURE_BASE_URL is not set")
        }

        try await checkHappyPath(base: base)
        try await checkMissingMethod(base: base)
        try await checkScriptError(base: base)
        try checkMissingExtension()
        try await checkHttpError(base: base)

        print("PASS: extension host — popular/search/details/chapters/pages over the JS "
            + "bridge, plus missing method, script error, missing bundle and HTTP failure")
    }

    // MARK: - Bundle under test

    private static func bundle(base: String) -> String {
        """
        var BASE = "\(base)";

        function entriesFrom(html, page) {
          var doc = dom.parse(html);
          var cards = dom.select(doc, ".card");
          var entries = [];
          for (var i = 0; i < cards.length; i++) {
            var link = dom.select(cards[i], "a.title")[0];
            var image = dom.select(cards[i], "img")[0];
            entries.push({
              url: dom.attr(link, "href"),
              title: dom.text(link),
              thumbnailURL: dom.attr(image, "src")
            });
          }
          return { entries: entries, hasNextPage: page < 2 };
        }

        var extension = {
          id: "fixture",
          name: "Fixture Source",
          lang: "en",
          version: "1.0.0",
          baseUrl: BASE,
          supportsLatest: true,

          popular: function (page) {
            return entriesFrom(http.get(BASE + "/list.html").body, page);
          },
          latest: function (page) {
            return entriesFrom(http.get(BASE + "/list.html").body, page);
          },
          search: function (query, page) {
            var result = entriesFrom(http.get(BASE + "/list.html").body, page);
            result.entries = result.entries.filter(function (e) {
              return e.title.toLowerCase().indexOf(query.toLowerCase()) >= 0;
            });
            return result;
          },
          details: function (url) {
            var doc = dom.parse(http.get(BASE + "/detail.html").body);
            var genres = dom.select(doc, "a.genre");
            var list = [];
            for (var i = 0; i < genres.length; i++) { list.push(dom.text(genres[i])); }
            return {
              url: url,
              title: dom.text(dom.select(doc, "h1.title")[0]),
              thumbnailURL: dom.attr(dom.select(doc, "img.cover")[0], "src"),
              author: dom.text(dom.select(doc, ".author")[0]),
              description: dom.text(dom.select(doc, ".summary")[0]),
              genres: list,
              status: dom.text(dom.select(doc, ".status")[0])
            };
          },
          chapters: function (url) {
            var doc = dom.parse(http.get(BASE + "/chapters.html").body);
            var rows = dom.select(doc, "li.chapter");
            var out = [];
            for (var i = 0; i < rows.length; i++) {
              var link = dom.select(rows[i], "a")[0];
              out.push({
                url: dom.attr(link, "href"),
                name: dom.text(link),
                number: dom.attr(link, "data-num"),
                dateUpload: dom.text(dom.select(rows[i], "span.date")[0])
              });
            }
            return out;
          },
          pages: function (url) {
            var doc = dom.parse(http.get(BASE + "/pages.html").body);
            var images = dom.select(doc, "img.page");
            var out = [];
            for (var i = 0; i < images.length; i++) {
              out.push({ url: dom.attr(images[i], "data-src"), headers: { "Referer": BASE } });
            }
            return out;
          }
        };
        """
    }

    private static func source(base: String) throws -> JSBundleMangaSource {
        let manifest = ExtensionManifest(
            pkg: "fixture.source",
            name: "Fixture Source",
            lang: "en",
            versionId: 1,
            iconURL: nil,
            bundlePath: "fixture.js",
            kind: .manga
        )
        return try JSBundleMangaSource(manifest: manifest, bundle: bundle(base: base))
    }

    // MARK: - Cases

    private static func checkHappyPath(base: String) async throws {
        let source = try source(base: base)

        precondition(source.key == "mihon:fixture.source", "unexpected key \(source.key)")
        precondition(source.kind == .manga)
        precondition(source.name == "Fixture Source")
        precondition(source.supportsLatest)

        // popular
        let popular = try await source.popular(page: 1, filters: FilterState())
        precondition(popular.entries.count == 3, "expected 3 entries, got \(popular.entries.count)")
        precondition(popular.hasNextPage, "page 1 of a 2-page fixture has a next page")
        let alpha = try unwrap(popular.entries.first)
        precondition(alpha.title == "Alpha")
        precondition(alpha.url == "/manga/alpha")
        precondition(alpha.thumbnailURL == "https://cdn.example.com/alpha.jpg")
        precondition(alpha.id == "mihon:fixture.source::/manga/alpha")

        // search filters through the bundle
        let found = try await source.search(query: "bet", page: 1, filters: FilterState())
        precondition(found.entries.map(\.title) == ["Beta"], "search should keep only Beta")

        // latest
        let latest = try await source.latest(page: 2, filters: FilterState())
        precondition(!latest.hasNextPage, "page 2 is the last page")

        // details
        let details = try await source.details(alpha)
        precondition(details.title == "Alpha")
        precondition(details.author == "A. Writer")
        precondition(details.description == "A story about the first letter.")
        precondition(details.genres == ["Action", "Drama"], "genres were \(details.genres)")
        precondition(details.status == .ongoing, "status was \(details.status)")

        // chapters
        let chapters = try await source.chapters(alpha)
        precondition(chapters.count == 2)
        precondition(chapters[0].name == "Chapter 2")
        precondition(chapters[0].chapterNumber == 2, "number came back as \(chapters[0].chapterNumber)")
        precondition(chapters[0].url == "/read/alpha/2")
        precondition(chapters[1].chapterNumber == 1)
        // "2024-03-05" must survive as a date, not a string.
        let day = Calendar(identifier: .gregorian).component(.day, from: try unwrap(chapters[0].dateUpload))
        precondition(day == 5, "dateUpload parsed to day \(day)")

        // pages
        let pages = try await source.pages(try unwrap(chapters.first))
        precondition(pages.count == 3)
        precondition(pages[0].index == 0)
        precondition(pages[2].url == "https://cdn.example.com/alpha/3.jpg")
        precondition(pages[0].headers["Referer"] == base)
    }

    private static func checkMissingMethod(base: String) async throws {
        let manifest = ExtensionManifest(
            pkg: "fixture.partial", name: "Partial", lang: "en", versionId: 1,
            iconURL: nil, bundlePath: "partial.js", kind: .manga
        )
        let partial = try JSBundleMangaSource(
            manifest: manifest,
            bundle: "var extension = { popular: function (p) { return { entries: [] }; } };"
        )
        do {
            _ = try await partial.details(SourceEntry(sourceKey: partial.key, kind: .manga, url: "/x", title: "X"))
            preconditionFailure("a missing method must throw")
        } catch let error as JSExtensionHost.HostError {
            guard case .missingMethod("details") = error else {
                preconditionFailure("unexpected error \(error)")
            }
        }
    }

    private static func checkScriptError(base: String) async throws {
        let manifest = ExtensionManifest(
            pkg: "fixture.broken", name: "Broken", lang: "en", versionId: 1,
            iconURL: nil, bundlePath: "broken.js", kind: .manga
        )
        let broken = try JSBundleMangaSource(
            manifest: manifest,
            bundle: "var extension = { popular: function (p) { throw new Error('boom'); } };"
        )
        do {
            _ = try await broken.popular(page: 1, filters: FilterState())
            preconditionFailure("a throwing bundle must surface an error")
        } catch let error as JSExtensionHost.HostError {
            guard case .script = error else {
                preconditionFailure("unexpected error \(error)")
            }
        }
    }

    private static func checkMissingExtension() throws {
        do {
            _ = try JSExtensionHost(bundle: "var notAnExtension = {};", sourceKey: "test")
            preconditionFailure("a bundle without `extension` must be rejected")
        } catch let error as JSExtensionHost.HostError {
            guard case .missingExtension = error else {
                preconditionFailure("unexpected error \(error)")
            }
        }
    }

    private static func checkHttpError(base: String) async throws {
        let manifest = ExtensionManifest(
            pkg: "fixture.http", name: "HTTP", lang: "en", versionId: 1,
            iconURL: nil, bundlePath: "http.js", kind: .manga
        )
        // The bridge reports failures as `{ error }`; the bundle decides what to
        // do with them. Here it turns a 404 into an empty page.
        let source = try JSBundleMangaSource(
            manifest: manifest,
            bundle: """
            var extension = {
              popular: function (page) {
                var res = http.get("\(base)/missing.html");
                if (res.error || res.status !== 200) { return { entries: [], hasNextPage: false }; }
                return { entries: [{ url: "/x", title: "X" }], hasNextPage: false };
              }
            };
            """
        )
        let page = try await source.popular(page: 1, filters: FilterState())
        precondition(page.entries.isEmpty, "a 404 must not produce entries")
    }

    // MARK: - Helpers

    private static func unwrap<T>(_ value: T?) throws -> T {
        guard let value else { throw CheckFailure.missingValue }
        return value
    }

    private enum CheckFailure: Error {
        case missingValue
    }
}
