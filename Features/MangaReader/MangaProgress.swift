// MangaProgress.swift - How a page turn maps to stored reading state.
//
// Pure on purpose: the pager and the webtoon strip both call it, and getting
// "finished" wrong is the difference between a chapter being marked read and
// the tracker never updating.

import Foundation

enum MangaProgress {

    struct Update: Equatable {
        /// 0–100, kind-agnostic progress stored on the chapter.
        let progress: Double
        let lastPageRead: Int
        let pagesLeft: Int
        /// Whether this page turn completes the chapter.
        let finished: Bool
    }

    /// State after the reader shows `pageIndex` (0-based) of `pageCount`.
    static func update(pageIndex: Int, pageCount: Int) -> Update {
        guard pageCount > 0 else {
            return Update(progress: 0, lastPageRead: 0, pagesLeft: 0, finished: false)
        }

        let index = min(max(pageIndex, 0), pageCount - 1)
        let progress = Double(index + 1) / Double(pageCount) * 100
        let pagesLeft = max(pageCount - index - 1, 0)

        return Update(
            progress: progress,
            lastPageRead: index,
            pagesLeft: pagesLeft,
            // The last page is the only page that finishes a chapter; reaching
            // 100% by arithmetic is not the same as the user seeing it.
            finished: index == pageCount - 1
        )
    }
}
