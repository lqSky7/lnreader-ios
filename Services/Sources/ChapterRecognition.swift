// ChapterRecognition.swift - Works out a chapter's number from its title.
//
// Port of Yokai's `ChapterRecognition` (Apache-2.0, itself from Tachiyomi).
// Sources name chapters "Ch. 12", "Vol.3 Ch.12-extra", "027: Part 002", or
// nothing useful at all, and both sorting and tracker updates depend on a
// comparable number.

import Foundation

enum ChapterRecognition {

    /// `123`, `123.4`, `123.a`, `123.extra`.
    private static let numberPattern = #"([0-9]+)(\.[0-9]+)?(\.?[a-z]+)?"#

    private static let numberRegex = try! NSRegularExpression(pattern: numberPattern)

    /// "Ch.12" — the number directly after the `ch.` prefix wins.
    private static let basicRegex = try! NSRegularExpression(
        pattern: #"(?<=ch\.) *"# + numberPattern
    )

    /// Volume/version/season tags: "Prison School 12 v.1 vol004" → "Prison School 12".
    private static let unwantedRegex = try! NSRegularExpression(
        pattern: #"\b(?:v|ver|vol|version|volume|season|s)[^a-z]?[0-9]+"#
    )

    /// "One Piece 12 special" → "One Piece 12special".
    private static let unwantedWhitespaceRegex = try! NSRegularExpression(
        pattern: #"\s(?=extra|special|omake)"#
    )

    /// Parse the chapter number out of `chapterName`.
    ///
    /// - Parameters:
    ///   - chapterName: the chapter title as the source reports it.
    ///   - mangaTitle: the entry title, removed first so "Ayame 14 1" is 1, not 14.
    ///   - knownNumber: a number the source already provided. Anything `> -1`,
    ///     or the sentinel `-2`, wins over parsing.
    /// - Returns: the number, or `-1` when the title carries none.
    static func parseChapterNumber(
        _ chapterName: String,
        mangaTitle: String = "",
        knownNumber: Double? = nil
    ) -> Double {
        if let knownNumber, knownNumber > -1 || knownNumber == -2 {
            return knownNumber
        }

        var cleaned = chapterName.lowercased()
        if !mangaTitle.isEmpty {
            cleaned = cleaned.replacingOccurrences(of: mangaTitle.lowercased(), with: "")
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
        cleaned = cleaned.replacingOccurrences(of: "-", with: ".")
        cleaned = replacing(unwantedWhitespaceRegex, in: cleaned, with: "")

        let matches = numberRegex.matches(in: cleaned, range: fullRange(cleaned))
        guard !matches.isEmpty else { return knownNumber ?? -1 }

        // More than one number means something else in the title is numeric:
        // strip volume tags, then prefer the "Ch." form.
        if matches.count > 1 {
            let stripped = replacing(unwantedRegex, in: cleaned, with: "")
            if let basic = basicRegex.firstMatch(in: stripped, range: fullRange(stripped)) {
                return number(from: basic, in: stripped)
            }
            if let first = numberRegex.firstMatch(in: stripped, range: fullRange(stripped)) {
                return number(from: first, in: stripped)
            }
        }

        return number(from: matches[0], in: cleaned)
    }

    // MARK: - Match handling

    private static func number(from match: NSTextCheckingResult, in text: String) -> Double {
        guard let integerRange = Range(match.range(at: 1), in: text),
              let integer = Double(text[integerRange])
        else {
            return -1
        }
        let decimal = substring(match, group: 2, in: text)
        let alpha = substring(match, group: 3, in: text)
        return integer + decimalOffset(decimal: decimal, alpha: alpha)
    }

    /// `x.4` → 0.4, `x.a` → 0.1, `x.extra` → 0.99.
    private static func decimalOffset(decimal: String?, alpha: String?) -> Double {
        if let decimal, !decimal.isEmpty {
            return Double(decimal) ?? 0
        }
        guard let alpha, !alpha.isEmpty else { return 0 }

        if alpha.contains("extra") { return 0.99 }
        if alpha.contains("omake") { return 0.98 }
        if alpha.contains("special") { return 0.97 }

        let trimmed = alpha.drop { $0 == "." }
        guard trimmed.count == 1, let character = trimmed.first else { return 0 }
        let value = Int(character.asciiValue ?? 0) - (Int(Character("a").asciiValue ?? 97) - 1)
        guard value >= 1, value < 10 else { return 0 }
        return Double(value) / 10
    }

    private static func substring(
        _ match: NSTextCheckingResult,
        group: Int,
        in text: String
    ) -> String? {
        guard group < match.numberOfRanges,
              let range = Range(match.range(at: group), in: text)
        else {
            return nil
        }
        return String(text[range])
    }

    private static func replacing(
        _ regex: NSRegularExpression,
        in text: String,
        with template: String
    ) -> String {
        regex.stringByReplacingMatches(
            in: text,
            range: fullRange(text),
            withTemplate: template
        )
    }

    private static func fullRange(_ text: String) -> NSRange {
        NSRange(text.startIndex..<text.endIndex, in: text)
    }
}
