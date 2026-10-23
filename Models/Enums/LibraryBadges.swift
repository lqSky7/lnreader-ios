// LibraryBadges.swift - Which badges a library cell shows, and the language label

import Foundation

/// The badge toggles from Settings. Only unread is on by default.
struct LibraryBadgeSettings: Equatable, Sendable {
    var unread = true
    var downloaded = false
    var language = false
    var new = false

    /// Whether the cell needs the `.newCount` extra from `LibraryChapterCounts`.
    var needsNewCount: Bool { new }
}

/// What one cell shows. A zero count or a missing label means "no badge".
struct LibraryBadges: Equatable, Sendable {
    var unread = 0
    var downloaded = 0
    var new = 0
    var language: String?

    var isEmpty: Bool { unread == 0 && downloaded == 0 && new == 0 && language == nil }

    static func resolve(
        unread: Int, downloaded: Int, new: Int,
        lang: String?, isLocal: Bool,
        settings: LibraryBadgeSettings
    ) -> LibraryBadges {
        LibraryBadges(
            unread: settings.unread ? max(unread, 0) : 0,
            downloaded: settings.downloaded ? max(downloaded, 0) : 0,
            // New chapters are by definition unread; never show more than exist.
            new: settings.new ? min(max(new, 0), max(unread, 0)) : 0,
            language: settings.language ? LanguageLabel.short(lang, isLocal: isLocal) : nil
        )
    }
}

/// A short badge label for a source's language, which arrives either as a
/// tag ("en", "pt-BR") or as a display name ("English").
enum LanguageLabel {
    static func short(_ lang: String?, isLocal: Bool) -> String? {
        if isLocal { return "LOCAL" }
        guard let lang = lang?.trimmingCharacters(in: .whitespaces), !lang.isEmpty else { return nil }
        let lowered = lang.lowercased()
        if ["all", "multi", "multiple", "mul"].contains(lowered) { return "MULTI" }
        if isTag(lowered) { return lowered.replacingOccurrences(of: "_", with: "-").uppercased() }
        return byName[lowered]
    }

    /// `^[a-z]{2,3}([-_][a-z0-9]{2,4})?$`
    private static func isTag(_ s: String) -> Bool {
        let parts = s.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "-" || $0 == "_" })
        guard parts.count <= 2, let language = parts.first,
              (2...3).contains(language.count), language.allSatisfy({ $0.isASCII && $0.isLetter })
        else { return false }
        if parts.count == 2 {
            let region = parts[1]
            return (2...4).contains(region.count) && region.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
        }
        return true
    }

    /// English language names to ISO codes, built once.
    private static let byName: [String: String] = {
        let english = Locale(identifier: "en")
        var table: [String: String] = [:]
        for code in Locale.LanguageCode.isoLanguageCodes where code.identifier.count == 2 {
            if let name = english.localizedString(forLanguageCode: code.identifier) {
                table[name.lowercased()] = code.identifier.uppercased()
            }
        }
        return table
    }()
}
