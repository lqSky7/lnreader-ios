// MoreView.swift
// Settings hub with quick stats and navigation to settings screens.

import SwiftData
import SwiftUI

struct MoreView: View {
    @Environment(PluginManager.self) private var pluginManager
    @Query(filter: #Predicate<Novel> { $0.inLibrary }) private var libraryNovels: [Novel]
    @Query private var chapters: [Chapter]
    @Query private var historyEntries: [ReadingHistory]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    overviewCard
                }

                Section("Insights") {
                    NavigationLink {
                        StatisticsView()
                    } label: {
                        MoreRow(
                            icon: "chart.bar",
                            title: "Statistics",
                            subtitle: "Library and reading insights"
                        )
                    }
                }

                Section("Settings") {
                    NavigationLink {
                        GeneralSettingsView()
                    } label: {
                        MoreRow(
                            icon: "gearshape",
                            title: "General",
                            subtitle: "Library, updates, and defaults"
                        )
                    }

                    NavigationLink {
                        AppearanceSettingsView()
                    } label: {
                        MoreRow(
                            icon: "paintbrush",
                            title: "Appearance",
                            subtitle: "Theme, glass, and cover style"
                        )
                    }

                    NavigationLink {
                        ReaderSettingsView()
                    } label: {
                        MoreRow(
                            icon: "textformat",
                            title: "Reader",
                            subtitle: "Typography and layout"
                        )
                    }

                    NavigationLink {
                        AdvancedSettingsView()
                    } label: {
                        MoreRow(
                            icon: "slider.horizontal.3",
                            title: "Advanced",
                            subtitle: "Diagnostics and maintenance"
                        )
                    }
                }

                Section("About") {
                    NavigationLink {
                        AboutView()
                    } label: {
                        MoreRow(
                            icon: "info.circle",
                            title: "About",
                            subtitle: "App info and links"
                        )
                    }
                }
            }
            .navigationTitle("More")
        }
    }

    // MARK: - Overview

    private var unreadCount: Int {
        chapters.filter(\.unread).count
    }

    private var stats: [StatItem] {
        [
            StatItem(title: "Library", value: "\(libraryNovels.count)", icon: "books.vertical"),
            StatItem(title: "Unread", value: "\(unreadCount)", icon: "eye.slash"),
            StatItem(title: "History", value: "\(historyEntries.count)", icon: "clock"),
            StatItem(title: "Sources", value: "\(pluginManager.installedPlugins.count)", icon: "globe"),
        ]
    }

    private var overviewCard: some View {
        GlassCard {
            LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(stats) { item in
                    StatItemView(item: item)
                }
            }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowBackground(Color.clear)
    }

    private var gridColumns: [GridItem] {
        [GridItem(.flexible()), GridItem(.flexible())]
    }
}

// MARK: - Supporting Views

private struct StatItem: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let icon: String
}

private struct StatItemView: View {
    let item: StatItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: item.icon)
                    .font(Typography.caption)
                    .foregroundStyle(AppTheme.accent)
                Text(item.title)
                    .font(Typography.small)
                    .foregroundStyle(.secondary)
            }

            Text(item.value)
                .font(Typography.title)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MoreRow: View {
    let icon: String
    let title: String
    let subtitle: String?
    var tint: Color = AppTheme.accent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(tint, in: .circle)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.headline)

                if let subtitle {
                    Text(subtitle)
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
