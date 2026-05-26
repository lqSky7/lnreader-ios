// NovelStatus.swift - Reading/publication status of a novel from its source

import Foundation

/// Reading status of a novel from its source
enum NovelStatus: String, Codable, CaseIterable, Identifiable {
    case unknown = "Unknown"
    case ongoing = "Ongoing"
    case completed = "Completed"
    case licensed = "Licensed"
    case publishingFinished = "Publishing Finished"
    case cancelled = "Cancelled"
    case onHiatus = "On Hiatus"

    var id: String { rawValue }

    var displayName: String { rawValue }

    var iconName: String {
        switch self {
        case .unknown: "questionmark.circle"
        case .ongoing: "clock.arrow.circlepath"
        case .completed: "checkmark.circle.fill"
        case .licensed: "lock.fill"
        case .publishingFinished: "flag.checkered"
        case .cancelled: "xmark.circle.fill"
        case .onHiatus: "pause.circle.fill"
        }
    }
}
