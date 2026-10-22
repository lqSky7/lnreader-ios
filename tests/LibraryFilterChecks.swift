// LibraryFilterChecks.swift - Library filter rules and per-category store, headless.

import Foundation

@main
struct LibraryFilterChecks {
    static func check(_ condition: Bool, _ message: String) {
        guard condition else { print("FAIL: \(message)"); exit(1) }
    }

    static func main() {
        let unreadStarted = LibraryFilterFacts(unread: 3, total: 10, downloaded: 2, isCompleted: false, isTracked: true)
        let fresh = LibraryFilterFacts(unread: 5, total: 5)
        let finished = LibraryFilterFacts(unread: 0, total: 5, downloaded: 5, isCompleted: true)

        check(LibraryFilter().matches(fresh), "empty filter matches everything")
        check(!LibraryFilter().isActive, "empty filter is inactive")

        var f = LibraryFilter(); f.unread = .include
        check(f.matches(unreadStarted) && f.matches(fresh) && !f.matches(finished), "unread include")
        f.unread = .exclude
        check(!f.matches(fresh) && f.matches(finished), "unread exclude")

        f = LibraryFilter(); f.started = .include
        check(f.matches(unreadStarted) && !f.matches(fresh) && f.matches(finished), "started")

        f = LibraryFilter(); f.downloaded = .include; f.completed = .exclude
        check(f.matches(unreadStarted) && !f.matches(finished) && !f.matches(fresh), "rules combine with AND")

        f = LibraryFilter(); f.tracked = .include
        check(f.matches(unreadStarted) && !f.matches(fresh), "tracked")
        check(!f.needsChapterCounts, "tracked alone needs no counts")
        f.unread = .include
        check(f.needsChapterCounts && f.activeCount == 2, "counts needed, active count")

        check(TriState.off.next == .include && TriState.include.next == .exclude && TriState.exclude.next == .off, "cycle")

        var store = LibraryFilterStore()
        var manga = LibraryFilter(); manga.unread = .include
        store.set(manga, for: "Manga")
        check(store.filter(for: "Manga") == manga, "category filter stored")
        check(!store.filter(for: nil).isActive && !store.filter(for: "Other").isActive, "categories independent")
        let reloaded = LibraryFilterStore(json: store.json)
        check(reloaded.filter(for: "Manga") == manga, "round trips through JSON")
        store.set(LibraryFilter(), for: "Manga")
        check(store.filters.isEmpty, "all-off filter is not stored")
        check(LibraryFilterStore(json: "garbage").filter(for: nil) == LibraryFilter(), "bad JSON falls back to default")

        let old = #"{"unread":"include","future":"x"}"#
        let decoded = try? JSONDecoder().decode(LibraryFilter.self, from: Data(old.utf8))
        check(decoded?.unread == .include && decoded?.tracked == .off, "old data decodes")

        print("PASS: library filters — tri-state rules, AND combination, count need, per-category store, decoding")
    }
}
