// NovelFireSource.swift - STUB: replaced by the real port.

import Foundation

final class NovelFireSource: NovelSource {
    let key = SourceKey.makeBuiltin(id: "novelfire")
    let kind = ContentKind.novel
    let name = "Novel Fire"
    let lang = "English"

    func details(_ entry: SourceEntry) async throws -> SourceEntry { throw SourceError.notSupported("details") }
    func chapters(_ entry: SourceEntry) async throws -> [SourceChapter] { throw SourceError.notSupported("chapters") }
    func chapterHTML(_ chapter: SourceChapter) async throws -> String { throw SourceError.notSupported("chapter text") }
}
