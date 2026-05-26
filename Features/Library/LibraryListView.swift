// LibraryListView.swift
// Compact list layout alternative for the library.

import SwiftUI
import UniformTypeIdentifiers

struct LibraryListView: View {
    let novels: [Novel]
    let isEditing: Bool
    @Binding var draggedItem: Novel?
    var onReorder: (Novel, Novel) -> Void
    var onDelete: (Novel) -> Void
    var onStartEditing: () -> Void
    var onSelect: (Novel) -> Void

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(novels) { novel in
                Group {
                    if isEditing {
                        EditableListRow(
                            novel: novel,
                            isDragging: draggedItem == novel,
                            onDelete: { onDelete(novel) }
                        )
                        .onDrag {
                            self.draggedItem = novel
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
                        InteractiveListRow(
                            novel: novel,
                            onSelect: onSelect,
                            onStartEditing: onStartEditing
                        )
                    }
                }
                Divider()
                    .padding(.leading, isEditing ? 120 : 88)
            }
        }
    }
}

// MARK: - Editable List Row (edit mode wrapper)

/// Separates the delete button from the drag surface so taps on the button
/// aren't swallowed by the drag gesture.
struct EditableListRow: View {
    let novel: Novel
    let isDragging: Bool
    var onDelete: () -> Void

    var body: some View {
        LibraryListRow(
            novel: novel,
            isEditing: true,
            onDelete: onDelete
        )
        .contentShape(Rectangle())
        .wiggle(when: true)
        .opacity(isDragging ? 0.4 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isDragging)
    }
}

// MARK: - Interactive List Row Wrapper

struct InteractiveListRow: View {
    let novel: Novel
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
            LibraryListRow(
                novel: novel,
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

// MARK: - List Row

struct LibraryListRow: View {
    let novel: Novel
    var isEditing: Bool = false
    var onDelete: () -> Void = {}

    var body: some View {
        HStack(spacing: 12) {
            if isEditing {
                Button(action: onDelete) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.red)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .transition(.move(edge: .leading).combined(with: .opacity))
                .zIndex(10)
            }

            NovelCoverView(
                url: novel.cover,
                aspectRatio: LayoutConstants.coverAspectRatio
            )
            .frame(width: 60, height: 86)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(novel.name)
                    .font(Typography.headline)
                    .lineLimit(2)

                if let author = novel.author {
                    Text(author)
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    Label("\(novel.totalChapters)", systemImage: "list.number")
                    if novel.chaptersUnread > 0 {
                        Label("\(novel.chaptersUnread)", systemImage: "eye.slash")
                    }
                }
                .font(Typography.small)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .frame(minHeight: LayoutConstants.listRowHeight)
    }
}
