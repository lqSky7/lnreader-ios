import Foundation
@main struct NavigationContractChecks {
    static func main() {
        let initial = ["a", "b", "c", "d"]
        precondition(LibraryReordering.move("a", to: "c", in: initial) == ["b", "c", "a", "d"])
        precondition(LibraryReordering.move("d", to: "b", in: initial) == ["a", "d", "b", "c"])
        precondition(LibraryReordering.move("missing", to: "b", in: initial) == initial)
        let reordered = LibraryReordering.move("a", to: "d", in: initial)
        precondition(Set(reordered) == Set(initial) && reordered.count == initial.count)
        precondition(reordered.filter { ["b", "c"].contains($0) } == ["b", "c"])
        for total in [0, 1, 49, 50, 51, 999, 1000, 1003, 10000] {
            let pages = (0..<ChapterPages.count(total: total)).flatMap { Array(ChapterPages.bounds(total: total, page: $0)) }
            precondition(pages == Array(0..<total), "Every chapter must appear once, including the final partial page")
            precondition(ChapterPages.bounds(total: total, page: -1).lowerBound == 0)
            precondition(ChapterPages.bounds(total: total, page: Int.max).upperBound == total)
        }
        print("PASS: stable book moves preserve hidden books; chapter pages cover every chapter through 10,000 without gaps or duplicates")
    }
}
