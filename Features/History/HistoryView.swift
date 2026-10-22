// HistoryView.swift
// Reading history screen showing recently read chapters.

import SwiftData
import SwiftUI

struct HistoryView: View {
    @Environment(ReaderRouter.self) private var readerRouter
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
                                        Button {
                                            readerRouter.open(
                                                sourceKey: chapter.entry?.sourceKey ?? "",
                                                entryURL: chapter.entry?.url,
                                                kind: chapter.entry?.kind ?? .novel,
                                                chapterURL: chapter.url,
                                                chapterName: chapter.name
                                            )
                                        } label: {
                                            HistoryRow(history: item)
                                                .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
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

    /// One formatter for the whole screen. `Date.formatted` builds a format
    /// style per call, and grouping by the fully formatted string put every row
    /// in a section of its own.
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

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
        let calendar = Calendar.current
        var buckets: [Date: [History]] = [:]
        for item in filteredHistory {
            buckets[calendar.startOfDay(for: item.lastRead), default: []].append(item)
        }
        return buckets.keys.sorted(by: >).map { day in
            (Self.dayFormatter.string(from: day), buckets[day] ?? [])
        }
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
