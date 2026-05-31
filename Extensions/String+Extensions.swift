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

    /// Formats the string for Bionic Reading by returning a concatenated SwiftUI `Text` view
    /// where the first part of each word is bolded.
    func bionicFormatted() -> Text {
        var formattedText = Text("")
        
        let pattern = "\\p{L}+"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return Text(self)
        }
        
        let range = NSRange(self.startIndex..<self.endIndex, in: self)
        let matches = regex.matches(in: self, options: [], range: range)
        
        var lastIndex = self.startIndex
        
        for match in matches {
            if let matchRange = Range(match.range, in: self) {
                // Append preceding text
                if matchRange.lowerBound > lastIndex {
                    let preceding = String(self[lastIndex..<matchRange.lowerBound])
                    formattedText = formattedText + Text(preceding)
                }
                
                // Format word
                let word = String(self[matchRange])
                let len = word.count
                let boldLen = len <= 3 ? (len == 3 ? 2 : 1) : Int(ceil(Double(len) * 0.5))
                
                let boldPart = String(word.prefix(boldLen))
                let normalPart = String(word.dropFirst(boldLen))
                
                formattedText = formattedText + Text(boldPart).bold()
                if !normalPart.isEmpty {
                    formattedText = formattedText + Text(normalPart)
                }
                
                lastIndex = matchRange.upperBound
            }
        }
        
        if lastIndex < self.endIndex {
            let remaining = String(self[lastIndex..<self.endIndex])
            formattedText = formattedText + Text(remaining)
        }
        
        return formattedText
    }
}
