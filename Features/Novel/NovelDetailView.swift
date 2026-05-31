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

    @State private var localNovel: Novel? = nil
    @State private var sourceNovel: SourceNovel?
    @State private var isLoading = true
    @State private var showFullDescription = false
    @State private var selectedRange: ChapterRange = .progress
    @State private var selectedFilter: ChapterFilter = .all
    @State private var errorMessage: String?

    // Search + navigation state
    @State private var chapterSearch = ""
    @State private var navigateToChapter: ChapterDisplay? = nil
    @State private var allChapters: [ChapterDisplay] = []

    // MARK: - Initializers

    /// View a saved library novel.
    init(novel: Novel) {
        self.novel = novel
        self.partialNovel = nil
        self.pluginId = novel.pluginId
        self._localNovel = State(initialValue: novel)
    }

    /// View a novel discovered from browse/search.
    init(partialNovel: PartialNovel, pluginId: String) {
        self.novel = nil
        self.partialNovel = partialNovel
        self.pluginId = pluginId
        self._localNovel = State(initialValue: nil)
    }

    var body: some View {
        NovelDetailScrollView(
            content: VStack(spacing: 0) {
                NovelHeaderView(
                    name: displayName,
                    author: displayAuthor,
                    cover: displayCover,
                    status: localNovel?.status ?? statusFromSource,
                    inLibrary: localNovel?.inLibrary ?? false,
                    onToggleLibrary: toggleLibrary,
                    onContinueReading: continueReading
                )

                if isLoading && localNovel == nil {
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
                        summary: localNovel?.summary ?? sourceNovel?.summary,
                        genres: displayGenres,
                        author: displayAuthor,
                        artist: localNovel?.artist ?? sourceNovel?.artist,
                        status: localNovel?.status ?? statusFromSource,
                        source: pluginManager.pluginName(for: pluginId),
                        showFullDescription: $showFullDescription
                    )

                    Divider().padding(.horizontal)

                    ChapterListView(
                        novel: localNovel,
                        chapters: pagedChapters,
                        totalCount: allChapters.count,
                        filteredCount: filteredChapters.count,
                        pluginId: pluginId,
                        selectedRange: $selectedRange,
                        selectedFilter: $selectedFilter,
                        searchText: $chapterSearch
                    )
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                hideKeyboard()
            }
        )
        .toolbar(removing: .title)
        .navigationDestination(item: $navigateToChapter) { chapter in
            ReaderView(
                chapterPath: chapter.path,
                chapterName: chapter.name,
                pluginId: pluginId,
                novelPath: localNovel?.path
            )
            .id(chapter.path)
        }
        .onAppear {
            syncLocalNovel()
            refreshChapters()
        }
        .onChange(of: novel) { refreshChapters() }
        .onChange(of: localNovel) { refreshChapters() }
        .task { await fetchNovelData() }
    }

    // MARK: - Chapter Computation

    private func refreshChapters() {
        if let localNovel {
            let novelPath = localNovel.path
            let pluginId = localNovel.pluginId
            let container = modelContext.container
            
            Task.detached(priority: .userInitiated) {
                let context = ModelContext(container)
                let predicate = #Predicate<Chapter> { $0.novel?.path == novelPath && $0.novel?.pluginId == pluginId }
                var descriptor = FetchDescriptor<Chapter>(
                    predicate: predicate,
                    sortBy: [SortDescriptor(\.position)]
                )
                descriptor.relationshipKeyPathsForPrefetching = []
                
                do {
                    let fetchedChapters = try context.fetch(descriptor)
                    let mapped = fetchedChapters.map { ChapterDisplay(chapter: $0) }
                    
                    await MainActor.run {
                        self.allChapters = mapped
                    }
                } catch {
                    print("⚠️ Failed to fetch chapters on background context: \(error)")
                    await MainActor.run {
                        let mapped = localNovel.chapters.map { ChapterDisplay(chapter: $0) }
                        let sorted = mapped.sorted { ch1, ch2 in
                            if ch1.position != ch2.position {
                                return ch1.position < ch2.position
                            }
                            if let num1 = ch1.chapterNumber, let num2 = ch2.chapterNumber {
                                return num1 < num2
                            }
                            return ch1.name.localizedStandardCompare(ch2.name) == .orderedAscending
                        }
                        self.allChapters = sorted
                    }
                }
            }
        } else {
            let sourceChapters = sourceNovel?.chapters ?? []
            let mapped = sourceChapters.enumerated().map { ChapterDisplay(sourceChapter: $1, position: $0) }
            self.allChapters = mapped
        }
    }

    private var filteredChapters: [ChapterDisplay] {
        var result = allChapters
        switch selectedFilter {
        case .all: break
        case .unread: result = result.filter { $0.unread }
        case .downloaded: result = result.filter { $0.downloaded }
        case .bookmarked: result = result.filter { $0.bookmarked }
        }
        if !chapterSearch.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(chapterSearch)
            }
        }
        return result
    }

    private var pagedChapters: [ChapterDisplay] {
        let list = filteredChapters
        guard !list.isEmpty else { return [] }
        
        switch selectedRange {
        case .first:
            return Array(list.prefix(10))
            
        case .last:
            return Array(list.suffix(10))
            
        case .progress:
            // Find the latest read chapter in the entire book
            let readChapterPaths = allChapters.filter { !$0.unread }
            let targetIndex: Int
            
            if !readChapterPaths.isEmpty,
               let maxRead = readChapterPaths.max(by: { $0.position < $1.position }) {
                // Find where it is in the filtered list
                if let idx = list.firstIndex(where: { $0.path == maxRead.path }) {
                    targetIndex = idx
                } else {
                    // Fallback: first chapter in filtered list with position >= maxRead.position
                    if let idx = list.firstIndex(where: { $0.position >= maxRead.position }) {
                        targetIndex = idx
                    } else {
                        targetIndex = list.count - 1
                    }
                }
            } else {
                targetIndex = 0
            }
            
            let totalCount = list.count
            let sliceSize = 11
            let halfSize = 5
            
            var start = targetIndex - halfSize
            var end = targetIndex + halfSize
            
            if start < 0 {
                start = 0
                end = min(sliceSize - 1, totalCount - 1)
            }
            if end >= totalCount {
                end = totalCount - 1
                start = max(0, end - sliceSize + 1)
            }
            
            return Array(list[start...end])
        }
    }

    // MARK: - Display Helpers

    private var displayName: String {
        localNovel?.name ?? partialNovel?.name ?? sourceNovel?.name ?? "Unknown"
    }

    private var displayAuthor: String? {
        localNovel?.author ?? sourceNovel?.author
    }

    private var displayCover: String? {
        localNovel?.cover ?? partialNovel?.cover ?? sourceNovel?.cover
    }

    private var displayGenres: [String] {
        let raw = localNovel?.genres ?? sourceNovel?.genres
        return raw?.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty } ?? []
    }

    private var statusFromSource: NovelStatus {
        NovelStatus(rawValue: sourceNovel?.status ?? "") ?? .unknown
    }

    // MARK: - Actions

    private func syncLocalNovel() {
        if localNovel == nil {
            let path = novel?.path ?? partialNovel?.path ?? ""
            guard !path.isEmpty else { return }
            let predicate = #Predicate<Novel> { $0.path == path && $0.pluginId == pluginId }
            var descriptor = FetchDescriptor<Novel>(predicate: predicate)
            descriptor.fetchLimit = 1
            if let fetched = try? modelContext.fetch(descriptor).first {
                self.localNovel = fetched
            }
        }
    }

    private func fetchNovelData() async {
        syncLocalNovel()
        refreshChapters()
        
        guard sourceNovel == nil else { return }
        let path = localNovel?.path ?? partialNovel?.path ?? ""
        guard !path.isEmpty,
            let source = pluginManager.plugin(for: pluginId)
        else {
            isLoading = false
            return
        }

        do {
            var parsed = try await source.parseNovel(path: path)
            print("📖 [\(pluginId)] parseNovel returned: chapters=\(parsed.chapters.count), totalPages=\(parsed.totalPages ?? -1), hasParsePage=\(source.hasParsePage)")
            if source.hasParsePage, let totalPages = parsed.totalPages, totalPages > 1 {
                print("📖 [\(pluginId)] Paginated chapters detected, fetching \(totalPages) pages...")
                let allChapters = try await source.fetchAllChapters(path: path, totalPages: totalPages)
                print("📖 [\(pluginId)] fetchAllChapters returned \(allChapters.count) total chapters")
                parsed = SourceNovel(
                    name: parsed.name,
                    path: parsed.path,
                    cover: parsed.cover,
                    genres: parsed.genres,
                    summary: parsed.summary,
                    author: parsed.author,
                    artist: parsed.artist,
                    status: parsed.status,
                    chapters: allChapters,
                    totalPages: parsed.totalPages
                )
            } else {
                print("📖 [\(pluginId)] NOT fetching all pages. hasParsePage=\(source.hasParsePage), totalPages=\(parsed.totalPages ?? -1)")
            }
            sourceNovel = parsed
            if let localNovel {
                libraryManager.updateNovel(localNovel, sourceNovel: parsed, context: modelContext)
            }
            isLoading = false
            refreshChapters()
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func toggleLibrary() {
        if let localNovel {
            if localNovel.inLibrary {
                libraryManager.removeFromLibrary(novel: localNovel, context: modelContext)
            } else {
                localNovel.inLibrary = true
                try? modelContext.save()
            }
        } else if let sourceNovel {
            libraryManager.addToLibrary(
                sourceNovel: sourceNovel,
                pluginId: pluginId,
                context: modelContext
            )
            syncLocalNovel()
        }
        refreshChapters()
    }

    private func continueReading() {
        if let localNovel, !localNovel.chapters.isEmpty {
            let chapters = localNovel.chapters
            let readChapters = chapters.filter { !$0.unread }
            
            if !readChapters.isEmpty {
                // Find the latest read chapter based on readTime (or fallback to position if no readTime is set)
                let latestRead: Chapter? = {
                    let chaptersWithTime = readChapters.filter { $0.readTime != nil }
                    if !chaptersWithTime.isEmpty {
                        return chaptersWithTime.max(by: { ($0.readTime ?? .distantPast) < ($1.readTime ?? .distantPast) })
                    } else {
                        return readChapters.max(by: { $0.position < $1.position })
                    }
                }()
                
                if let latestRead {
                    let unreadAfterLatest = chapters
                        .filter { $0.unread && $0.position > latestRead.position }
                        .sorted { $0.position < $1.position }
                    
                    if let nextChapter = unreadAfterLatest.first {
                        navigateToChapter = ChapterDisplay(chapter: nextChapter)
                        return
                    }
                }
            }
            
            // Fallback: if no chapters are read, or no unread chapters exist after the latest read, open the first unread chapter
            let sorted = chapters.sorted { $0.position < $1.position }
            if let firstUnread = sorted.first(where: { $0.unread }) {
                navigateToChapter = ChapterDisplay(chapter: firstUnread)
                return
            }
            if let last = sorted.last {
                navigateToChapter = ChapterDisplay(chapter: last)
                return
            }
        } else if let sourceNovel, !sourceNovel.chapters.isEmpty {
            let chapters = sourceNovel.chapters
            if let first = chapters.first {
                navigateToChapter = ChapterDisplay(sourceChapter: first, position: 0)
            }
        }
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

/// Range options for the chapter list.
enum ChapterRange: String, CaseIterable, Identifiable {
    case progress = "Current Progress"
    case first = "First 10 Chapters"
    case last = "Last 10 Chapters"

    var id: String { rawValue }
}

/// A performance-optimized ScrollView wrapper that isolates scroll offset tracking
struct NovelDetailScrollView<Content: View>: View {
    let content: Content

    var body: some View {
        ScrollView {
            content
        }
        .ignoresSafeArea(edges: .top)
        .scrollDismissesKeyboard(.immediately)
    }
}
