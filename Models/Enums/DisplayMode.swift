// DisplayMode.swift - Grid/list display modes for the library view

import Foundation

/// Display modes for novel grid/list in library
enum DisplayMode: String, Codable, CaseIterable, Identifiable {
    case compact = "Compact"
    case comfortable = "Comfortable"
    case coverOnly = "Cover Only"
    case list = "List"

    var id: String { rawValue }
    var displayName: String { rawValue }

    var iconName: String {
        switch self {
        case .compact: "square.grid.2x2"
        case .comfortable: "square.grid.2x2.fill"
        case .coverOnly: "photo"
        case .list: "list.bullet"
        }
    }
}
