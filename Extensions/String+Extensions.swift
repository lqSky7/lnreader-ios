import Foundation
import SwiftUI

extension String {

    /// The string with leading and trailing whitespace/newlines removed.
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `true` when the string is empty or contains only whitespace.
    var isBlank: Bool {
        trimmed.isEmpty
    }

    /// Parses the string into a `Date` using the given format.
    ///
    /// - Parameter format: A `DateFormatter`-compatible format string
    ///   (e.g. `"yyyy-MM-dd"`).
    /// - Returns: The parsed date, or `nil` if parsing fails.
    func toDate(format: String = "yyyy-MM-dd") -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: self)
    }

    /// Formats the string for Bionic Reading by returning a SwiftUI `Text` view
    /// where the first part of each word is bolded.
    func bionicFormatted() -> Text {
        guard let regex = try? NSRegularExpression(pattern: "\\p{L}+", options: []) else {
            return Text(self)
        }

        var result = AttributedString(self)
        let range = NSRange(startIndex..<endIndex, in: self)
        for match in regex.matches(in: self, options: [], range: range) {
            guard let wordRange = Range(match.range, in: self) else { continue }
            let len = self[wordRange].count
            let boldLen = len <= 3 ? (len == 3 ? 2 : 1) : Int(ceil(Double(len) * 0.5))
            let boldEnd = self.index(wordRange.lowerBound, offsetBy: boldLen)
            guard let lower = AttributedString.Index(wordRange.lowerBound, within: result),
                  let upper = AttributedString.Index(boldEnd, within: result) else { continue }
            result[lower..<upper].inlinePresentationIntent = .stronglyEmphasized
        }
        return Text(result)
    }
}
