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

    @Query private var recentChapters: [Chapter]

    /// Newest-first, capped: grouping and diffing every chapter ever fetched
    /// froze the main thread for over a second on a large library.
    private static let feedLimit = 300

    init() {
        var descriptor = FetchDescriptor<Chapter>(
            predicate: #Predicate { $0.dateFetch != nil },
            sortBy: [SortDescriptor(\Chapter.dateFetch, order: .reverse)]
        )
        descriptor.fetchLimit = Self.feedLimit
        _recentChapters = Query(descriptor)
    }

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
                        // The updates modal shows progress; release the pull indicator.
                        let context = modelContext, sources = sourceManager
                        Task { await libraryManager.updateLibrary(context: context, sourceManager: sources) }
                        try? await Task.sleep(for: .seconds(1.5))
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
                        // The updates modal shows progress; release the pull indicator.
                        let context = modelContext, sources = sourceManager
                        Task { await libraryManager.updateLibrary(context: context, sourceManager: sources) }
                        try? await Task.sleep(for: .seconds(1.5))
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
            // Owned by the screen, not the toolbar button: a dialog attached
            // inside a toolbar item does not reliably present, which is why the
            // trash button appeared to do nothing.
            .confirmationDialog(
                "Are you sure you want to clear all updates?",
                isPresented: $showClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear All", role: .destructive) {
                    Task { await libraryManager.clearUpdates(context: modelContext) }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    // MARK: - Grouping

    /// Group chapters by the day they were fetched.
    private var groupedUpdates: [(key: String, value: [Chapter])] {
        let calendar = Calendar.current
        var buckets: [Date: [Chapter]] = [:]
        var undated: [Chapter] = []
        for chapter in recentChapters {
            guard let date = chapter.dateFetch else {
                undated.append(chapter)
                continue
            }
            buckets[calendar.startOfDay(for: date), default: []].append(chapter)
        }
        var groups = buckets.keys.sorted(by: >).map { day in
            (day.daySectionTitle, buckets[day] ?? [])
        }
        if !undated.isEmpty {
            groups.append(("Unknown", undated))
        }
        return groups
    }
}
