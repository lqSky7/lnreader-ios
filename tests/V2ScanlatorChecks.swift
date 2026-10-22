// V2ScanlatorChecks.swift - The dedup/hide rules, headless.

import Foundation

@main
struct V2ScanlatorChecks {

    static func main() {
        checkLegacyDecoding()
        checkMasterToggleOff()
        checkHidingWithoutPriority()
        checkFirstWinsWithoutPriority()
        checkPriorityWins()
        checkDisabledScanlatorHidden()
        checkDisabledWinnerFallsBack()
        checkUnnumberedNeverMerged()
        checkUnknownRanksLast()
        print("PASS: scanlator rules — legacy preference decoding, priority toggle, "
            + "hiding without priority, priority dedup, hidden scanlators, "
            + "fallback when the winner is hidden, unnumbered chapters, unknown ranking")
    }

    private static func item(_ number: Double?, _ scanlator: String?) -> ScanlatorRules.Item {
        .init(number: number, scanlator: scanlator)
    }

    private static func checkMasterToggleOff() {
        let chapters = [item(1, "A"), item(1, "B"), item(2, "A")]
        let kept = ScanlatorRules.keptIndices(
            for: chapters,
            preference: ScanlatorPreference(priorityEnabled: false)
        )
        precondition(kept == [0, 1, 2], "feature off keeps everything, got \(kept)")
    }

    private static func checkLegacyDecoding() {
        // The priority toggle was stored as "enabled". Renaming the property
        // must not drop settings people already have.
        let legacy = #"{"enabled":true,"priority":["A"],"disabled":["B"]}"#
        guard let data = legacy.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(ScanlatorPreference.self, from: data) else {
            preconditionFailure("legacy preference JSON no longer decodes")
        }
        precondition(decoded.priorityEnabled, "old \"enabled\" must become priorityEnabled")
        precondition(decoded.priority == ["A"], "priority lost, got \(decoded.priority)")
        precondition(decoded.disabled == ["B"], "disabled lost, got \(decoded.disabled)")

        // And it still writes the same key, so an older build can read it back.
        guard let encoded = try? JSONEncoder().encode(decoded),
              let json = String(data: encoded, encoding: .utf8),
              json.contains("\"enabled\"") else {
            preconditionFailure("preference no longer encodes as \"enabled\"")
        }
    }

    private static func checkHidingWithoutPriority() {
        // Hiding is its own feature: it must work with priority merging off,
        // which it did not before — the whole list was gated behind the toggle.
        let chapters = [item(1, "A"), item(2, "B"), item(3, "A")]
        var preference = ScanlatorPreference(priorityEnabled: false)
        preference.disabled = ["A"]

        let kept = ScanlatorRules.keptIndices(for: chapters, preference: preference)
        precondition(kept == [1], "hiding must not need priority, got \(kept)")
        precondition(preference.hasActiveRules, "a hidden scanlator is an active rule")
    }

    private static func checkFirstWinsWithoutPriority() {
        let chapters = [item(1, "A"), item(1, "B")]
        let kept = ScanlatorRules.keptIndices(
            for: chapters,
            preference: ScanlatorPreference(priorityEnabled: true)
        )
        precondition(kept == [0], "with no priority the first wins, got \(kept)")
    }

    private static func checkPriorityWins() {
        let chapters = [item(1, "A"), item(1, "B"), item(2, "A"), item(2, "B")]
        var preference = ScanlatorPreference(priorityEnabled: true)
        preference.priority = ["B", "A"]

        let kept = ScanlatorRules.keptIndices(for: chapters, preference: preference)
        precondition(kept == [1, 3], "B should win both numbers, got \(kept)")

        preference.priority = ["A", "B"]
        let flipped = ScanlatorRules.keptIndices(for: chapters, preference: preference)
        precondition(flipped == [0, 2], "A should win both numbers, got \(flipped)")
    }

    private static func checkDisabledScanlatorHidden() {
        let chapters = [item(1, "A"), item(2, "B"), item(3, "A")]
        var preference = ScanlatorPreference(priorityEnabled: true)
        preference.disabled = ["A"]

        let kept = ScanlatorRules.keptIndices(for: chapters, preference: preference)
        precondition(kept == [1], "only B survives, got \(kept)")
    }

    private static func checkDisabledWinnerFallsBack() {
        // B wins on priority but is hidden, so A must be kept instead.
        let chapters = [item(5, "A"), item(5, "B")]
        var preference = ScanlatorPreference(priorityEnabled: true)
        preference.priority = ["B", "A"]
        preference.disabled = ["B"]

        let kept = ScanlatorRules.keptIndices(for: chapters, preference: preference)
        precondition(kept == [0], "hidden winner must not delete the chapter, got \(kept)")
    }

    private static func checkUnnumberedNeverMerged() {
        let chapters = [item(nil, "A"), item(nil, "B"), item(0, "A"), item(-1, "B")]
        var preference = ScanlatorPreference(priorityEnabled: true)
        preference.priority = ["A", "B"]

        let kept = ScanlatorRules.keptIndices(for: chapters, preference: preference)
        precondition(kept == [0, 1, 2, 3], "unnumbered chapters are never merged, got \(kept)")
    }

    private static func checkUnknownRanksLast() {
        let chapters = [item(7, "Unknown"), item(7, "Known")]
        var preference = ScanlatorPreference(priorityEnabled: true)
        preference.priority = ["Known"]

        let kept = ScanlatorRules.keptIndices(for: chapters, preference: preference)
        precondition(kept == [1], "a listed scanlator beats an unlisted one, got \(kept)")
    }
}
