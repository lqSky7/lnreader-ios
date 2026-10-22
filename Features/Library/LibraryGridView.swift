// LibraryGridView.swift
// Adaptive grid layout for novel covers in the library.

import SwiftUI
import UniformTypeIdentifiers

struct LibraryGridView: View {
    var transitionNamespace: Namespace.ID? = nil
    let novels: [Entry]
    let displayMode: DisplayMode
    let isEditing: Bool
    @Binding var draggedItem: Entry?
    var onReorder: (Entry, Entry) -> Void
    var onDelete: (Entry) -> Void
    var onStartEditing: () -> Void
    var onSelect: (Entry) -> Void

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
                            object: (novel.url + "|" + novel.sourceKey) as NSString)
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
                        transitionNamespace: transitionNamespace,
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let novel: Entry
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
        .animation(AppMotion.gentle(reduceMotion: reduceMotion), value: isDragging)
    }
}

// MARK: - Interactive Grid Cell Wrapper

struct InteractiveGridCell: View {
    var transitionNamespace: Namespace.ID? = nil
    let novel: Entry
    let displayMode: DisplayMode
    var onSelect: (Entry) -> Void
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
                transitionNamespace: transitionNamespace,
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
    var transitionNamespace: Namespace.ID? = nil
    @AppStorage("general.showUnreadBadges") private var showUnreadBadges = true
    @Environment(\.modelContext) private var modelContext
    let novel: Entry
    let displayMode: DisplayMode
    var isEditing: Bool = false
    var onDelete: () -> Void = {}

    /// Counts come from a cached `fetchCount`, never from walking the entry's
    /// chapter array — see `LibraryChapterCounts`.
    @State private var counts: LibraryChapterCounts.Counts?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                ZStack(alignment: .topLeading) {
                    NovelCoverView(
                        url: novel.displayThumbnailURL,
                        aspectRatio: LayoutConstants.coverAspectRatio
                    )
                    .bookTransitionSource(novel.persistentModelID, in: transitionNamespace)

                    if isEditing {
                        DeleteBadge(action: onDelete)
                            .offset(x: -6, y: -6)
                            .transition(.scale.combined(with: .opacity))
                            .zIndex(10)
                    }
                }

                if showUnreadBadges, !isEditing, let unread = counts?.unread, unread > 0 {
                    BadgeView(count: unread)
                        .padding(6)
                }
            }

            if displayMode != .coverOnly {
                VStack(alignment: .leading, spacing: 2) {
                    Text(novel.displayTitle)
                        .font(Typography.caption)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(.primary)
                        .frame(height: 36, alignment: .topLeading)

                    if displayMode == .comfortable {
                        Text(novel.displayAuthor ?? "")
                            .font(Typography.small)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(height: 14, alignment: .topLeading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task(id: novel.persistentModelID) {
            if let cached = LibraryChapterCounts.shared.cached(novel.persistentModelID) {
                counts = cached
            }
            counts = await LibraryChapterCounts.shared.counts(for: novel, container: modelContext.container)
        }
    }
}
