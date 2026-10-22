// DownloadState.swift - Lifecycle of one chapter download.

import Foundation

/// State of a single chapter download in the persisted queue.
///
/// Raw values are stored, so append only.
enum DownloadState: String, Codable, CaseIterable, Sendable, Hashable {
    /// Waiting for a slot in the queue.
    case queued
    /// Currently fetching pages.
    case downloading
    /// Paused by the user.
    case paused
    /// Finished and on disk.
    case completed
    /// Gave up after retries; `DownloadItem.error` holds the reason.
    case failed

    var isTerminal: Bool {
        self == .completed || self == .failed
    }
}
