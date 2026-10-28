// SourceFilterStore.swift - On-disk copy of filter lists that a source scrapes from its site.
//
// Plain JSON files in Application Support, not SwiftData, so saving one never re-runs a `@Query`.
// A copy older than `maxAge` is still shown; Browse refreshes it quietly in the background.

import Foundation

enum SourceFilterStore {

    struct Entry: Codable, Sendable {
        let filters: [SourceFilter]
        let fetchedAt: Date

        var isStale: Bool { Date().timeIntervalSince(fetchedAt) > SourceFilterStore.maxAge }
    }

    /// 30 days.
    static let maxAge: TimeInterval = 30 * 24 * 60 * 60

    static func load(sourceKey: String) -> Entry? {
        guard let url = fileURL(for: sourceKey), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Entry.self, from: data)
    }

    @discardableResult
    static func save(_ filters: [SourceFilter], sourceKey: String) -> Entry? {
        guard let url = fileURL(for: sourceKey) else { return nil }
        let entry = Entry(filters: filters, fetchedAt: Date())
        guard let data = try? JSONEncoder().encode(entry) else { return nil }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        do { try data.write(to: url, options: .atomic) } catch { return nil }
        return entry
    }

    private static func fileURL(for sourceKey: String) -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
              let name = sourceKey.addingPercentEncoding(withAllowedCharacters: .alphanumerics)
        else { return nil }
        return base.appendingPathComponent("SourceFilters", isDirectory: true)
            .appendingPathComponent("\(name).json")
    }
}
