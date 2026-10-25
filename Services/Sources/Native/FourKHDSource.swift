// FourKHDSource.swift - STUB: replaced by the real port.

import Foundation

final class FourKHDSource: MangaSource {
    let key = SourceKey.makeBuiltin(id: "fourkhd")
    let kind = ContentKind.manga
    let name = "4KHD"
    let lang = "all"

    func details(_ entry: SourceEntry) async throws -> SourceEntry { throw SourceError.notSupported("details") }
    func chapters(_ entry: SourceEntry) async throws -> [SourceChapter] { throw SourceError.notSupported("chapters") }
    func pages(_ chapter: SourceChapter) async throws -> [SourcePage] { throw SourceError.notSupported("pages") }
}
