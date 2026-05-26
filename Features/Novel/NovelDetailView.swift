// NovelDetailView.swift
// Novel detail screen supporting both library and browse modes.

import SwiftData
import SwiftUI

struct NovelDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(PluginManager.self) private var pluginManager
    @Environment(LibraryManager.self) private var libraryManager

    let novel: Novel?
    let partialNovel: PartialNovel?
    let pluginId: String

    @State private var sourceNovel: SourceNovel?
    @State private var isLoading = true
    @State private var showFullDescription = false
    @State private var chapterSortAscending = false
    @State private var selectedFilter: ChapterFilter = .all
    @State private var errorMessage: String?

    // MARK: - Initializers

    /// View a saved library novel.
    init(novel: Novel) {
        self.novel = novel
        self.partialNovel = nil
        self.pluginId = novel.pluginId
    }

    /// View a novel discovered from browse/search.
    init(partialNovel: PartialNovel, pluginId: String) {
        self.novel = nil
        self.partialNovel = partialNovel
        self.pluginId = pluginId
    }

    var body: some View {
        ScrollView {
            NovelHeaderView(
                name: displayName,
                author: displayAuthor,
                cover: displayCover,
                status: novel?.status ?? statusFromSource,
                inLibrary: novel?.inLibrary ?? false,
                onToggleLibrary: toggleLibrary,
                onContinueReading: continueReading
            )

            if isLoading && novel == nil {
                LoadingView(message: "Loading novel details...")
                    .frame(height: 200)
            } else if let error = errorMessage {
                EmptyStateView(
                    icon: "exclamationmark.triangle",
                    title: "Error",
                    subtitle: error
                )
            } else {
                NovelInfoSection(
                    summary: novel?.summary ?? sourceNovel?.summary,
                    genres: displayGenres,
                    author: displayAuthor,
                    artist: novel?.artist ?? sourceNovel?.artist,
                    status: novel?.status ?? statusFromSource,
                    source: pluginManager.pluginName(for: pluginId),
                    showFullDescription: $showFullDescription
                )

                Divider().padding(.horizontal)

                ChapterListView(
                    novel: novel,
                    sourceChapters: sourceNovel?.chapters ?? [],
                    pluginId: pluginId,
                    sortAscending: $chapterSortAscending,
                    selectedFilter: $selectedFilter
                )
            }
        }
        .ignoresSafeArea(edges: .top)
        .toolbar(removing: .title)
        .task { await fetchNovelData() }
    }

    // MARK: - Display Helpers

    private var displayName: String {
        novel?.name ?? partialNovel?.name ?? sourceNovel?.name ?? "Unknown"
    }

    private var displayAuthor: String? {
        novel?.author ?? sourceNovel?.author
    }

    private var displayCover: String? {
        novel?.cover ?? partialNovel?.cover ?? sourceNovel?.cover
    }

    private var displayGenres: [String] {
        let raw = novel?.genres ?? sourceNovel?.genres
        return raw?.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty } ?? []
    }

    private var statusFromSource: NovelStatus {
        NovelStatus(rawValue: sourceNovel?.status ?? "") ?? .unknown
    }

    // MARK: - Actions

    private func fetchNovelData() async {
        guard sourceNovel == nil else { return }
        let path = novel?.path ?? partialNovel?.path ?? ""
        guard !path.isEmpty,
              let source = pluginManager.plugin(for: pluginId) else {
            isLoading = false
            return
        }

        do {
            sourceNovel = try await source.parseNovel(path: path)
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func toggleLibrary() {
        if let novel {
            if novel.inLibrary {
                libraryManager.removeFromLibrary(novel: novel, context: modelContext)
            } else {
                novel.inLibrary = true
                try? modelContext.save()
            }
        } else if let sourceNovel {
            libraryManager.addToLibrary(
                sourceNovel: sourceNovel,
                pluginId: pluginId,
                context: modelContext
            )
        }
    }

    private func continueReading() {
        // TODO: Navigate to last-read or first unread chapter
    }
}

/// Filter options for the chapter list.
enum ChapterFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case unread = "Unread"
    case downloaded = "Downloaded"
    case bookmarked = "Bookmarked"

    var id: String { rawValue }
}
