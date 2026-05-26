// StatisticsView.swift
// Library and reading activity metrics.

import SwiftData
import SwiftUI

struct StatisticsView: View {
    @Environment(PluginManager.self) private var pluginManager
    @Query(filter: #Predicate<Novel> { $0.inLibrary }) private var libraryNovels: [Novel]
    @Query private var chapters: [Chapter]
    @Query private var categories: [Category]
    @Query(sort: \ReadingHistory.lastReadAt, order: .reverse)
    private var historyEntries: [ReadingHistory]

    private var unreadCount: Int {
        chapters.filter(\.unread).count
    }

    private var downloadedCount: Int {
        chapters.filter(\.isDownloaded).count
    }

    private var lastReadText: String {
        historyEntries.first?.lastReadAt.timeAgo ?? "Never"
    }

    private var stats: [StatItem] {
        [
            StatItem(title: "Library", value: "\(libraryNovels.count)", icon: "books.vertical"),
            StatItem(title: "Categories", value: "\(categories.count)", icon: "square.grid.2x2"),
            StatItem(title: "Chapters", value: "\(chapters.count)", icon: "list.number"),
            StatItem(title: "Unread", value: "\(unreadCount)", icon: "eye.slash"),
            StatItem(title: "Downloaded", value: "\(downloadedCount)", icon: "arrow.down.circle"),
            StatItem(title: "History", value: "\(historyEntries.count)", icon: "clock"),
            StatItem(title: "Sources", value: "\(pluginManager.installedPlugins.count)", icon: "globe"),
            StatItem(title: "Last Read", value: lastReadText, icon: "clock.arrow.circlepath"),
        ]
    }

    private var columns: [GridItem] {
        [GridItem(.flexible()), GridItem(.flexible())]
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(stats) { item in
                    StatCard(item: item)
                }
            }
            .padding()
        }
        .navigationTitle("Statistics")
    }
}

// MARK: - Supporting Views

private struct StatItem: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let icon: String
}

private struct StatCard: View {
    let item: StatItem

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: item.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)

                Text(item.value)
                    .font(Typography.title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(item.title)
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
