// NovelDetailView.swift
// Entry detail screen supporting both library and browse modes.
//
// One view for both kinds: the header, metadata and chapter list are shared,
// and kind-specific sections (manga reader entry, downloads) hang off the same
// `Entry` once the manga reader lands.

import SwiftData
import SwiftUI

struct NovelDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SourceManager.self) private var sourceManager
    @Environment(LibraryManager.self) private var libraryManager

    /// Stored entry, when opened from the library or from a search hit that is
    /// already in the library.
    let entry: Entry?
    /// Source-side entry, when opened from browse/search.
    let sourceEntry: SourceEntry?
    let sourceKey: String

    @Namespace private var chapterTransition
    @State private var localEntry: Entry? = nil
    @State private var details: SourceEntry?
    @State private var sourceChapters: [SourceChapter] = []
    @State private var isLoading = true
    @State private var showFullDescription = false
    @State private var selectedRange: ChapterRange = .progress
    @State private var selectedFilter: ChapterFilter = .all
    @State private var errorMessage: String?

    // Search + navigation state
    @State private var chapterSearch = ""
    @State private var navigateToChapter: ChapterDisplay? = nil
    @State private var allChapters: [ChapterDisplay] = []
    @State private var showAudioDownloads = false

    // MARK: - Initializers

    /// View a saved library entry.
    init(entry: Entry) {
        self.entry = entry
        self.sourceEntry = nil
        self.sourceKey = entry.sourceKey
        self._localEntry = State(initialValue: entry)
    }

    /// View an entry discovered from browse/search.
    init(sourceEntry: SourceEntry) {
        self.entry = nil
        self.sourceEntry = sourceEntry
        self.sourceKey = sourceEntry.sourceKey
        self._localEntry = State(initialValue: nil)
    }

    var body: some View {
        NovelDetailScrollView(
            content: VStack(spacing: 0) {
                NovelHeaderView(
                    transitionNamespace: chapterTransition,
                    name: displayTitle,
                    author: displayAuthor,
                    cover: displayCover,
                    status: localEntry?.status ?? details?.status ?? .unknown,
                    inLibrary: localEntry?.inLibrary ?? false,
                    onToggleLibrary: toggleLibrary,
                    hasStartedReading: hasStartedReading,
                    onContinueReading: continueReading
                )

                if isLoading && localEntry == nil {
                    LoadingView(message: "Loading entry details...")
                        .frame(height: 200)
                } else if let error = errorMessage {
                    EmptyStateView(
                        icon: "exclamationmark.triangle",
                        title: "Error",
                        subtitle: error
                    )
                } else {
                    NovelInfoSection(
                        summary: localEntry?.displaySummary ?? details?.description,
                        genres: displayGenres,
                        author: displayAuthor,
                        artist: localEntry?.displayArtist ?? details?.artist,
                        status: localEntry?.status ?? details?.status ?? .unknown,
                        source: sourceName,
                        showFullDescription: $showFullDescription
                    )
                    .padding(.bottom, 12)

                    Divider()
                        .padding(.horizontal)
                        .padding(.vertical, 16)

                    ChapterListView(
                        entry: localEntry,
                        allChapters: allChapters,
                        chapters: pagedChapters,
                        totalCount: allChapters.count,
                        filteredCount: filteredChapters.count,
                        sourceKey: sourceKey,
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAudioDownloads = true } label: { Image(systemName: "headphones.circle").frame(width: 44, height: 44) }
                    .accessibilityLabel("Manage chapter audio downloads")
            }
        }
        .sheet(isPresented: $showAudioDownloads) {
            BookAudioDownloadsView(
                bookId: TTSBookIdentity.make(pluginId: sourceKey, novelPath: bookPath),
                bookTitle: displayTitle,
                sourceKey: sourceKey,
                entryURL: bookPath,
                chapters: allChapters.map { TTSChapterChoice($0) },
                coverURL: displayCover
            )
        }
        .navigationDestination(item: $navigateToChapter) { chapter in
            ReaderView(
                chapterPath: chapter.path,
                chapterName: chapter.name,
                sourceKey: sourceKey,
                entryURL: localEntry?.url ?? sourceEntry?.url
            )
            .id(chapter.path)
            .bookZoom(from: "continue", in: chapterTransition)
        }
        .onAppear {
            syncLocalEntry()
            refreshChapters()
        }
        .onChange(of: entry) { refreshChapters() }
        .onChange(of: localEntry) { refreshChapters() }
        .task { await fetchDetails() }
    }

    // MARK: - Chapter Computation

    private var bookPath: String {
        localEntry?.url ?? sourceEntry?.url ?? ""
    }

    private func refreshChapters() {
        if let localEntry {
            let entryURL = localEntry.url
            let entrySourceKey = localEntry.sourceKey
            let container = modelContext.container

            Task.detached(priority: .userInitiated) {
                let context = ModelContext(container)
                let predicate = #Predicate<Chapter> {
                    $0.entry?.url == entryURL && $0.entry?.sourceKey == entrySourceKey
                }
                var descriptor = FetchDescriptor<Chapter>(
                    predicate: predicate,
                    sortBy: [SortDescriptor(\.sourceOrder)]
                )
                descriptor.relationshipKeyPathsForPrefetching = []

                do {
                    let fetched = try context.fetch(descriptor)
                    let mapped = fetched.map { ChapterDisplay(chapter: $0) }
                    await MainActor.run { self.allChapters = mapped }
                } catch {
                    print("⚠️ Failed to fetch chapters on background context: \(error)")
                    await MainActor.run {
                        let mapped = localEntry.chapters.map { ChapterDisplay(chapter: $0) }
                        self.allChapters = mapped.sorted { lhs, rhs in
                            if lhs.position != rhs.position { return lhs.position < rhs.position }
                            if let num1 = lhs.chapterNumber, let num2 = rhs.chapterNumber {
                                return num1 < num2
                            }
                            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                        }
                    }
                }
            }
        } else {
            let mapped = sourceChapters.enumerated().map {
                ChapterDisplay(sourceChapter: $1, position: $0, sourceKey: sourceKey, entryURL: sourceEntry?.url)
            }
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
                $0.name.localizedCaseInsensitiveContains(chapterSearch) || String($0.position + 1) == chapterSearch.trimmingCharacters(in: .whitespaces)
            }
        }
        return result
    }

    private var pagedChapters: [ChapterDisplay] {
        let list = filteredChapters
        guard !list.isEmpty else { return [] }

        if !chapterSearch.isEmpty || selectedFilter != .all { return Array(list.prefix(50)) }
        switch selectedRange {
        case .first:
            return Array(list.prefix(10))

        case .last:
            return Array(list.suffix(10))

        case .progress:
            // Find the latest read chapter in the entire book
            let readChapters = allChapters.filter { !$0.unread || $0.isInProgress }
            let targetIndex: Int

            if !readChapters.isEmpty,
               let maxRead = readChapters.max(by: { $0.position < $1.position }) {
                if let idx = list.firstIndex(where: { $0.path == maxRead.path }) {
                    targetIndex = idx
                } else if let idx = list.firstIndex(where: { $0.position >= maxRead.position }) {
                    targetIndex = idx
                } else {
                    targetIndex = list.count - 1
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

    private var displayTitle: String {
        localEntry?.displayTitle ?? details?.title ?? sourceEntry?.title ?? "Unknown"
    }

    private var displayAuthor: String? {
        localEntry?.displayAuthor ?? details?.author ?? sourceEntry?.author
    }

    private var displayCover: String? {
        localEntry?.displayThumbnailURL ?? details?.thumbnailURL ?? sourceEntry?.thumbnailURL
    }

    private var displayGenres: [String] {
        if let local = localEntry, !local.genres.isEmpty { return local.genres }
        if let details, !details.genres.isEmpty { return details.genres }
        return sourceEntry?.genres ?? []
    }

    private var sourceName: String {
        sourceManager.source(forKey: sourceKey)?.name ?? SourceKey.identifier(from: sourceKey)
    }

    private var hasStartedReading: Bool {
        localEntry?.chapters.contains { chapter in
            chapter.read || chapter.progress > 0 || chapter.history != nil
        } ?? false
    }

    // MARK: - Actions

    private func syncLocalEntry() {
        if localEntry == nil {
            let url = entry?.url ?? sourceEntry?.url ?? ""
            guard !url.isEmpty else { return }
            let entrySourceKey = sourceKey
            let predicate = #Predicate<Entry> { $0.url == url && $0.sourceKey == entrySourceKey }
            var descriptor = FetchDescriptor<Entry>(predicate: predicate)
            descriptor.fetchLimit = 1
            if let fetched = try? modelContext.fetch(descriptor).first {
                self.localEntry = fetched
            }
        }
    }

    private func fetchDetails() async {
        syncLocalEntry()
        refreshChapters()

        guard details == nil, let source = sourceManager.novelSource(forKey: sourceKey) else {
            isLoading = false
            return
        }

        let url = localEntry?.url ?? sourceEntry?.url ?? ""
        guard !url.isEmpty else {
            isLoading = false
            return
        }

        do {
            let entry = localEntry.map(Self.sourceEntry(from:))
                ?? sourceEntry
                ?? SourceEntry(sourceKey: sourceKey, kind: .novel, url: url, title: "")
            let fetchedDetails = try await source.details(entry)
            let chapters = try await source.chapters(entry)

            details = fetchedDetails
            sourceChapters = chapters
            if let localEntry {
                libraryManager.applyUpdate(localEntry, details: fetchedDetails, chapters: chapters, context: modelContext)
            }
            isLoading = false
            refreshChapters()
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    /// A stored entry has to be re-expressed as a source value to be refetched.
    private static func sourceEntry(from entry: Entry) -> SourceEntry {
        SourceEntry(
            sourceKey: entry.sourceKey,
            kind: entry.kind,
            url: entry.url,
            title: entry.title,
            thumbnailURL: entry.thumbnailURL,
            author: entry.author,
            artist: entry.artist,
            description: entry.summary,
            genres: entry.genres,
            status: entry.status
        )
    }

    private func toggleLibrary() {
        if let localEntry {
            if localEntry.inLibrary {
                libraryManager.removeFromLibrary(entry: localEntry, context: modelContext)
            } else {
                localEntry.inLibrary = true
                try? modelContext.save()
            }
        } else if let details {
            let added = libraryManager.addToLibrary(
                entry: details,
                chapters: sourceChapters,
                context: modelContext
            )
            localEntry = added
        }
        refreshChapters()
    }

    private func continueReading() {
        guard let localEntry, !localEntry.chapters.isEmpty else {
            if let first = sourceChapters.first {
                navigateToChapter = ChapterDisplay(sourceChapter: first, position: 0, sourceKey: sourceKey)
            }
            return
        }

        let chapters = localEntry.chapters

        // The chapter opened most recently decides where to resume: if it is
        // unfinished, reopen it.
        if let lastOpened = chapters
            .filter({ $0.history != nil })
            .max(by: { ($0.history?.lastRead ?? .distantPast) < ($1.history?.lastRead ?? .distantPast) }),
           !lastOpened.read {
            navigateToChapter = ChapterDisplay(chapter: lastOpened)
            return
        }

        let readChapters = chapters.filter(\.read)
        if let latestRead = readChapters.max(by: { $0.sourceOrder < $1.sourceOrder }) {
            let next = chapters
                .filter { !$0.read && $0.sourceOrder > latestRead.sourceOrder }
                .min { $0.sourceOrder < $1.sourceOrder }
            if let next {
                navigateToChapter = ChapterDisplay(chapter: next)
                return
            }
        }

        let sorted = chapters.sorted { $0.sourceOrder < $1.sourceOrder }
        if let firstUnread = sorted.first(where: { !$0.read }) {
            navigateToChapter = ChapterDisplay(chapter: firstUnread)
            return
        }
        if let last = sorted.last {
            navigateToChapter = ChapterDisplay(chapter: last)
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
