// DateParsing.swift - Lenient date parsing for source-supplied strings.

import Foundation

/// Parses the release dates sources report.
///
/// Sources are wildly inconsistent here: ISO-8601 from JSON APIs, `"Jan 2,
/// 2024"` from scraped pages, `"2 hours ago"` from a few, and empty strings
/// everywhere. Anything unparseable returns `nil`; callers fall back to
/// `dateFetch` rather than inventing a date.
enum DateParsing {

    private static let formatters: [DateFormatter] = {
        let patterns = [
            "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ",
            "yyyy-MM-dd'T'HH:mm:ssZZZZZ",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd",
            "dd MMM yyyy",
            "d MMM yyyy",
            "MMM d, yyyy",
            "MMMM d, yyyy",
            "dd/MM/yyyy",
            "MM/dd/yyyy",
        ]
        return patterns.map { pattern in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = pattern
            return formatter
        }
    }()

    private static let isoFormatter = ISO8601DateFormatter()

    /// Best-effort parse. Never throws.
    static func parse(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let date = isoFormatter.date(from: trimmed) {
            return date
        }

        for formatter in formatters where formatter.date(from: trimmed) != nil {
            return formatter.date(from: trimmed)
        }

        // "2 hours ago" / "3 days ago" — common on scraped chapter lists.
        if let relative = parseRelative(trimmed) {
            return relative
        }

        return nil
    }

    private static func parseRelative(_ raw: String) -> Date? {
        let lowercased = raw.lowercased()
        let components = lowercased.split(separator: " ")
        guard components.count >= 3,
              let amount = Double(components[0]),
              components[2].hasPrefix("ago") || components.last?.hasPrefix("ago") == true
        else {
            return nil
        }

        let unit = components[1]
        let seconds: Double
        switch unit {
        case "second", "seconds", "sec", "secs": seconds = 1
        case "minute", "minutes", "min", "mins": seconds = 60
        case "hour", "hours", "hr", "hrs": seconds = 3600
        case "day", "days": seconds = 86_400
        case "week", "weeks": seconds = 604_800
        case "month", "months": seconds = 2_592_000
        case "year", "years": seconds = 31_536_000
        default: return nil
        }
        return Date.now.addingTimeInterval(-amount * seconds)
    }
}
