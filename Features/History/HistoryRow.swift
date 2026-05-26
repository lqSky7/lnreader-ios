// HistoryRow.swift
// Single history entry showing novel, chapter, and time ago.

import SwiftUI

struct HistoryRow: View {
    let entry: ReadingHistory
    @Environment(PluginManager.self) private var pluginManager

    private var sourceName: String {
        pluginManager.pluginName(for: entry.pluginId)
    }

    var body: some View {
        HStack(spacing: 12) {
            NovelCoverView(
                url: entry.novelCover,
                aspectRatio: LayoutConstants.coverAspectRatio
            )
            .frame(width: 44, height: 63)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.novelName)
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(entry.chapterName)
                    .font(Typography.body)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text(sourceName)
                        .font(Typography.small)
                        .foregroundStyle(.tertiary)

                    if let progress = entry.progress, progress > 0 {
                        Text("\(progress)%")
                            .font(Typography.small)
                            .foregroundStyle(AppTheme.accent)
                    }
                }
            }

            Spacer()

            Text(entry.lastReadAt.timeAgo)
                .font(Typography.small)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    HistoryRow(
        entry: ReadingHistory(
            novelId: 1,
            chapterID: 12,
            novelName: "Sample Novel",
            novelCover: "https://picsum.photos/300/420?random=3",
            chapterName: "Chapter 12: A Long Night",
            pluginId: "mock-source",
            progress: 55
        )
    )
    .environment(PluginManager())
    .padding()
}
