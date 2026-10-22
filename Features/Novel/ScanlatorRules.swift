// ScanlatorRules.swift - Which chapters survive, given a scanlator preference.
//
// Pure and free of SwiftUI so it can be checked without a simulator: the same
// function decides what the chapter list shows and what a test asserts.

import Foundation

/// Per-entry scanlator preference.
struct ScanlatorPreference: Codable, Equatable {
    var enabled = false
    /// Highest priority first. Unknown scanlators sort after these.
    var priority: [String] = []
    /// Chapters from these scanlators are hidden.
    var disabled: [String] = []

    var disabledSet: Set<String> { Set(disabled) }
}

enum ScanlatorRules {

    /// The only part of a chapter the rules care about.
    struct Item {
        let number: Double?
        let scanlator: String?

        init(number: Double?, scanlator: String?) {
            self.number = number
            self.scanlator = scanlator
        }
    }

    /// Indices to keep, in the original order.
    ///
    /// - Master toggle off → everything.
    /// - Disabled scanlator → its chapters are dropped.
    /// - Master toggle on → one chapter per number: the one whose scanlator ranks
    ///   highest. Chapters with no number are never merged, because there is
    ///   nothing to match them on.
    static func keptIndices(for chapters: [Item], preference: ScanlatorPreference) -> [Int] {
        guard preference.enabled else { return Array(chapters.indices) }

        let disabled = preference.disabledSet

        func isHidden(_ chapter: Item) -> Bool {
            guard let scanlator = chapter.scanlator, !scanlator.isEmpty else { return false }
            return disabled.contains(scanlator)
        }

        var rank: [String: Int] = [:]
        for (index, name) in preference.priority.enumerated() {
            rank[name] = index
        }

        func rankOf(_ chapter: Item) -> Int {
            guard let scanlator = chapter.scanlator, !scanlator.isEmpty else { return Int.max }
            return rank[scanlator] ?? Int.max - 1
        }

        var best: [Double: Int] = [:]
        for (index, chapter) in chapters.enumerated() where !isHidden(chapter) {
            guard let number = chapter.number, number > 0 else { continue }
            if let current = best[number] {
                if rankOf(chapter) < rankOf(chapters[current]) {
                    best[number] = index
                }
            } else {
                best[number] = index
            }
        }

        let winners = Set(best.values)
        return chapters.indices.filter { index in
            let chapter = chapters[index]
            if isHidden(chapter) { return false }
            guard let number = chapter.number, number > 0 else { return true }
            return winners.contains(index)
        }
    }
}
