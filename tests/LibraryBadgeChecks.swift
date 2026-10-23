// LibraryBadgeChecks.swift - Library badge rules and language labels, headless.

import Foundation

@main
struct LibraryBadgeChecks {
    static func check(_ condition: Bool, _ message: String) {
        guard condition else { print("FAIL: \(message)"); exit(1) }
    }

    static func main() {
        let defaults = LibraryBadgeSettings()
        check(defaults.unread && !defaults.downloaded && !defaults.language && !defaults.new, "only unread is on by default")

        let plain = LibraryBadges.resolve(unread: 4, downloaded: 2, new: 1, lang: "en", isLocal: false, settings: defaults)
        check(plain == LibraryBadges(unread: 4), "default settings show unread only")

        var all = LibraryBadgeSettings(); all.downloaded = true; all.language = true; all.new = true
        let full = LibraryBadges.resolve(unread: 4, downloaded: 2, new: 1, lang: "English", isLocal: false, settings: all)
        check(full == LibraryBadges(unread: 4, downloaded: 2, new: 1, language: "EN"), "every badge when all on")

        var none = LibraryBadgeSettings(); none.unread = false
        check(LibraryBadges.resolve(unread: 4, downloaded: 2, new: 1, lang: "en", isLocal: false, settings: none).isEmpty, "all off is empty")
        check(LibraryBadges().isEmpty && !LibraryBadges(unread: 1).isEmpty, "isEmpty")

        check(LibraryBadges.resolve(unread: 2, downloaded: 0, new: 9, lang: nil, isLocal: false, settings: all).new == 2, "new never exceeds unread")
        check(LibraryBadges.resolve(unread: -1, downloaded: -3, new: -2, lang: nil, isLocal: false, settings: all) == LibraryBadges(), "negative counts clamp to none")
        check(LibraryBadges.resolve(unread: 0, downloaded: 0, new: 0, lang: "", isLocal: false, settings: all).language == nil, "empty language has no badge")
        check(all.needsNewCount && !defaults.needsNewCount, "new count is only asked for when shown")

        check(LanguageLabel.short("en", isLocal: false) == "EN", "tag")
        check(LanguageLabel.short("pt-BR", isLocal: false) == "PT-BR", "tag with region")
        check(LanguageLabel.short("zh_Hans", isLocal: false) == "ZH-HANS", "underscore tag")
        check(LanguageLabel.short("English", isLocal: false) == "EN", "English name")
        check(LanguageLabel.short("japanese", isLocal: false) == "JA", "name is case-insensitive")
        check(LanguageLabel.short("all", isLocal: false) == "MULTI" && LanguageLabel.short("Multi", isLocal: false) == "MULTI", "multi-language sources")
        check(LanguageLabel.short("Klingon-ish dialect", isLocal: false) == nil, "unknown name has no badge")
        check(LanguageLabel.short(nil, isLocal: false) == nil && LanguageLabel.short("  ", isLocal: false) == nil, "missing language")
        check(LanguageLabel.short("en", isLocal: true) == "LOCAL", "local books are labelled local")

        print("PASS: library badges — settings, count clamping, new-vs-unread, language labels")
    }
}
