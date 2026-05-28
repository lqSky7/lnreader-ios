// LibraryGridView.swift
// Adaptive grid layout for novel covers in the library.

import SwiftUI
import UniformTypeIdentifiers

struct LibraryGridView: View {
    let novels: [Novel]
    let displayMode: DisplayMode
    let isEditing: Bool
    @Binding var draggedItem: Novel?
    var onReorder: (Novel, Novel) -> Void
    var onDelete: (Novel) -> Void
    var onStartEditing: () -> Void
    var onSelect: (Novel) -> Void

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: LayoutConstants.gridItemMinSize), spacing: 12)]
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(novels) { novel in
                if isEditing {
                    EditableGridCell(
                        novel: novel,
                        displayMode: displayMode,
                        isDragging: draggedItem == novel,
                        onDelete: { onDelete(novel) }
                    )
                    .onDrag {
                        draggedItem = novel
                        return NSItemProvider(
                            object: (novel.path + "|" + novel.pluginId) as NSString)
                    }
                    .onDrop(
                        of: [UTType.text],
                        delegate: NovelDropDelegate(
                            item: novel,
                            novels: novels,
                            draggedItem: $draggedItem,
                            onReorder: onReorder
                        ))
                } else {
                    InteractiveGridCell(
                        novel: novel,
                        displayMode: displayMode,
                        onSelect: onSelect,
                        onStartEditing: onStartEditing
                    )
                }
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Editable Grid Cell (edit mode wrapper)

/// Separates the delete badge from the drag surface so taps on the badge
/// aren't swallowed by the drag gesture.
struct EditableGridCell: View {
    let novel: Novel
    let displayMode: DisplayMode
    let isDragging: Bool
    var onDelete: () -> Void

    var body: some View {
        NovelGridCell(
            novel: novel,
            displayMode: displayMode,
            isEditing: true,
            onDelete: onDelete
        )
        .contentShape(Rectangle())
        .wiggle(when: true)
        .opacity(isDragging ? 0.4 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isDragging)
    }
}

// MARK: - Interactive Grid Cell Wrapper

struct InteractiveGridCell: View {
    let novel: Novel
    let displayMode: DisplayMode
    var onSelect: (Novel) -> Void
    var onStartEditing: () -> Void

    @State private var longPressActive = false

    var body: some View {
        Button(action: {
            if longPressActive {
                longPressActive = false
            } else {
                onSelect(novel)
            }
        }) {
            NovelGridCell(
                novel: novel,
                displayMode: displayMode,
                isEditing: false,
                onDelete: {}
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.4)
                .onEnded { _ in
                    #if os(iOS)
                        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                    #endif
                    longPressActive = true
                    onStartEditing()
                }
        )
    }
}

// MARK: - Grid Cell

struct NovelGridCell: View {
    @AppStorage("general.showUnreadBadges") private var showUnreadBadges = true
    let novel: Novel
    let displayMode: DisplayMode
    var isEditing: Bool = false
    var onDelete: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                ZStack(alignment: .topLeading) {
                    NovelCoverView(
                        url: novel.cover,
                        aspectRatio: LayoutConstants.coverAspectRatio
                    )

                    if isEditing {
                        DeleteBadge(action: onDelete)
                            .offset(x: -6, y: -6)
                            .transition(.scale.combined(with: .opacity))
                            .zIndex(10)
                    }
                }

                if showUnreadBadges && novel.chaptersUnread > 0 && !isEditing {
                    BadgeView(count: novel.chaptersUnread)
                        .padding(6)
                }
            }

            if displayMode != .coverOnly {
                VStack(alignment: .leading, spacing: 2) {
                    Text(novel.name)
                        .font(Typography.caption)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(.primary)
                        .frame(height: 36, alignment: .topLeading)

                    if displayMode == .comfortable {
                        Text(novel.author ?? "")
                            .font(Typography.small)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(height: 14, alignment: .topLeading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
