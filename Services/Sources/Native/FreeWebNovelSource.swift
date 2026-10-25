// FreeWebNovelSource.swift - STUB: replaced by the real port.

import Foundation

final class FreeWebNovelSource: NovelSource {
    let key = SourceKey.makeBuiltin(id: "freewebnovel")
    let kind = ContentKind.novel
    let name = "Free Web Novel"
    let lang = "English"

    func details(_ entry: SourceEntry) async throws -> SourceEntry { throw SourceError.notSupported("details") }
    func chapters(_ entry: SourceEntry) async throws -> [SourceChapter] { throw SourceError.notSupported("chapters") }
    func chapterHTML(_ chapter: SourceChapter) async throws -> String { throw SourceError.notSupported("chapter text") }
}
