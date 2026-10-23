// SourceModels.swift - Values exchanged with sources.
//
// These are deliberately source-agnostic: an LN JS plugin and a transpiled
// Mihon extension both hand back the same shapes, so the rest of the app never
// branches on which runtime produced the data.

import Foundation

// MARK: - Entry

/// A novel or manga as a source describes it.
///
/// `url` is *source-relative*: a plugin path for LN sources (`"novel/foo-123"`)
/// and a relative URL for Mihon sources (`"/manga/foo"`). Resolving it against
/// the source's base URL is the source's job, not the caller's.
struct SourceEntry: Identifiable, Hashable, Sendable {

    let sourceKey: String
    let kind: ContentKind
    let url: String
    let title: String
    let thumbnailURL: String?
    let author: String?
    let artist: String?
    let description: String?
    let genres: [String]
    let status: EntryStatus

    /// Stable identity: an entry is unique per (source, url), matching the
    /// `#Unique` constraint on the stored `Entry`.
    var id: String { "\(sourceKey)::\(url)" }

    init(
        sourceKey: String,
        kind: ContentKind,
        url: String,
        title: String,
        thumbnailURL: String? = nil,
        author: String? = nil,
        artist: String? = nil,
        description: String? = nil,
        genres: [String] = [],
        status: EntryStatus = .unknown
    ) {
        self.sourceKey = sourceKey
        self.kind = kind
        self.url = url
        self.title = title
        self.thumbnailURL = thumbnailURL
        self.author = author
        self.artist = artist
        self.description = description
        self.genres = genres
        self.status = status
    }
}

// MARK: - Pages of entries

/// One page of browse/search results.
struct EntriesPage: Sendable {
    let entries: [SourceEntry]
    /// Whether another page exists. Sources that can't tell say `false`.
    let hasNextPage: Bool

    init(entries: [SourceEntry], hasNextPage: Bool = false) {
        self.entries = entries
        self.hasNextPage = hasNextPage
    }
}

// MARK: - Chapter

/// A chapter as a source describes it.
struct SourceChapter: Identifiable, Hashable, Sendable {

    let url: String
    let name: String
    /// `-1` when the source gives nothing usable.
    let chapterNumber: Double
    let scanlator: String?
    let dateUpload: Date?

    var id: String { url }

    init(
        url: String,
        name: String,
        chapterNumber: Double = -1,
        scanlator: String? = nil,
        dateUpload: Date? = nil
    ) {
        self.url = url
        self.name = name
        self.chapterNumber = chapterNumber
        self.scanlator = scanlator
        self.dateUpload = dateUpload
    }
}

// MARK: - Image page

/// One page of a manga chapter.
///
/// The URL is resolved lazily: some sources only produce a signed URL after a
/// per-chapter request, and holding 200 of them in memory is pointless when the
/// reader shows one at a time.
struct SourcePage: Identifiable, Hashable, Sendable {

    /// 0-based page index.
    let index: Int
    let url: String
    /// Extra headers the CDN needs (Referer, auth token).
    let headers: [String: String]

    var id: Int { index }

    init(index: Int, url: String, headers: [String: String] = [:]) {
        self.index = index
        self.url = url
        self.headers = headers
    }
}

// MARK: - Errors

/// Failures a source can report.
enum SourceError: LocalizedError, Equatable {
    case notSupported(String)
    case entryNotFound(String)
    case emptyResponse(String)
    case parseFailed(String)

    var errorDescription: String? {
        switch self {
        case .notSupported(let what): "Source does not support \(what)"
        case .entryNotFound(let url): "Entry not found: \(url)"
        case .emptyResponse(let what): "Source returned no \(what)"
        case .parseFailed(let detail): "Could not parse source response: \(detail)"
        }
    }
}
