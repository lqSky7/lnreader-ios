// ReadingHistory.swift - Denormalized reading history for the recents view

import SwiftData
import SwiftUI

/// A denormalized reading history entry for quick access in the history/recents view
@Model
final class ReadingHistory: Hashable {

    /// Reference to the novel's persistent ID
    var novelId: Int = 0

    /// Reference to the chapter's persistent ID
    var chapterID: Int = 0

    /// Cached novel title for display without fetching
    var novelName: String = ""

    /// Cached novel cover URL for display without fetching
    var novelCover: String?

    /// Cached chapter title for display without fetching
    var chapterName: String = ""

    /// Source plugin identifier
    var pluginId: String = ""

    /// When this history entry was recorded
    var lastReadAt: Date = Date.now

    /// Reading progress percentage at time of recording
    var progress: Int?

    // MARK: - Init

    init(
        novelId: Int,
        chapterID: Int,
        novelName: String,
        novelCover: String? = nil,
        chapterName: String,
        pluginId: String,
        progress: Int? = nil
    ) {
        self.novelId = novelId
        self.chapterID = chapterID
        self.novelName = novelName
        self.novelCover = novelCover
        self.chapterName = chapterName
        self.pluginId = pluginId
        self.progress = progress
    }
}
