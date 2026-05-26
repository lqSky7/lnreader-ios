// Novel.swift - Core novel model with metadata and relationships

import SwiftData
import SwiftUI

/// A light novel or web novel tracked by the app
@Model
final class Novel: Hashable {

    #Unique<Novel>([\.path, \.pluginId])

    /// Source-specific path identifier
    var path: String = ""

    /// Identifier for the source plugin
    var pluginId: String = ""

    /// Display title
    var name: String = ""

    /// Cover image URL
    var cover: String?

    /// Novel synopsis/description
    var summary: String?

    /// Author name(s)
    var author: String?

    /// Artist/illustrator name(s)
    var artist: String?

    /// Publication status from source
    var status: NovelStatus = NovelStatus.unknown

    /// Comma-separated genre list
    var genres: String?

    /// Whether the user added this to their library
    var inLibrary: Bool = false

    /// Whether this novel is stored locally
    var isLocal: Bool = false

    /// Total pages available in the source
    var totalPages: Int = 0

    /// When the user last read a chapter
    var lastReadAt: Date?

    /// When the source last updated
    var lastUpdatedAt: Date?

    /// When the novel was added to the library
    var dateAdded: Date = Date.now

    /// Custom sort position for ordering in library drag and drop
    var libraryPosition: Int = 0

    // MARK: - Relationships

    /// All chapters belonging to this novel
    @Relationship(deleteRule: .cascade, inverse: \Chapter.novel)
    var chapters: [Chapter] = []

    /// Categories this novel belongs to
    @Relationship(inverse: \Category.novels)
    var categories: [Category] = []

    // MARK: - Computed Properties

    /// Number of downloaded chapters
    var chaptersDownloaded: Int {
        chapters.filter(\.isDownloaded).count
    }

    /// Number of unread chapters
    var chaptersUnread: Int {
        chapters.filter(\.unread).count
    }

    /// Total number of chapters
    var totalChapters: Int {
        chapters.count
    }

    /// Genres split into an array
    var genreList: [String] {
        genres?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? []
    }

    // MARK: - Init

    init(
        path: String,
        pluginId: String,
        name: String,
        cover: String? = nil,
        summary: String? = nil,
        author: String? = nil,
        artist: String? = nil,
        status: NovelStatus = NovelStatus.unknown,
        genres: String? = nil
    ) {
        self.path = path
        self.pluginId = pluginId
        self.name = name
        self.cover = cover
        self.summary = summary
        self.author = author
        self.artist = artist
        self.status = status
        self.genres = genres
    }
}
