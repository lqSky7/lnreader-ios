// ChapterRow.swift
// Single chapter row with unread indicator, release time, and status icons.

import SwiftUI

struct ChapterRow: View {
    let chapter: ChapterDisplay
    let novel: Novel?
    let pluginId: String

    var body: some View {
        NavigationLink {
            ReaderView(
                chapterPath: chapter.path,
                chapterName: chapter.name,
                pluginId: pluginId,
                novelPath: novel?.path
            )
            .id(chapter.path)
        } label: {
            HStack(spacing: 12) {
                // Unread indicator dot
                Circle()
                    .fill(chapter.unread ? AppTheme.accent : .clear)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 4) {
                    Text(chapter.name)
                        .font(Typography.body)
                        .foregroundStyle(chapter.unread ? .primary : .secondary)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        if let releaseTime = chapter.releaseTime {
                            Text(releaseTime)
                                .font(Typography.small)
                                .foregroundStyle(.tertiary)
                        }

                        if let progress = chapter.progress, progress > 0 {
                            Text("\(progress)%")
                                .font(Typography.small)
                                .foregroundStyle(AppTheme.accent)
                        }
                    }
                }

                Spacer()

                // Status icons
                HStack(spacing: 8) {
                    if chapter.bookmarked {
                        Image(systemName: "bookmark.fill")
                            .foregroundStyle(AppTheme.accent)
                            .font(Typography.small)
                    }
                    if chapter.downloaded {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(Typography.small)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(.systemBackground))
        }
        .buttonStyle(.plain)
    }
}
