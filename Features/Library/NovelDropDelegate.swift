// NovelDropDelegate.swift
// DropDelegate implementation for reordering novels inside a grid/list in real time.

import SwiftUI

struct NovelDropDelegate: DropDelegate {
    let item: Novel
    let novels: [Novel]
    @Binding var draggedItem: Novel?
    var onReorder: (Novel, Novel) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggedItem = draggedItem,
              draggedItem != item else { return }

        // Only fire reorder when source and target actually differ in position.
        // This prevents the chaotic constant-shuffling that happened when
        // onReorder was called on every hover frame.
        guard let fromIdx = novels.firstIndex(of: draggedItem),
              let toIdx = novels.firstIndex(of: item),
              fromIdx != toIdx else { return }

        onReorder(draggedItem, item)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedItem = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        // No-op — cleanup happens in performDrop or LibraryView state reset.
    }

    func validateDrop(info: DropInfo) -> Bool {
        return draggedItem != nil
    }
}
