// UpdatesView.swift
// Feed of newly available chapters from library entries.

import SwiftData
import SwiftUI

struct UpdatesView: View {
    @Environment(ReaderRouter.self) private var readerRouter
    @Namespace private var chapterTransitions
    @Environment(\.modelContext) private var modelContext
    @Environment(SourceManager.self) private var sourceManager
    @Environment(LibraryManager.self) private var libraryManager
    @State private var showClearConfirmation = false

    @Query(
        filter: #Predicate<Chapter> { $0.dateFetch != nil },
        sort: \Chapter.dateFetch,
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
                        subtitle: "New chapters from your library will appear here."
                    )
                    .refreshable {
                        await libraryManager.updateLibrary(context: modelContext, sourceManager: sourceManager)
                    }
                } else {
                    List {
                        ForEach(groupedUpdates, id: \.key) { date, chapters in
                            Section(date) {
                                ForEach(chapters) { chapter in
                                    Button {
                                        readerRouter.open(
                                            sourceKey: chapter.entry?.sourceKey ?? "",
                                            entryURL: chapter.entry?.url,
                                            kind: chapter.entry?.kind ?? .novel,
                                            chapterURL: chapter.url,
                                            chapterName: chapter.name
                                        )
                                    } label: {
                                        UpdateRow(chapter: chapter)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable {
                        await libraryManager.updateLibrary(context: modelContext, sourceManager: sourceManager)
                    }
                }
            }
            .navigationTitle("Updates")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if !recentChapters.isEmpty {
                        Button(role: .destructive) {
                            showClearConfirmation = true
                        } label: {
                            Label("Clear Updates", systemImage: "trash")
                        }
                    }

                    Button(action: {
                        Task {
                            await libraryManager.updateLibrary(context: modelContext, sourceManager: sourceManager)
                        }
                    }) {
                        if libraryManager.isUpdating {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(libraryManager.isUpdating)
                }
            }
            .confirmationDialog(
                "Are you sure you want to clear all updates?",
                isPresented: $showClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear All", role: .destructive) {
                    libraryManager.clearUpdates(context: modelContext)
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    // MARK: - Grouping

    /// Group chapters by their update date (formatted as relative date).
    private var groupedUpdates: [(key: String, value: [Chapter])] {
        let grouped = Dictionary(grouping: recentChapters) { chapter -> String in
            guard let date = chapter.dateFetch else { return "Unknown" }
            return date.formatted
        }
        return grouped.sorted { $0.key > $1.key }
    }
}
