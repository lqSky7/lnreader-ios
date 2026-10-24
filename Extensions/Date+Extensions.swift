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

    /// A section heading for the day this date falls on: "Today", "Yesterday",
    /// the weekday within the last week, otherwise the medium date.
    var daySectionTitle: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) { return "Today" }
        if calendar.isDateInYesterday(self) { return "Yesterday" }
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: self), to: calendar.startOfDay(for: .now)).day ?? 0
        if days > 0, days < 7 { return formatted(.dateTime.weekday(.wide)) }
        return formatted
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
