// Chapter.swift - Chapter model with reading progress and download state

import SwiftData
import SwiftUI

/// A single chapter within a novel
@Model
final class Chapter: Hashable {

    /// Source-specific path identifier
    var path: String = ""

    /// Chapter display name/title
    var name: String = ""

    /// Release date string from the source
    var releaseTime: String?

    /// Whether the user bookmarked this chapter
    var bookmark: Bool = false

    /// Whether the chapter has not been read yet
    var unread: Bool = true

    /// When the user last read this chapter
    var readTime: Date?

    /// Whether the chapter content is saved locally
    var isDownloaded: Bool = false

    /// Parsed chapter number for sorting
    var chapterNumber: Double?

    /// Current page within the chapter
    var page: String = "1"

    /// Sort position/order index
    var position: Int = 0

    /// Reading progress percentage (0–100)
    var progress: Int?

    /// When the chapter was last updated from source
    var updatedTime: Date?

    // MARK: - Relationships

    /// The novel this chapter belongs to
    @Relationship(deleteRule: .nullify)
    var novel: Novel?

    // MARK: - Init

    init(
        path: String,
        name: String,
        releaseTime: String? = nil,
        chapterNumber: Double? = nil,
        position: Int = 0
    ) {
        self.path = path
        self.name = name
        self.releaseTime = releaseTime
        self.chapterNumber = chapterNumber
        self.position = position
    }
}
