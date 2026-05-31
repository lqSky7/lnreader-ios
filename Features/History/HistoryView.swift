// HistoryView.swift
// Reading history screen showing recently read chapters.

import SwiftData
import SwiftUI

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ReadingHistory.lastReadAt, order: .reverse)
    private var history: [ReadingHistory]
    @Query private var novels: [Novel]

    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            Group {
                if filteredHistory.isEmpty {
                    EmptyStateView(
                        icon: "clock",
                        title: "No Reading History",
                        subtitle: "Chapters you read will appear here."
                    )
                } else {
                    List {
                        ForEach(groupedHistory, id: \.key) { date, entries in
                            Section(date) {
                                ForEach(entries) { entry in
                                    NavigationLink {
                                        ReaderView(
                                            chapterPath: entry.chapterPath,
                                            chapterName: entry.chapterName,
                                            pluginId: entry.pluginId,
                                            novelPath: entry.novelPath
                                        )
                                        .id(entry.chapterPath)
                                    } label: {
                                        HistoryRow(entry: entry)
                                    }
                                }
                                .onDelete { offsets in
                                    deleteEntries(offsets, from: entries)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("History")
            .searchable(text: $searchText, prompt: "Search history")
            .toolbar {
                if !history.isEmpty {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Clear All", role: .destructive) {
                            clearAllHistory()
                        }
                    }
                }
            }
        }
    }

    private func novel(for entry: ReadingHistory) -> Novel? {
        novels.first { $0.path == entry.novelPath && $0.pluginId == entry.pluginId }
    }

    // MARK: - Filtering & Grouping

    private var filteredHistory: [ReadingHistory] {
        if searchText.isEmpty { return history }
        return history.filter {
            $0.novelName.localizedCaseInsensitiveContains(searchText)
            || $0.chapterName.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var groupedHistory: [(key: String, value: [ReadingHistory])] {
        let grouped = Dictionary(grouping: filteredHistory) { entry in
            entry.lastReadAt.formatted
        }
        return grouped.sorted { $0.key > $1.key }
    }

    // MARK: - Actions

    private func deleteEntries(_ offsets: IndexSet, from entries: [ReadingHistory]) {
        for index in offsets {
            modelContext.delete(entries[index])
        }
        try? modelContext.save()
    }

    private func clearAllHistory() {
        for entry in history {
            modelContext.delete(entry)
        }
        try? modelContext.save()
    }
}
