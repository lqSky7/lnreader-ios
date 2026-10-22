// V2ScanlatorChecks.swift - The dedup/hide rules, headless.

import Foundation

@main
struct V2ScanlatorChecks {

    static func main() {
        checkMasterToggleOff()
        checkFirstWinsWithoutPriority()
        checkPriorityWins()
        checkDisabledScanlatorHidden()
        checkDisabledWinnerFallsBack()
        checkUnnumberedNeverMerged()
        checkUnknownRanksLast()
        print("PASS: scanlator rules — master toggle, priority dedup, hidden scanlators, "
            + "fallback when the winner is hidden, unnumbered chapters, unknown ranking")
    }

    private static func item(_ number: Double?, _ scanlator: String?) -> ScanlatorRules.Item {
        .init(number: number, scanlator: scanlator)
    }

    private static func checkMasterToggleOff() {
        let chapters = [item(1, "A"), item(1, "B"), item(2, "A")]
        let kept = ScanlatorRules.keptIndices(
            for: chapters,
            preference: ScanlatorPreference(enabled: false)
        )
        precondition(kept == [0, 1, 2], "feature off keeps everything, got \(kept)")
    }

    private static func checkFirstWinsWithoutPriority() {
        let chapters = [item(1, "A"), item(1, "B")]
        let kept = ScanlatorRules.keptIndices(
            for: chapters,
            preference: ScanlatorPreference(enabled: true)
        )
        precondition(kept == [0], "with no priority the first wins, got \(kept)")
    }

    private static func checkPriorityWins() {
        let chapters = [item(1, "A"), item(1, "B"), item(2, "A"), item(2, "B")]
        var preference = ScanlatorPreference(enabled: true)
        preference.priority = ["B", "A"]

        let kept = ScanlatorRules.keptIndices(for: chapters, preference: preference)
        precondition(kept == [1, 3], "B should win both numbers, got \(kept)")

        preference.priority = ["A", "B"]
        let flipped = ScanlatorRules.keptIndices(for: chapters, preference: preference)
        precondition(flipped == [0, 2], "A should win both numbers, got \(flipped)")
    }

    private static func checkDisabledScanlatorHidden() {
        let chapters = [item(1, "A"), item(2, "B"), item(3, "A")]
        var preference = ScanlatorPreference(enabled: true)
        preference.disabled = ["A"]

        let kept = ScanlatorRules.keptIndices(for: chapters, preference: preference)
        precondition(kept == [1], "only B survives, got \(kept)")
    }

    private static func checkDisabledWinnerFallsBack() {
        // B wins on priority but is hidden, so A must be kept instead.
        let chapters = [item(5, "A"), item(5, "B")]
        var preference = ScanlatorPreference(enabled: true)
        preference.priority = ["B", "A"]
        preference.disabled = ["B"]

        let kept = ScanlatorRules.keptIndices(for: chapters, preference: preference)
        precondition(kept == [0], "hidden winner must not delete the chapter, got \(kept)")
    }

    private static func checkUnnumberedNeverMerged() {
        let chapters = [item(nil, "A"), item(nil, "B"), item(0, "A"), item(-1, "B")]
        var preference = ScanlatorPreference(enabled: true)
        preference.priority = ["A", "B"]

        let kept = ScanlatorRules.keptIndices(for: chapters, preference: preference)
        precondition(kept == [0, 1, 2, 3], "unnumbered chapters are never merged, got \(kept)")
    }

    private static func checkUnknownRanksLast() {
        let chapters = [item(7, "Unknown"), item(7, "Known")]
        var preference = ScanlatorPreference(enabled: true)
        preference.priority = ["Known"]

        let kept = ScanlatorRules.keptIndices(for: chapters, preference: preference)
        precondition(kept == [1], "a listed scanlator beats an unlisted one, got \(kept)")
    }
}
