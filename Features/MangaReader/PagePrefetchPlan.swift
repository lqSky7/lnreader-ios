// PagePrefetchPlan.swift - Which pages the reader should load, and in what order.
//
// Kept pure and separate from the viewer: the pager and the webtoon strip both
// need the same answer, and getting the order wrong is invisible in a screenshot
// but very visible while scrolling.

import Foundation

enum PagePrefetchPlan {

    /// Pages to load for a reader sitting on `current`, most urgent first.
    ///
    /// The current page is always first, then the next `ahead` pages, then
    /// `behind` pages for scrolling back. Out-of-range indices are dropped, so
    /// callers can pass the plan straight to a loader without clamping.
    static func loadOrder(
        current: Int,
        pageCount: Int,
        ahead: Int = 6,
        behind: Int = 1
    ) -> [Int] {
        guard pageCount > 0 else { return [] }
        let current = min(max(current, 0), pageCount - 1)

        var order = [current]
        var seen: Set<Int> = [current]

        if ahead > 0 {
            for offset in 1...ahead {
                let forward = current + offset
                if forward < pageCount, seen.insert(forward).inserted {
                    order.append(forward)
                }
                // Going back matters less than going forward, so it trails behind.
                if offset <= behind {
                    let backward = current - offset
                    if backward >= 0, seen.insert(backward).inserted {
                        order.append(backward)
                    }
                }
            }
        }

        return order
    }

    /// Whether the reader is close enough to the end to start the next chapter.
    ///
    /// - Parameter threshold: pages from the end, 5 by default.
    static func shouldPreloadNextChapter(
        current: Int,
        pageCount: Int,
        threshold: Int = 5
    ) -> Bool {
        guard pageCount > 0, threshold > 0 else { return false }
        return current >= pageCount - threshold
    }
}

/// How many stitched chapters the webtoon strip keeps.
///
/// The strip appends each chapter it scrolls into and, without a window, never
/// lets one go. Every page whose height becomes known re-measures every row of
/// the flow layout, so a long session got slower with each chapter read. The
/// strip keeps the open chapter, a few behind it for scrolling back, and
/// whatever has been fetched ahead.
enum StripWindow {

    /// Chapters kept above the open one.
    static let behind = 1

    /// Index of the first segment to keep when segment `current` is the open one.
    static func firstKept(current: Int, behind: Int = StripWindow.behind) -> Int {
        max(0, current - max(behind, 0))
    }

    /// How many segments were dropped from the front of `old` to give `new`,
    /// when that is all that happened apart from segments appended at the end.
    /// `nil` when the change is anything else (a reorder, an edit, a new strip),
    /// which the strip answers with a full reload.
    ///
    /// - Parameter same: whether `old[i]` and `new[j]` are the same segment.
    static func leadingDrop(oldCount: Int, newCount: Int, same: (_ old: Int, _ new: Int) -> Bool) -> Int? {
        guard oldCount > 0, newCount > 0 else { return nil }
        for dropped in 0..<oldCount {
            let kept = oldCount - dropped
            guard kept <= newCount else { continue }
            if (0..<kept).allSatisfy({ same(dropped + $0, $0) }) { return dropped }
        }
        return nil
    }
}
