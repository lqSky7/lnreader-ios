import Foundation

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
}
