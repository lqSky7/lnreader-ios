// LibrarySortChecks.swift - Library sort rules and per-category store, headless.

import Foundation

@main
struct LibrarySortChecks {
    static func check(_ condition: Bool, _ message: String) {
        guard condition else { print("FAIL: \(message)"); exit(1) }
    }

    static func titles(_ items: [LibrarySortFacts], _ sort: LibrarySort) -> [String] {
        LibrarySorter.sorted(items, by: sort) { $0 }.map(\.title)
    }

    static func main() {
        let day: TimeInterval = 86_400
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let a = LibrarySortFacts(title: "Alpha", libraryOrder: 2, dateAdded: now - 3 * day, lastReadAt: now - day,
                                 lastChecked: now - 2 * day, total: 10, unread: 4, latestUpload: now - 5 * day, latestFetch: nil)
        let b = LibrarySortFacts(title: "bravo", libraryOrder: 0, dateAdded: now - 2 * day, lastReadAt: nil,
                                 lastChecked: now - 3 * day, total: 50, unread: 0, latestUpload: now - day, latestFetch: now - day)
        let c = LibrarySortFacts(title: "Chapter 10", libraryOrder: 1, dateAdded: now - day, lastReadAt: now - 2 * day,
                                 lastChecked: nil, total: 5, unread: 5, latestUpload: nil, latestFetch: now - 4 * day)
        let all = [a, b, c]

        check(titles(all, LibrarySort(order: .alphabetical)) == ["Alpha", "bravo", "Chapter 10"], "A to Z ascending, case-insensitive")
        check(titles(all, LibrarySort(order: .alphabetical, direction: .descending)) == ["Chapter 10", "bravo", "Alpha"], "alphabetical descending")
        check(titles(all, LibrarySort(order: .custom)) == ["bravo", "Chapter 10", "Alpha"], "custom follows libraryOrder")
        check(titles(all, LibrarySort(order: .lastRead)) == ["Alpha", "Chapter 10", "bravo"], "last read newest first, never-read last")
        check(titles(all, LibrarySort(order: .lastRead, direction: .ascending)) == ["bravo", "Chapter 10", "Alpha"], "last read oldest first")
        check(titles(all, LibrarySort(order: .lastUpdated)) == ["Alpha", "bravo", "Chapter 10"], "last checked, never-checked last")
        check(titles(all, LibrarySort(order: .totalChapters)) == ["bravo", "Alpha", "Chapter 10"], "most chapters first")
        check(titles(all, LibrarySort(order: .unread)) == ["Chapter 10", "Alpha", "bravo"], "most unread first")
        check(titles(all, LibrarySort(order: .dateAdded)) == ["Chapter 10", "bravo", "Alpha"], "newest added first")
        check(titles(all, LibrarySort(order: .latestChapter)) == ["bravo", "Alpha", "Chapter 10"], "latest chapter, no upload date last")
        check(titles(all, LibrarySort(order: .chapterFetched)) == ["bravo", "Chapter 10", "Alpha"], "chapter fetch date, nil last")

        let twins = [LibrarySortFacts(title: "Zed", unread: 1), LibrarySortFacts(title: "Ace", unread: 1)]
        check(titles(twins, LibrarySort(order: .unread)) == ["Ace", "Zed"], "ties break by title")
        check(titles(twins, LibrarySort(order: .unread, direction: .ascending)) == ["Ace", "Zed"], "ties break by title in either direction")

        var sort = LibrarySort(order: .lastRead)
        check(sort.direction == .descending, "last read starts newest first")
        sort.select(.lastRead)
        check(sort.direction == .ascending, "selecting the current order flips direction")
        sort.select(.alphabetical)
        check(sort == LibrarySort(order: .alphabetical, direction: .ascending), "a new order starts in its natural direction")
        check(LibrarySort(order: .unread).needsChapterCounts && !LibrarySort(order: .unread).needsChapterDates, "unread needs counts only")
        check(LibrarySort(order: .latestChapter).needsChapterDates && !LibrarySort(order: .dateAdded).needsChapterCounts, "dates need the date pass")

        let fallback = LibrarySort(order: .lastRead, direction: .descending)
        var store = LibrarySortStore()
        check(store.sort(for: "Manga", default: fallback) == fallback, "no override follows the default")
        store.set(LibrarySort(order: .unread), for: "Manga")
        check(store.sort(for: "Manga", default: fallback).order == .unread, "category override wins")
        check(store.sort(for: nil, default: fallback) == fallback && store.sort(for: "Other", default: fallback) == fallback, "categories independent")
        check(store.hasOverride(for: "Manga") && !store.hasOverride(for: nil), "override flag")
        let reloaded = LibrarySortStore(json: store.json)
        check(reloaded.sort(for: "Manga", default: fallback) == LibrarySort(order: .unread), "round trips through JSON")
        store.reset("Manga")
        check(store.sorts.isEmpty, "reset removes the override")
        check(LibrarySortStore(json: "garbage").sort(for: nil, default: fallback) == fallback, "bad JSON falls back to default")

        let old = #"{"order":"Unread","future":"x"}"#
        let decoded = try? JSONDecoder().decode(LibrarySort.self, from: Data(old.utf8))
        check(decoded?.order == .unread && decoded?.direction == .descending, "old data decodes")

        print("PASS: library sorts — every order, direction, nil handling, tie-breaks, per-category store, decoding")
    }
}
