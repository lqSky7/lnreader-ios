// UpdateRow.swift
// Single update entry showing novel cover thumbnail and chapter info.

import SwiftUI

struct UpdateRow: View {
    let chapter: Chapter

    var body: some View {
        HStack(spacing: 12) {
            // Novel cover thumbnail
            if let novel = chapter.novel {
                NovelCoverView(
                    url: novel.cover,
                    aspectRatio: LayoutConstants.coverAspectRatio
                )
                .frame(width: 44, height: 63)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            VStack(alignment: .leading, spacing: 4) {
                // Novel name
                if let novel = chapter.novel {
                    Text(novel.name)
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                // Chapter name
                Text(chapter.name)
                    .font(Typography.body)
                    .lineLimit(2)

                // Release time
                if let releaseTime = chapter.releaseTime {
                    Text(releaseTime)
                        .font(Typography.small)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // Unread indicator
            if chapter.unread {
                Circle()
                    .fill(AppTheme.accent)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.vertical, 4)
    }
}
