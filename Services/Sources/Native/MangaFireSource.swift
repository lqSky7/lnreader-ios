// MangaFireSource.swift - STUB: replaced by the real port.

import Foundation

final class MangaFireSource: MangaSource {
    let key = SourceKey.makeBuiltin(id: "mangafire")
    let kind = ContentKind.manga
    let name = "MangaFire"
    let lang = "en"

    func details(_ entry: SourceEntry) async throws -> SourceEntry { throw SourceError.notSupported("details") }
    func chapters(_ entry: SourceEntry) async throws -> [SourceChapter] { throw SourceError.notSupported("chapters") }
    func pages(_ chapter: SourceChapter) async throws -> [SourcePage] { throw SourceError.notSupported("pages") }
}
