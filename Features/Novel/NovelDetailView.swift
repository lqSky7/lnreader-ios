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
    @Environment(ReaderRouter.self) private var readerRouter

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
    /// A manual refetch is running; the page stays up while it does.
    @State private var isRefetching = false
    @State private var refetchError: String?
    /// When this screen last fetched from the source, for entries with no
    /// stored `lastUpdate` (a browse result).
    @State private var fetchedAt: Date?

    // Search + navigation state
    @State private var chapterSearch = ""
    @State private var navigateToChapter: ChapterDisplay? = nil
    @State private var allChapters: [ChapterDisplay] = []
    /// `allChapters` after scanlator rules and number ordering.
    ///
    /// Kept as state, not a computed property: the sort compares localized
    /// titles and the scanlator pass rebuilds the array, so recomputing it on
    /// every body evaluation meant two full passes over every chapter each time
    /// a chip, a search keystroke, or a scroll tick re-rendered the screen.
    @State private var orderedChapters: [ChapterDisplay] = []
    @State private var showAudioDownloads = false
    /// Hold-to-select state for the chapter list; the bar pins to this screen.
    @State private var chapterSelection = ChapterSelection()
    /// True while the entry is being written to the library.
    @State private var isAddingToLibrary = false
    /// Scanlator priority for this entry, loaded from its own defaults key.
    @State private var scanlatorSettings: ScanlatorSettings

    // MARK: - Initializers

    /// View a saved library entry.
    init(entry: Entry) {
        self.entry = entry
        self.sourceEntry = nil
        self.sourceKey = entry.sourceKey
        self._localEntry = State(initialValue: entry)
        self._scanlatorSettings = State(
            initialValue: ScanlatorSettings(key: "\(entry.sourceKey)::\(entry.url)")
        )
    }

    /// View an entry discovered from browse/search.
    init(sourceEntry: SourceEntry) {
        self.entry = nil
        self.sourceEntry = sourceEntry
        self.sourceKey = sourceEntry.sourceKey
        self._localEntry = State(initialValue: nil)
        self._scanlatorSettings = State(
            initialValue: ScanlatorSettings(key: "\(sourceEntry.sourceKey)::\(sourceEntry.url)")
        )
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
                    isAddingToLibrary: isAddingToLibrary,
                    onToggleLibrary: toggleLibrary,
                    hasStartedReading: hasStartedReading,
                    canStartReading: !allChapters.isEmpty,
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

                    fetchStatusRow

                    ChapterListView(
                        entry: localEntry,
                        allChapters: allChapters,
                        chapters: pagedChapters,
                        totalCount: allChapters.count,
                        filteredCount: filteredChapters.count,
                        showsAllChapters: showsAllChapters,
                        scanlatorSettings: scanlatorSettings,
                        sourceKey: sourceKey,
                        isLoading: isLoading,
                        selection: localEntry == nil ? nil : chapterSelection,
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
        .safeAreaInset(edge: .bottom) {
            if chapterSelection.isActive {
                ChapterSelectionBar(
                    selection: chapterSelection, entry: localEntry,
                    ordered: pagedChapters, allChapters: allChapters, sourceKey: sourceKey)
            }
        }
        .onDisappear { chapterSelection.end() }
        .toolbar(removing: .title)
        .toolbar {
            // Audio is generated from chapter text, which manga don't have.
            if !isManga {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAudioDownloads = true } label: { Image(systemName: "headphones.circle").frame(width: 44, height: 44) }
                        .accessibilityLabel("Manage chapter audio downloads")
                }
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
        // The reader is a full-screen window of its own; this screen only
        // decides which chapter to open.
        .onChange(of: navigateToChapter) { _, chapter in
            guard let chapter else { return }
            openReader(chapter)
            navigateToChapter = nil
        }
        .onAppear {
            syncLocalEntry()
            refreshChapters()
        }
        .onChange(of: entry) { refreshChapters() }
        .onChange(of: localEntry) { refreshChapters() }
        // Scanlator priority changes the merge/hide result, so the ordered list
        // has to be rebuilt — it is no longer a computed property.
        .onChange(of: scanlatorSettings.value) { rebuildOrderedChapters() }
        .task { await fetchDetails() }
        .alert("Couldn't refresh", isPresented: Binding(
            get: { refetchError != nil },
            set: { if !$0 { refetchError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(refetchError ?? "")
        }
    }

    // MARK: - Fetch status

    /// Whether this entry has a source to fetch from (local books do not).
    private var canRefetch: Bool { sourceManager.source(forKey: sourceKey) != nil }

    private var lastFetched: Date? { fetchedAt ?? localEntry?.lastUpdate }

    private var fetchStatusRow: some View {
        HStack(spacing: 8) {
            if let lastFetched {
                Text("Last fetched \(lastFetched.formatted(.relative(presentation: .named)))")
            } else {
                Text("Not fetched yet")
            }
            Spacer()
            if canRefetch {
                Button {
                    Task { await fetchDetails(force: true) }
                } label: {
                    if isRefetching {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(isRefetching)
            }
        }
        .font(Typography.small)
        .foregroundStyle(.secondary)
        .padding(.horizontal)
        .padding(.bottom, 8)
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
                    await MainActor.run {
                        self.allChapters = mapped
                        self.rebuildOrderedChapters()
                    }
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
                        self.rebuildOrderedChapters()
                    }
                }
            }
        } else {
            let kind = localEntry?.kind ?? sourceEntry?.kind ?? .novel
            let mapped = sourceChapters.enumerated().map {
                ChapterDisplay(
                    sourceChapter: $1,
                    position: $0,
                    sourceKey: sourceKey,
                    entryURL: sourceEntry?.url,
                    kind: kind
                )
            }
            self.allChapters = mapped
            rebuildOrderedChapters()
        }
    }

    /// Newest first, ordered by chapter number.
    ///
    /// `sourceOrder` is whatever the source listed — MangaFire hands back
    /// newest-first while most novel sources go oldest-first — so it cannot be
    /// used to sort. The parsed number can.
    private func rebuildOrderedChapters() {
        // Merge and hide by scanlator before ordering, so the list shows what
        // the user actually asked for.
        let base = ScanlatorRules.apply(scanlatorSettings.value, to: allChapters)
        orderedChapters = base.sorted { lhs, rhs in
            if lhs.sortNumber != rhs.sortNumber { return lhs.sortNumber > rhs.sortNumber }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedDescending
        }
    }

    private var filteredChapters: [ChapterDisplay] {
        var result = orderedChapters
        switch selectedFilter {
        case .all: break
        case .unread: result = result.filter { $0.unread }
        case .downloaded: result = result.filter { $0.downloaded }
        case .bookmarked: result = result.filter { $0.bookmarked }
        }
        if !chapterSearch.isEmpty {
            let query = chapterSearch.trimmingCharacters(in: .whitespaces)
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(query)
                    || ($0.chapterNumber.map { String(Int($0)) } == query)
            }
        }
        return result
    }

    /// Manga sources report every chapter at once, so the list shows all of
    /// them. Novels keep the windowed preview: their sources paginate, and a
    /// 2000-chapter web novel should not render 2000 rows on the detail screen.
    private var showsAllChapters: Bool { isManga }

    private var isManga: Bool {
        (localEntry?.kind ?? sourceEntry?.kind ?? .novel) == .manga
    }

    private var pagedChapters: [ChapterDisplay] {
        let list = filteredChapters
        guard !list.isEmpty else { return [] }
        if showsAllChapters { return list }

        if !chapterSearch.isEmpty || selectedFilter != .all { return Array(list.prefix(50)) }
        switch selectedRange {
        case .first:
            // Oldest chapters — the end of a newest-first list.
            return Array(list.suffix(10))

        case .last:
            // Newest chapters.
            return Array(list.prefix(10))

        case .progress:
            let readChapters = allChapters.filter { !$0.unread || $0.isInProgress }
            let targetIndex: Int

            if let maxRead = readChapters.max(by: { $0.sortNumber < $1.sortNumber }) {
                if let idx = list.firstIndex(where: { $0.path == maxRead.path }) {
                    targetIndex = idx
                } else if let idx = list.firstIndex(where: { $0.sortNumber <= maxRead.sortNumber }) {
                    targetIndex = idx
                } else {
                    targetIndex = list.count - 1
                }
            } else {
                // Nothing read yet: start at the oldest chapter.
                targetIndex = list.count - 1
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

    /// Opening an entry never refetches one that already has stored chapters:
    /// the user decides, with Refresh. A fetch happens on its own only when
    /// there is nothing to show yet (a browse result, or a library entry that
    /// was never fetched). `force` is the Refresh button.
    private func fetchDetails(force: Bool = false) async {
        syncLocalEntry()
        refreshChapters()

        if !force, let stored = localEntry, stored.lastUpdate != nil {
            isLoading = false
            return
        }

        // `CatalogSource` covers both kinds: details and the chapter list are
        // shared, only the reader differs.
        guard force || details == nil, let source = sourceManager.source(forKey: sourceKey) else {
            isLoading = false
            return
        }
        if force {
            guard !isRefetching else { return }
            isRefetching = true
        }
        defer { isRefetching = false }

        let url = localEntry?.url ?? sourceEntry?.url ?? ""
        guard !url.isEmpty else {
            isLoading = false
            return
        }

        do {
            let entry = localEntry.map(Self.sourceEntry(from:))
                ?? sourceEntry
                ?? SourceEntry(sourceKey: sourceKey, kind: .novel, url: url, title: "")
            // Two independent requests: run them together so the screen is not
            // waiting on two round trips in series.
            async let pendingDetails = source.details(entry)
            async let pendingChapters = source.chapters(entry)
            let fetchedDetails = try await pendingDetails
            let chapters = try await pendingChapters

            details = fetchedDetails
            sourceChapters = chapters
            fetchedAt = .now
            if let localEntry {
                libraryManager.applyUpdate(localEntry, details: fetchedDetails, chapters: chapters, context: modelContext)
            }
            isLoading = false
            refreshChapters()
        } catch {
            if force {
                refetchError = error.localizedDescription
            } else {
                errorMessage = error.localizedDescription
            }
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
        guard !isAddingToLibrary else { return }

        // Removing is local and instant.
        if let localEntry, localEntry.inLibrary {
            libraryManager.removeFromLibrary(entry: localEntry, context: modelContext)
            refreshChapters()
            return
        }

        // Adding has to work the moment the screen opens, not only after the
        // details request lands. A browse result already carries everything the
        // library row needs, so seed from it and let `fetchDetails` merge the
        // chapter list when it arrives.
        let seed: SourceEntry? = localEntry.map(Self.sourceEntry(from:)) ?? details ?? sourceEntry
        guard let seed else { return }

        isAddingToLibrary = true
        Task { @MainActor in
            let added = libraryManager.addToLibrary(
                entry: seed,
                chapters: sourceChapters,
                context: modelContext
            )
            localEntry = added
            isAddingToLibrary = false
            refreshChapters()
        }
    }

    private func openReader(_ chapter: ChapterDisplay) {
        readerRouter.open(
            chapter,
            sourceKey: sourceKey,
            entryURL: localEntry?.url ?? sourceEntry?.url,
            kind: localEntry?.kind ?? sourceEntry?.kind ?? .novel
        )
    }

    private func continueReading() {
        guard let localEntry, !localEntry.chapters.isEmpty else {
            if let first = sourceChapters.first {
                navigateToChapter = ChapterDisplay(
                    sourceChapter: first,
                    position: 0,
                    sourceKey: sourceKey,
                    kind: sourceEntry?.kind ?? .novel
                )
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
