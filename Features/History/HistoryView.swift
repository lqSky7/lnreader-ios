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

    /// Changes when the History tab is tapped again; opens the most recent chapter.
    var resumeTrigger = 0

    @State private var searchText = ""
    @State private var path = NavigationPath()
    @State private var showClearConfirmation = false

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if filteredHistory.isEmpty, !searchText.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else if filteredHistory.isEmpty {
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
                                        HistoryRow(
                                            history: item,
                                            onOpenEntry: {
                                                if let entry = chapter.entry { path.append(entry) }
                                            },
                                            onOpenChapter: {
                                                readerRouter.open(
                                                    sourceKey: chapter.entry?.sourceKey ?? "",
                                                    entryURL: chapter.entry?.url,
                                                    kind: chapter.entry?.kind ?? .novel,
                                                    chapterURL: chapter.url,
                                                    chapterName: chapter.name
                                                )
                                            }
                                        )
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
            .navigationDestination(for: Entry.self) { entry in
                NovelDetailView(entry: entry)
            }
            .navigationTitle("History")
            .onChange(of: resumeTrigger) { resumeLatest() }
            .searchable(text: $searchText, prompt: "Search history")
            .toolbar {
                if !history.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button(role: .destructive) {
                            showClearConfirmation = true
                        } label: {
                            Label("Clear History", systemImage: "trash")
                        }
                        .confirmationDialog(
                            "Clear all reading history?",
                            isPresented: $showClearConfirmation,
                            titleVisibility: .visible
                        ) {
                            Button("Clear History", role: .destructive, action: clearAllHistory)
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("This removes every entry from History. Your reading progress is kept.")
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
        let calendar = Calendar.current
        var buckets: [Date: [History]] = [:]
        for item in filteredHistory {
            buckets[calendar.startOfDay(for: item.lastRead), default: []].append(item)
        }
        return buckets.keys.sorted(by: >).map { day in
            (day.daySectionTitle, buckets[day] ?? [])
        }
    }

    // MARK: - Actions

    private func resumeLatest() {
        guard path.isEmpty, readerRouter.request == nil,
              let chapter = history.first(where: { $0.chapter != nil })?.chapter else { return }
        readerRouter.open(
            sourceKey: chapter.entry?.sourceKey ?? "",
            entryURL: chapter.entry?.url,
            kind: chapter.entry?.kind ?? .novel,
            chapterURL: chapter.url,
            chapterName: chapter.name
        )
    }

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
