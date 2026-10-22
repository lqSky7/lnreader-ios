// V2ReaderSettingsChecks.swift - Per-series reader settings, headless.

import Foundation

@main
@MainActor
struct V2ReaderSettingsChecks {

    static func main() {
        checkDefaultsWhenNothingStored()
        checkOverrideBeatsDefault()
        checkOverrideIsPerField()
        checkNewDefaultReachesUnoverriddenSeries()
        checkPersistsAcrossInstances()
        checkSeriesAreIndependent()
        checkResetClearsStorage()
        checkMakeDefault()
        checkForwardCompatibleDecoding()
        print("PASS: reader settings — defaults, per-field override, default propagation, "
            + "persistence, series isolation, reset, make default, decoding old data")
    }

    private static func freshDefaults() -> UserDefaults {
        let name = "lnreader-reader-settings-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private static func checkDefaultsWhenNothingStored() {
        let settings = MangaSeriesSettings(key: "s::a", defaults: freshDefaults())
        precondition(settings.resolved == MangaReaderPreferences(readingMode: .pager, direction: .leftToRight),
                     "built-in defaults")
        precondition(!settings.hasOverrides, "nothing overridden")
    }

    private static func checkOverrideBeatsDefault() {
        let defaults = freshDefaults()
        defaults.set("pager", forKey: MangaReaderSettingsKey.readingMode)
        let settings = MangaSeriesSettings(key: "s::a", defaults: defaults)
        settings.setReadingMode(.webtoon)
        precondition(settings.resolved.readingMode == .webtoon, "override wins over the default")
    }

    private static func checkOverrideIsPerField() {
        let defaults = freshDefaults()
        defaults.set("rightToLeft", forKey: MangaReaderSettingsKey.direction)
        let settings = MangaSeriesSettings(key: "s::a", defaults: defaults)
        settings.setReadingMode(.webtoon)
        precondition(settings.resolved.direction == .rightToLeft,
                     "overriding the mode must not freeze the direction")
    }

    private static func checkNewDefaultReachesUnoverriddenSeries() {
        let defaults = freshDefaults()
        let settings = MangaSeriesSettings(key: "s::a", defaults: defaults)
        defaults.set("webtoon", forKey: MangaReaderSettingsKey.readingMode)
        precondition(settings.resolved.readingMode == .webtoon,
                     "a series that never overrode follows a changed default")
    }

    private static func checkPersistsAcrossInstances() {
        let defaults = freshDefaults()
        MangaSeriesSettings(key: "s::a", defaults: defaults).setDirection(.rightToLeft)
        let reloaded = MangaSeriesSettings(key: "s::a", defaults: defaults)
        precondition(reloaded.resolved.direction == .rightToLeft, "override survives a reload")
    }

    private static func checkSeriesAreIndependent() {
        let defaults = freshDefaults()
        MangaSeriesSettings(key: "s::a", defaults: defaults).setReadingMode(.webtoon)
        let other = MangaSeriesSettings(key: "s::b", defaults: defaults)
        precondition(other.resolved.readingMode == .pager, "another series is unaffected")
    }

    private static func checkResetClearsStorage() {
        let defaults = freshDefaults()
        let settings = MangaSeriesSettings(key: "s::a", defaults: defaults)
        settings.setReadingMode(.webtoon)
        settings.reset()
        precondition(!settings.hasOverrides, "reset clears overrides")
        precondition(defaults.data(forKey: "mangareader.s::a") == nil,
                     "an empty override set is removed, not stored as {}")
    }

    private static func checkMakeDefault() {
        let defaults = freshDefaults()
        let a = MangaSeriesSettings(key: "s::a", defaults: defaults)
        a.setReadingMode(.webtoon)
        a.makeDefault()
        precondition(!a.hasOverrides, "promoting to default drops the override")
        let b = MangaSeriesSettings(key: "s::b", defaults: defaults)
        precondition(b.resolved.readingMode == .webtoon, "other series follow the new default")
    }

    private static func checkForwardCompatibleDecoding() {
        // Fields added later are optional, so data written before them loads,
        // and data with fields this build does not know does not break it.
        let defaults = freshDefaults()
        defaults.set(Data(#"{"readingMode":"webtoon","tapZones":"lShaped"}"#.utf8), forKey: "mangareader.s::a")
        let settings = MangaSeriesSettings(key: "s::a", defaults: defaults)
        precondition(settings.resolved.readingMode == .webtoon, "known field decoded despite an unknown one")
        defaults.set(Data("{}".utf8), forKey: "mangareader.s::b")
        precondition(!MangaSeriesSettings(key: "s::b", defaults: defaults).hasOverrides, "empty object loads")
    }
}
