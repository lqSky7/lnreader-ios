// OmegaScansSource.swift - STUB: replaced by the real port.

import Foundation

final class OmegaScansSource: MangaSource {
    let key = SourceKey.makeBuiltin(id: "omegascans")
    let kind = ContentKind.manga
    let name = "Omega Scans"
    let lang = "en"

    func details(_ entry: SourceEntry) async throws -> SourceEntry { throw SourceError.notSupported("details") }
    func chapters(_ entry: SourceEntry) async throws -> [SourceChapter] { throw SourceError.notSupported("chapters") }
    func pages(_ chapter: SourceChapter) async throws -> [SourcePage] { throw SourceError.notSupported("pages") }
}
