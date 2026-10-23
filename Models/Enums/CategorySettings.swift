// CategorySettings.swift - Per-category display mode and update scope

import Foundation

/// Bits of `Category.flags`. Persisted on the category (and carried by `.lnbk`
/// backups); Mihon imports leave the flags at 0.
enum CategoryFlags {
    /// Skipped by library-wide and background updates.
    static let excludedFromUpdates = 1 << 0

    static func isExcluded(_ flags: Int) -> Bool { flags & excludedFromUpdates != 0 }

    static func setting(_ flags: Int, excluded: Bool) -> Int {
        excluded ? flags | excludedFromUpdates : flags & ~excludedFromUpdates
    }
}

/// Which entries a library update touches.
enum LibraryUpdateScope {
    /// - `only`: a refresh of one category. It updates every title in it, even
    ///   when the category is excluded from the routine updates.
    /// - Otherwise a title is skipped when any of its categories is excluded;
    ///   exclusion wins, as in Mihon. Uncategorised titles always update.
    static func includes(categories: [String], excluded: Set<String>, only: String?) -> Bool {
        if let only { return categories.contains(only) }
        return !categories.contains { excluded.contains($0) }
    }
}

/// One `DisplayMode` override per category, persisted as a single JSON value.
/// `nil` is the "All" tab. A category with no entry follows the global default.
struct LibraryDisplayStore {
    /// Raw values, so a mode that no longer exists drops one entry, not all.
    private(set) var modes: [String: String]

    init(modes: [String: String] = [:]) { self.modes = modes }

    init(json: String) {
        let decoded = try? JSONDecoder().decode([String: String].self, from: Data(json.utf8))
        self.init(modes: decoded ?? [:])
    }

    var json: String {
        guard let data = try? JSONEncoder().encode(modes) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    func mode(for category: String?, default fallback: DisplayMode) -> DisplayMode {
        modes[category ?? LibraryFilterStore.allKey].flatMap(DisplayMode.init(rawValue:)) ?? fallback
    }

    func hasOverride(for category: String?) -> Bool {
        modes[category ?? LibraryFilterStore.allKey].flatMap(DisplayMode.init(rawValue:)) != nil
    }

    mutating func set(_ mode: DisplayMode, for category: String?) {
        modes[category ?? LibraryFilterStore.allKey] = mode.rawValue
    }

    mutating func reset(_ category: String?) {
        modes[category ?? LibraryFilterStore.allKey] = nil
    }
}
