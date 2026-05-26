// SortOrder.swift - Sort orders and direction for the library view

import Foundation

/// Sort orders for the library view
enum SortOrder: String, Codable, CaseIterable, Identifiable {
    case alphabetical = "Alphabetical"
    case lastRead = "Last Read"
    case lastUpdated = "Last Updated"
    case totalChapters = "Total Chapters"
    case unread = "Unread"
    case dateAdded = "Date Added"

    var id: String { rawValue }
    var displayName: String { rawValue }

    var iconName: String {
        switch self {
        case .alphabetical: "textformat.abc"
        case .lastRead: "book"
        case .lastUpdated: "clock"
        case .totalChapters: "list.number"
        case .unread: "eye.slash"
        case .dateAdded: "calendar"
        }
    }
}

/// Sort direction
enum SortDirection: String, Codable, CaseIterable {
    case ascending = "Ascending"
    case descending = "Descending"

    var isAscending: Bool { self == .ascending }

    mutating func toggle() {
        self = self == .ascending ? .descending : .ascending
    }
}
