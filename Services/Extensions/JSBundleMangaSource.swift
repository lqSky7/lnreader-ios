// JSBundleMangaSource.swift - Adapts a JS extension bundle to MangaSource.
//
// One adapter for every transpiled extension: the bundle owns site logic, this
// owns the translation into the app's value types.

import Foundation

final class JSBundleMangaSource: MangaSource {

    let manifest: ExtensionManifest
    private let host: JSExtensionHost

    init(manifest: ExtensionManifest, bundle: String) throws {
        self.manifest = manifest
        self.host = try JSExtensionHost(
            bundle: bundle,
            sourceKey: SourceKey.make(kind: manifest.kind, id: manifest.pkg)
        )
    }

    // MARK: CatalogSource

    var key: String { SourceKey.make(kind: manifest.kind, id: manifest.pkg) }
    var kind: ContentKind { manifest.kind }
    var name: String { manifest.name }
    var lang: String { manifest.lang }
    var iconURL: String? { manifest.iconURL }
    var iconAsset: String? { manifest.iconAsset }
    var supportsLatest: Bool { host.supportsLatest }

    func popular(page: Int, filters: FilterState) async throws -> EntriesPage {
        try entriesPage(from: await host.callAsync("popular", [page]))
    }

    func latest(page: Int, filters: FilterState) async throws -> EntriesPage {
        guard supportsLatest else { return try await popular(page: page, filters: filters) }
        return try entriesPage(from: await host.callAsync("latest", [page]))
    }

    func search(query: String, page: Int, filters: FilterState) async throws -> EntriesPage {
        try entriesPage(from: await host.callAsync("search", [query, page]))
    }

    func details(_ entry: SourceEntry) async throws -> SourceEntry {
        let raw = try await host.callAsync("details", [entry.url])
        guard let mapped = Self.entry(from: raw, sourceKey: key, kind: kind) else {
            throw SourceError.parseFailed("details returned no entry for \(entry.url)")
        }
        return mapped
    }

    func chapters(_ entry: SourceEntry) async throws -> [SourceChapter] {
        let raw = try await host.callAsync("chapters", [entry.url])
        guard let items = raw as? [[String: Any]] else { return [] }
        return items.compactMap(Self.chapter(from:))
    }

    // MARK: MangaSource

    func pages(_ chapter: SourceChapter) async throws -> [SourcePage] {
        let raw = try await host.callAsync("pages", [chapter.url])
        guard let items = raw as? [[String: Any]] else { return [] }
        return items.enumerated().compactMap { index, item in
            guard let url = item["url"] as? String, !url.isEmpty else { return nil }
            let headers = item["headers"] as? [String: String] ?? [:]
            return SourcePage(index: index, url: url, headers: headers)
        }
    }

    // MARK: - Mapping

    private func entriesPage(from raw: Any) throws -> EntriesPage {
        guard let object = raw as? [String: Any] else {
            throw SourceError.parseFailed("expected an object with `entries`")
        }
        let items = object["entries"] as? [[String: Any]] ?? []
        let entries = items.compactMap { Self.entry(from: $0, sourceKey: key, kind: kind) }
        let hasNext = object["hasNextPage"] as? Bool ?? false
        return EntriesPage(entries: entries, hasNextPage: hasNext)
    }

    static func entry(
        from raw: Any,
        sourceKey: String,
        kind: ContentKind
    ) -> SourceEntry? {
        guard let object = raw as? [String: Any],
              let url = object["url"] as? String, !url.isEmpty,
              let title = object["title"] as? String, !title.isEmpty
        else { return nil }

        return SourceEntry(
            sourceKey: sourceKey,
            kind: kind,
            url: url,
            title: title,
            thumbnailURL: object["thumbnailURL"] as? String,
            author: object["author"] as? String,
            artist: object["artist"] as? String,
            description: object["description"] as? String,
            genres: Self.uniqueGenres(object["genres"] as? [String] ?? []),
            status: EntryStatus.parse(object["status"] as? String)
        )
    }

    /// Genres are shown in a `ForEach` keyed by their text, so a source that
    /// repeats one would make SwiftUI misbehave.
    private static func uniqueGenres(_ genres: [String]) -> [String] {
        var seen = Set<String>()
        return genres.compactMap { genre in
            let trimmed = genre.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty || !seen.insert(trimmed.lowercased()).inserted ? nil : trimmed
        }
    }

    static func chapter(from object: [String: Any]) -> SourceChapter? {
        guard let url = object["url"] as? String, !url.isEmpty,
              let name = object["name"] as? String, !name.isEmpty
        else { return nil }

        // `number` may arrive as Int, Double or String depending on how the
        // bundle built it; -1 means "no number", which ChapterRecognition fills.
        let number: Double = {
            if let value = object["number"] as? Double { return value }
            if let value = object["number"] as? Int { return Double(value) }
            if let value = object["number"] as? String, let parsed = Double(value) { return parsed }
            return -1
        }()

        return SourceChapter(
            url: url,
            name: name,
            chapterNumber: number,
            scanlator: object["scanlator"] as? String,
            dateUpload: DateParsing.parse(object["dateUpload"] as? String)
        )
    }
}
