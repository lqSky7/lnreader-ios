import Foundation

extension Date {

    /// A human-readable relative time string (e.g. "2 hours ago").
    ///
    /// Uses `RelativeDateTimeFormatter` with `.full` style for
    /// natural-language output.
    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: self, relativeTo: .now)
    }

    /// The date formatted with `.medium` date style and no time component.
    ///
    /// Example output: "Jan 12, 2025".
    var formatted: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: self)
    }
}
