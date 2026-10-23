// UpdateRow.swift
// Single update entry showing book cover thumbnail and chapter info.

import SwiftUI

struct UpdateRow: View {
    let chapter: Chapter

    var body: some View {
        HStack(spacing: 12) {
            // Book cover thumbnail
            if let entry = chapter.entry {
                NovelCoverView(
                    url: entry.displayThumbnailURL,
                    aspectRatio: LayoutConstants.coverAspectRatio
                )
                .frame(width: 44, height: 63)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            VStack(alignment: .leading, spacing: 4) {
                // Book title
                if let entry = chapter.entry {
                    Text(entry.displayTitle)
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                // Chapter name
                Text(chapter.name)
                    .font(Typography.body)
                    .lineLimit(2)

                // Release date
                if let released = chapter.dateUpload?.formatted {
                    Text(released)
                        .font(Typography.small)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // Unread indicator
            if !chapter.read {
                Circle()
                    .fill(Color.primary)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.vertical, 4)
    }
}
