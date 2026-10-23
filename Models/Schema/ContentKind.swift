// ContentKind.swift - The two content types LNReader supports.

import Foundation

/// What a library entry actually is.
///
/// v2 makes manga a first-class citizen next to novels: both share one
/// library, one history, one category system and one download queue, and
/// diverge only in how a chapter is read (HTML vs. images).
enum ContentKind: String, Codable, CaseIterable, Sendable, Hashable {
    case novel
    case manga

    /// Human-readable name used in filters and settings.
    var displayName: String {
        switch self {
        case .novel: "Novels"
        case .manga: "Manga"
        }
    }

    /// Singular form, for "Add to library" style copy.
    var singularName: String {
        switch self {
        case .novel: "Novel"
        case .manga: "Manga"
        }
    }

    /// SF Symbol representing the kind.
    var symbolName: String {
        switch self {
        case .novel: "book.closed.fill"
        case .manga: "photo.stack.fill"
        }
    }

    /// Key prefix a source uses for this kind: `"ln:<id>"` or `"mihon:<id>"`.
    ///
    /// `sourceKey` strings are persisted in backups and in the store, so the
    /// prefixes are part of the on-disk format. Do not change them.
    var sourceKeyPrefix: String {
        switch self {
        case .novel: "ln"
        case .manga: "mihon"
        }
    }
}
