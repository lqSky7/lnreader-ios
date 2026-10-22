// ScanlatorSettings.swift - Per-entry scanlator rules, persisted.
//
// One master toggle turns the feature on; it reveals an ordered list of
// scanlators. Dragging sets priority (used to merge duplicate chapter numbers),
// and each row has its own switch to hide that scanlator's chapters entirely.
//
// Stored in UserDefaults rather than the model: these are view preferences, and
// keeping them out of `Entry` avoids a schema migration for every tuning knob.
// The decision itself lives in `ScanlatorRules`, which is pure.

import Foundation

@Observable
@MainActor
final class ScanlatorSettings {

    /// Entry this belongs to (`sourceKey::url`).
    let key: String

    private(set) var value: ScanlatorPreference
    private let defaults: UserDefaults

    init(key: String, defaults: UserDefaults = .standard) {
        self.key = key
        self.defaults = defaults
        self.value = Self.load(key: key, defaults: defaults)
    }

    var isEnabled: Bool { value.enabled }

    func setEnabled(_ enabled: Bool) {
        mutate { $0.enabled = enabled }
    }

    func setEnabled(_ scanlator: String, _ enabled: Bool) {
        mutate { value in
            if enabled {
                value.disabled.removeAll { $0 == scanlator }
            } else if !value.disabled.contains(scanlator) {
                value.disabled.append(scanlator)
            }
        }
    }

    /// Make `order` the priority list.
    func setPriority(_ order: [String]) {
        mutate { $0.priority = order }
    }

    /// Priority order for `scanlators`: saved ones first, then anything new
    /// appended in the order the source listed it.
    func orderedScanlators(from scanlators: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for name in value.priority where scanlators.contains(name) {
            if seen.insert(name).inserted { result.append(name) }
        }
        for name in scanlators where seen.insert(name).inserted {
            result.append(name)
        }
        return result
    }

    // MARK: - Persistence

    private func mutate(_ body: (inout ScanlatorPreference) -> Void) {
        var updated = value
        body(&updated)
        guard updated != value else { return }
        value = updated
        if let data = try? JSONEncoder().encode(updated) {
            defaults.set(data, forKey: Self.defaultsKey(key))
        }
    }

    private static func defaultsKey(_ key: String) -> String {
        "scanlators.\(key)"
    }

    private static func load(key: String, defaults: UserDefaults) -> ScanlatorPreference {
        guard let data = defaults.data(forKey: defaultsKey(key)),
              let decoded = try? JSONDecoder().decode(ScanlatorPreference.self, from: data)
        else { return ScanlatorPreference() }
        return decoded
    }
}

// MARK: - Applying to the chapter list

extension ScanlatorRules {

    /// Apply a preference to display chapters.
    static func apply(
        _ preference: ScanlatorPreference,
        to chapters: [ChapterDisplay]
    ) -> [ChapterDisplay] {
        guard preference.enabled else { return chapters }

        let items = chapters.map {
            Item(number: $0.chapterNumber, scanlator: $0.scanlator)
        }
        return keptIndices(for: items, preference: preference).map { chapters[$0] }
    }
}
