// UpdatesView.swift
// Feed of newly available chapters from library novels.

import SwiftData
import SwiftUI

struct UpdatesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<Chapter> { $0.updatedTime != nil },
        sort: \Chapter.updatedTime,
        order: .reverse
    )
    private var recentChapters: [Chapter]

    var body: some View {
        NavigationStack {
            Group {
                if recentChapters.isEmpty {
                    EmptyStateView(
                        icon: "bell.badge",
                        title: "No Updates",
                        subtitle: "New chapters from your library novels will appear here."
                    )
                } else {
                    List {
                        ForEach(groupedUpdates, id: \.key) { date, chapters in
                            Section(date) {
                                ForEach(chapters) { chapter in
                                    UpdateRow(chapter: chapter)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Updates")
        }
    }

    // MARK: - Grouping

    /// Group chapters by their update date (formatted as relative date).
    private var groupedUpdates: [(key: String, value: [Chapter])] {
        let grouped = Dictionary(grouping: recentChapters) { chapter -> String in
            guard let date = chapter.updatedTime else { return "Unknown" }
            return date.formatted
        }
        return grouped.sorted { $0.key > $1.key }
    }
}
