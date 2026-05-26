// LibraryGridView.swift
// Adaptive grid layout for novel covers in the library.

import SwiftUI

struct LibraryGridView: View {
    let novels: [Novel]
    let displayMode: DisplayMode

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: LayoutConstants.gridItemMinSize), spacing: 12)]
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(novels) { novel in
                NavigationLink(value: novel) {
                    NovelGridCell(novel: novel, displayMode: displayMode)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
        .navigationDestination(for: Novel.self) { novel in
            NovelDetailView(novel: novel)
        }
    }
}

// MARK: - Grid Cell

struct NovelGridCell: View {
    let novel: Novel
    let displayMode: DisplayMode

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                NovelCoverView(
                    url: novel.cover,
                    aspectRatio: LayoutConstants.coverAspectRatio
                )

                if novel.chaptersUnread > 0 {
                    BadgeView(count: novel.chaptersUnread)
                        .padding(6)
                }
            }

            if displayMode != .coverOnly {
                Text(novel.name)
                    .font(Typography.caption)
                    .lineLimit(2)
                    .foregroundStyle(.primary)

                if displayMode == .comfortable, let author = novel.author {
                    Text(author)
                        .font(Typography.small)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}
