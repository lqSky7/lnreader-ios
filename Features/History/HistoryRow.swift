// HistoryRow.swift
// Single history entry showing the book, chapter, and time ago.

import SwiftUI

struct HistoryRow: View {
    let history: History
    @Environment(SourceManager.self) private var sourceManager

    private var entry: Entry? { history.chapter?.entry }

    private var sourceName: String {
        guard let entry else { return "" }
        return sourceManager.source(forKey: entry.sourceKey)?.name
            ?? SourceKey.identifier(from: entry.sourceKey)
    }

    var body: some View {
        HStack(spacing: 12) {
            NovelCoverView(
                url: entry?.displayThumbnailURL,
                aspectRatio: LayoutConstants.coverAspectRatio
            )
            .frame(width: 44, height: 63)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                Text(entry?.displayTitle ?? "Unknown")
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(history.chapter?.name ?? "")
                    .font(Typography.body)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text(sourceName)
                        .font(Typography.small)
                        .foregroundStyle(.tertiary)

                    if let progress = history.chapter?.progress, progress > 0, progress < 100 {
                        Text("\(Int(progress))%")
                            .font(Typography.small)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            Text(history.lastRead.timeAgo)
                .font(Typography.small)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
