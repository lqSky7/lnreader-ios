// HistoryView.swift
// Reading history screen showing recently read chapters.

import SwiftData
import SwiftUI

struct HistoryView: View {
    @Namespace private var chapterTransitions
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \History.lastRead, order: .reverse)
    private var history: [History]

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
                                ForEach(entries) { item in
                                    if let chapter = item.chapter {
                                        NavigationLink {
                                            ReaderView(
                                                chapterPath: chapter.url,
                                                chapterName: chapter.name,
                                                sourceKey: chapter.entry?.sourceKey ?? "",
                                                entryURL: chapter.entry?.url
                                            )
                                            .id(chapter.url)
                                            .bookZoom(from: item.persistentModelID, in: chapterTransitions)
                                        } label: {
                                            HistoryRow(history: item)
                                                .bookTransitionSource(item.persistentModelID, in: chapterTransitions)
                                        }
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

    // MARK: - Filtering & Grouping

    private var filteredHistory: [History] {
        if searchText.isEmpty { return history }
        return history.filter { item in
            let bookTitle = item.chapter?.entry?.displayTitle ?? ""
            let chapterName = item.chapter?.name ?? ""
            return bookTitle.localizedCaseInsensitiveContains(searchText)
                || chapterName.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var groupedHistory: [(key: String, value: [History])] {
        let grouped = Dictionary(grouping: filteredHistory) { item in
            item.lastRead.formatted
        }
        return grouped.sorted { $0.key > $1.key }
    }

    // MARK: - Actions

    private func deleteEntries(_ offsets: IndexSet, from entries: [History]) {
        for index in offsets {
            modelContext.delete(entries[index])
        }
        try? modelContext.save()
    }

    private func clearAllHistory() {
        for item in history {
            modelContext.delete(item)
        }
        try? modelContext.save()
    }
}
