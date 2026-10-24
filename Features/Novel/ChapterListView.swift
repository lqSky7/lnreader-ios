// ChapterListView.swift
// Sortable, filterable chapter list. Pagination and filtering are driven
// from the parent (NovelDetailView); this view only renders what it receives.

import SwiftUI

struct ChapterListView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let entry: Entry?
    var allChapters: [ChapterDisplay] = []
    let chapters: [ChapterDisplay]
    let totalCount: Int
    let filteredCount: Int
    /// Manga sources hand over the whole chapter list at once, so there is
    /// nothing to page through — show all of it.
    var showsAllChapters = false
    /// Per-entry scanlator priority, when the parent owns one.
    var scanlatorSettings: ScanlatorSettings? = nil
    let sourceKey: String
    /// The chapter list is still being fetched. Without this the screen said
    /// "No chapters yet" while the request was in flight.
    var isLoading: Bool = false
    /// Hold-to-select state, owned by the screen so its action bar can pin.
    var selection: ChapterSelection? = nil
    @Binding var selectedRange: ChapterRange
    @Binding var selectedFilter: ChapterFilter
    @Binding var searchText: String
    @AppStorage("chapters.ascending") private var ascending = false
    @State private var showSearchField = false
    @State private var showDirectory = false
    @State private var showScanlators = false
    @FocusState private var searchFocused: Bool

    /// The whole list in the chosen order, built when the directory opens.
    private var directoryChapters: [ChapterDisplay] {
        let all = allChapters.isEmpty ? chapters : allChapters
        return all.sorted { ascending ? $0.sortNumber < $1.sortNumber : $0.sortNumber > $1.sortNumber }
    }

    private var isFiltered: Bool { selectedFilter != .all || !searchText.isEmpty }
    private var rangeDescription: String {
        if showsAllChapters { return "\(totalCount) chapters" }
        guard let first = chapters.first, let last = chapters.last else { return "No chapters" }
        return "\(first.position + 1)–\(last.position + 1) of \(totalCount)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Chapters").font(Typography.title)
                    Text(isFiltered ? "\(filteredCount) matching chapters" : rangeDescription)
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    withAnimation(AppMotion.gentle(reduceMotion: reduceMotion)) {
                        showSearchField.toggle()
                        if !showSearchField { searchText = "" }
                    }
                    searchFocused = showSearchField
                } label: {
                    Image(systemName: showSearchField ? "xmark" : "magnifyingglass").frame(width: 40, height: 40)
                }.buttonStyle(.glass).accessibilityLabel(showSearchField ? "Close chapter search" : "Search chapters")
                Menu {
                    Picker("Order", selection: $ascending) {
                        Label("Newest first", systemImage: "arrow.down").tag(false)
                        Label("Oldest first", systemImage: "arrow.up").tag(true)
                    }
                    Picker("Filter chapters", selection: $selectedFilter) {
                        ForEach(ChapterFilter.allCases) { Text($0.rawValue).tag($0) }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                        .foregroundStyle(selectedFilter == .all ? Color.primary : Color.accentColor)
                        .frame(width: 40, height: 40)
                }.buttonStyle(.glass).accessibilityLabel("Sort and filter chapters")

                if let scanlatorSettings {
                    Button {
                        showScanlators = true
                    } label: {
                        Image(systemName: scanlatorSettings.hasActiveRules ? "person.2.fill" : "person.2")
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("Scanlator priority")
                }
            }
            .padding(.top, 8)

            if showSearchField {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Chapter name or number", text: $searchText)
                        .textFieldStyle(.plain).autocorrectionDisabled().focused($searchFocused)
                }
                .padding(12).background(.quaternary, in: .rect(cornerRadius: 14))
                .transition(.opacity.combined(with: .offset(y: -4)))
            }

            if !isFiltered && !showsAllChapters {
                Picker("Chapter range", selection: $selectedRange) {
                    Text("Continue").tag(ChapterRange.progress)
                    Text("First").tag(ChapterRange.first)
                    Text("Latest").tag(ChapterRange.last)
                }.pickerStyle(.segmented)
            }

            if chapters.isEmpty && isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Loading chapters…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 88)
                .background(AppTheme.cardBackground, in: .rect(cornerRadius: 18))
            } else if chapters.isEmpty {
                ContentUnavailableView(isFiltered ? "No matching chapters" : "No chapters yet", systemImage: "text.magnifyingglass")
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(chapters) { chapter in
                        ChapterRow(chapter: chapter, entry: entry, sourceKey: sourceKey,
                                   selection: selection, orderedPaths: { chapters.map(\.path) })
                            .padding(.horizontal, 12)
                        if chapter.id != chapters.last?.id { Divider().padding(.leading, 34) }
                    }
                }
                .background(AppTheme.cardBackground, in: .rect(cornerRadius: 18))
            }

            if !showsAllChapters {
                Button { showDirectory = true } label: {
                    HStack {
                        Label(isFiltered && filteredCount > chapters.count ? "See all \(filteredCount) results" : "All \(totalCount) chapters", systemImage: "list.bullet.rectangle")
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    }.font(.subheadline.weight(.medium)).padding(.vertical, 12)
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
        .animation(AppMotion.gentle(reduceMotion: reduceMotion), value: showSearchField)
        .sheet(isPresented: $showDirectory) {
            ChapterDirectoryView(entry: entry, chapters: directoryChapters,
                sourceKey: sourceKey, currentChapterPath: chapters.first(where: { $0.unread })?.path ?? chapters.first?.path,
                initialSearch: searchText, initialFilter: selectedFilter)
        }
        .onAppear { showSearchField = !searchText.isEmpty }
        .sheet(isPresented: $showScanlators) {
            if let scanlatorSettings {
                ScanlatorSettingsView(
                    settings: scanlatorSettings,
                    scanlators: Set(allChapters.isEmpty ? chapters : allChapters)
                        .compactMap(\.scanlator)
                        .filter { !$0.isEmpty }
                        .sorted()
                )
            }
        }
    }
}

// MARK: - Unified Chapter Display

/// Bridges a stored chapter and a source chapter into a single displayable type.
///
/// The two sources of chapters differ (SwiftData rows carry read state, source
/// rows do not), so the list only ever renders this value.
struct ChapterDisplay: Identifiable, Hashable {
    let id: String
    let name: String
    let path: String
    /// Release date, formatted on demand.
    ///
    /// It used to be a `String` formatted inside the initializer, which meant
    /// building and running a date formatter for every chapter in the book —
    /// thousands of them — to display ten rows.
    let releaseDate: Date?
    let unread: Bool
    let bookmarked: Bool
    let downloaded: Bool
    let progress: Int?
    let isInProgress: Bool
    let position: Int
    let chapterNumber: Double?
    /// Which group released this chapter, when the source says.
    let scanlator: String?
    /// Ordering key that does not depend on how the source listed the chapters.
    /// MangaFire returns newest-first, most novel sources oldest-first, so
    /// `position` is not comparable across sources — the number is.
    let sortNumber: Double
    let sourceKey: String
    let entryURL: String?
    /// Which reader opens this chapter. Needed because a browse result has no
    /// stored entry to ask.
    let kind: ContentKind

    /// Shared so a row does not rebuild a format style per access.
    private static let releaseStyle = Date.FormatStyle()

    var releaseTime: String? {
        releaseDate.map { $0.formatted(Self.releaseStyle) }
    }

    init(chapter: Chapter, position: Int? = nil) {
        self.id = chapter.url
        self.name = chapter.name
        self.path = chapter.url
        self.releaseDate = chapter.dateUpload
        self.unread = !chapter.read
        self.bookmarked = chapter.bookmark
        self.downloaded = chapter.isDownloaded
        self.progress = chapter.progress > 0 ? Int(chapter.progress) : nil
        self.isInProgress = chapter.isInProgress
        self.position = position ?? chapter.sourceOrder
        self.chapterNumber = chapter.chapterNumber >= 0 ? chapter.chapterNumber : nil
        self.scanlator = chapter.scanlator
        self.sortNumber = chapter.chapterNumber > 0
            ? chapter.chapterNumber
            : Double((position ?? chapter.sourceOrder) + 1)
        self.sourceKey = chapter.entry?.sourceKey ?? ""
        self.entryURL = chapter.entry?.url
        self.kind = chapter.entry?.kind ?? .novel
    }

    init(
        sourceChapter: SourceChapter,
        position: Int,
        sourceKey: String = "",
        entryURL: String? = nil,
        kind: ContentKind = .novel
    ) {
        self.id = sourceChapter.url
        self.name = sourceChapter.name
        self.path = sourceChapter.url
        self.releaseDate = sourceChapter.dateUpload
        self.unread = true
        self.bookmarked = false
        self.downloaded = false
        self.progress = nil
        self.isInProgress = false
        self.position = position
        self.chapterNumber = sourceChapter.chapterNumber >= 0 ? sourceChapter.chapterNumber : nil
        self.scanlator = sourceChapter.scanlator
        let parsed = sourceChapter.chapterNumber > 0
            ? sourceChapter.chapterNumber
            : ChapterRecognition.parseChapterNumber(sourceChapter.name)
        self.sortNumber = parsed > 0 ? parsed : Double(position + 1)
        self.sourceKey = sourceKey
        self.entryURL = entryURL
        self.kind = kind
    }
}

/// Bounded chapter pages keep navigation manageable even for very long novels.
struct ChapterDirectoryView: View {
    @Environment(\.dismiss) private var dismiss
    let entry: Entry?
    let sourceEntry: SourceEntry?
    let chapters: [ChapterDisplay]
    let sourceKey: String
    let currentChapterPath: String?
    var onSelect: ((ChapterDisplay) -> Void)? = nil
    var onClose: (() -> Void)? = nil
    let initialSearch: String
    let initialFilter: ChapterFilter

    init(entry: Entry?, chapters: [ChapterDisplay], sourceKey: String, currentChapterPath: String?, onSelect: ((ChapterDisplay) -> Void)? = nil, onClose: (() -> Void)? = nil, initialSearch: String = "", initialFilter: ChapterFilter = .all, sourceEntry: SourceEntry? = nil) {
        self.entry = entry; self.sourceEntry = sourceEntry; self.chapters = chapters; self.sourceKey = sourceKey; self.currentChapterPath = currentChapterPath
        self.onSelect = onSelect; self.onClose = onClose; self.initialSearch = initialSearch; self.initialFilter = initialFilter
        self._search = State(initialValue: initialSearch); self._selectedFilter = State(initialValue: initialFilter)
    }

    @State private var search = ""
    @State private var selectedFilter: ChapterFilter = .all
    @State private var page = 0
    @State private var jumpNumber = ""
    @State private var jumpError: String?
    @State private var initialized = false
    @State private var scrollTarget: String?
    @State private var scrollRequest = UUID()
    @State private var selection = ChapterSelection()
    @FocusState private var jumpFocused: Bool
    private let pageSize = 50

    private var filtered: [ChapterDisplay] {
        chapters.filter { chapter in
            let included: Bool
            switch selectedFilter {
            case .all: included = true
            case .unread: included = chapter.unread
            case .downloaded: included = chapter.downloaded
            case .bookmarked: included = chapter.bookmarked
            }
            return included && (search.isEmpty || chapter.name.localizedCaseInsensitiveContains(search) || String(chapter.position + 1) == search.trimmingCharacters(in: .whitespaces))
        }
    }
    private var pageCount: Int { ChapterPages.count(total: filtered.count, size: pageSize) }
    private var currentPage: Int { min(max(0, page), pageCount - 1) }
    private var visible: [ChapterDisplay] {
        let items = filtered
        if !search.isEmpty { return items }
        return Array(items[ChapterPages.bounds(total: items.count, page: currentPage, size: pageSize)])
    }
    private var pageLabel: String { label(for: currentPage) }
    private func label(for page: Int) -> String {
        let items = filtered
        guard !items.isEmpty else { return "No chapters" }
        let range = ChapterPages.bounds(total: items.count, page: page, size: pageSize)
        let ends = [items[range.lowerBound].position, items[range.upperBound - 1].position]
        return "\(ends.min()! + 1)–\(ends.max()! + 1)"
    }
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            List {
                Section {
                    HStack(spacing: 12) {
                        NovelCoverView(url: entry?.displayThumbnailURL ?? sourceEntry?.thumbnailURL, aspectRatio: LayoutConstants.coverAspectRatio).frame(width: 42, height: 60)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry?.displayTitle ?? sourceEntry?.title ?? "Chapters").font(.headline).lineLimit(2)
                            Text("\(chapters.count) chapters").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { goToCurrent() } label: { Image(systemName: "location.fill").frame(width: 44, height: 44) }
                            .accessibilityLabel("Go to current chapter")
                    }
                    HStack {
                        Image(systemName: "number").foregroundStyle(.secondary)
                        TextField("Jump to chapter", text: $jumpNumber).keyboardType(.numberPad).focused($jumpFocused)
                        Button("Go", action: jump).disabled(jumpNumber.isEmpty)
                    }
                    if let jumpError { Text(jumpError).font(.caption).foregroundStyle(.red) }
                }
                Section {
                    ForEach(visible) { chapter in
                        HStack(spacing: 8) {
                            Text(String(chapter.position + 1)).font(.caption.monospacedDigit()).foregroundStyle(chapter.path == currentChapterPath ? .primary : .secondary).fontWeight(chapter.path == currentChapterPath ? .semibold : .regular).frame(minWidth: 32)
                            if let onSelect {
                                Button { onSelect(chapter) } label: {
                                    HStack {
                                        Text(chapter.name).font(.subheadline).fontWeight(chapter.path == currentChapterPath ? .semibold : .regular).foregroundStyle(.primary).lineLimit(2)
                                        Spacer()
                                        if chapter.path == currentChapterPath { Image(systemName: "book.fill").foregroundStyle(.primary) }
                                        else if chapter.bookmarked { Image(systemName: "bookmark.fill").foregroundStyle(.secondary) }
                                    }.frame(minHeight: 44).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            } else {
                                ChapterRow(chapter: chapter, entry: entry, sourceKey: sourceKey,
                                           selection: entry == nil ? nil : selection, orderedPaths: { filtered.map(\.path) })
                            }
                        }.id(chapter.path)
                    }
                    if visible.isEmpty { ContentUnavailableView("No chapters", systemImage: "text.magnifyingglass", description: Text("Try another number, title, or filter.")) }
                } header: { Text(search.isEmpty ? "Chapters \(pageLabel)" : "\(filtered.count) results") }
            }
            .listStyle(.insetGrouped)
            .id("\(search.isEmpty ? currentPage : -1)-\(selectedFilter.rawValue)")
            .searchable(text: $search, prompt: "Search every chapter")
            .navigationTitle("Chapters").navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Filter", selection: Binding(get: { selectedFilter }, set: { selectedFilter = $0; page = 0 })) {
                            ForEach(ChapterFilter.allCases) { Text($0.rawValue).tag($0) }
                        }
                    } label: { Image(systemName: "line.3.horizontal.decrease").foregroundStyle(selectedFilter == .all ? Color.primary : Color.accentColor) }.accessibilityLabel("Filter chapters")
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { if let onClose { onClose() } else { dismiss() } } }
            }
            .safeAreaInset(edge: .bottom) {
                if selection.isActive {
                    ChapterSelectionBar(selection: selection, entry: entry, ordered: filtered,
                                        allChapters: chapters, sourceKey: sourceKey)
                } else if search.isEmpty && pageCount > 1 {
                    HStack {
                        Button { page = max(0, currentPage - 1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.disabled(currentPage == 0).accessibilityLabel("Previous 50 chapters")
                        Spacer()
                        Menu {
                            ForEach(0..<pageCount, id: \.self) { index in
                                Button(label(for: index)) { page = index }
                            }
                        } label: { Label("\(pageLabel) · \(currentPage + 1)/\(pageCount)", systemImage: "rectangle.split.3x1").font(.subheadline.monospacedDigit()) }
                        Spacer()
                        Button { page = min(pageCount - 1, currentPage + 1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.disabled(currentPage + 1 >= pageCount).accessibilityLabel("Next 50 chapters")
                    }.padding(.horizontal).padding(.vertical, 4).background(.bar)
                }
            }
            .onChange(of: chapters) { _, _ in if !initialized && !chapters.isEmpty { if initialSearch.isEmpty && initialFilter == .all { goToCurrent() }; initialized = true } }
            .onAppear { if !initialized && !chapters.isEmpty { if initialSearch.isEmpty && initialFilter == .all { goToCurrent() }; initialized = true } }
            .onChange(of: scrollRequest) { _, request in
                Task { @MainActor in
                    await Task.yield()
                    guard scrollRequest == request, let scrollTarget else { return }
                    proxy.scrollTo(scrollTarget, anchor: .center)
                }
            }
            }
        }.tint(AppTheme.accent)
    }
    private func goToCurrent() {
        search = ""; selectedFilter = .all
        page = (chapters.firstIndex { $0.path == currentChapterPath } ?? 0) / pageSize
        scrollTarget = currentChapterPath ?? chapters.first?.path; scrollRequest = UUID()
        jumpError = nil; jumpFocused = false
    }
    private func jump() {
        guard let number = Int(jumpNumber), let index = chapters.firstIndex(where: { $0.position + 1 == number }) else {
            jumpError = "Enter a chapter number from this book."; return
        }
        search = ""; selectedFilter = .all; page = index / pageSize
        scrollTarget = chapters[index].path; scrollRequest = UUID()
        jumpNumber = ""; jumpError = nil; jumpFocused = false
    }
}
