// UpdateStrategy.swift - When library updates should fetch new chapters.

import Foundation

/// How aggressively a library update refreshes this entry's chapter list.
///
/// Raw values match Yokai's constants so the setting survives a `.tachibk`
/// import unchanged.
enum UpdateStrategy: Int, Codable, CaseIterable, Sendable, Hashable {
    /// Always check for new chapters during a library update.
    case always = 0
    /// Fetch the chapter list once, then leave it alone (finished series).
    case onlyFetchOnce = 1
    /// Never fetch during a library update, manual or automatic.
    case never = 2

    var displayName: String {
        switch self {
        case .always: "Always"
        case .onlyFetchOnce: "Only once"
        case .never: "Never"
        }
    }
}

enum LibraryUpdatePolicy {
    static func permits(strategy: UpdateStrategy, hasFetched: Bool, status: EntryStatus,
                        hasUnread: Bool, unreadOnly: Bool, skipCompleted: Bool) -> Bool {
        guard strategy != .never, strategy != .onlyFetchOnce || !hasFetched else { return false }
        if skipCompleted && (status == .completed || status == .publishingFinished) { return false }
        return !unreadOnly || hasUnread
    }
}
