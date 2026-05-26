// LibraryListView.swift
// Compact list layout alternative for the library.

import SwiftUI

struct LibraryListView: View {
    let novels: [Novel]

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(novels) { novel in
                NavigationLink(value: novel) {
                    LibraryListRow(novel: novel)
                }
                .buttonStyle(.plain)
                Divider()
                    .padding(.leading, 88)
            }
        }
        .navigationDestination(for: Novel.self) { novel in
            NovelDetailView(novel: novel)
        }
    }
}

// MARK: - List Row

struct LibraryListRow: View {
    let novel: Novel

    var body: some View {
        HStack(spacing: 12) {
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
