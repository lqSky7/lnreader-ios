// UpdatesView.swift
// Feed of newly available chapters from library novels.

import SwiftData
import SwiftUI

struct UpdatesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(PluginManager.self) private var pluginManager
    @Environment(LibraryManager.self) private var libraryManager
    @State private var showClearConfirmation = false

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
                    .refreshable {
                        await libraryManager.updateLibrary(context: modelContext, pluginManager: pluginManager)
                    }
                } else {
                    List {
                        ForEach(groupedUpdates, id: \.key) { date, chapters in
                            Section(date) {
                                ForEach(chapters) { chapter in
                                    NavigationLink {
                                        ReaderView(
                                            chapterPath: chapter.path,
                                            chapterName: chapter.name,
                                            pluginId: chapter.novel?.pluginId ?? "",
                                            novel: chapter.novel
                                        )
                                    } label: {
                                        UpdateRow(chapter: chapter)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable {
                        await libraryManager.updateLibrary(context: modelContext, pluginManager: pluginManager)
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
                            await libraryManager.updateLibrary(context: modelContext, pluginManager: pluginManager)
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
            guard let date = chapter.updatedTime else { return "Unknown" }
            return date.formatted
        }
        return grouped.sorted { $0.key > $1.key }
    }
}
