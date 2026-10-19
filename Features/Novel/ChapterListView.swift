// ChapterListView.swift
// Sortable, filterable chapter list. Pagination and filtering are driven
// from the parent (NovelDetailView); this view only renders what it receives.

import SwiftUI

struct ChapterListView: View {
    let novel: Novel?
    var allChapters: [ChapterDisplay] = []
    /// Pre-filtered, pre-sorted, pre-paged slice to display.
    let chapters: [ChapterDisplay]
    /// Total chapters (unfiltered) — shown in the header.
    let totalCount: Int
    /// Filtered chapter count — used for the header when a search/filter is active.
    let filteredCount: Int
    let pluginId: String
    @Binding var selectedRange: ChapterRange
    @Binding var selectedFilter: ChapterFilter
    @Binding var searchText: String
    @State private var showSearchField = false
    @State private var showDirectory = false

    private var isFiltered: Bool {
        selectedFilter != .all || !searchText.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                if isFiltered {
                    Text("\(filteredCount) / \(totalCount) Chapters")
                        .font(Typography.title)
                } else {
                    Text("\(totalCount) Chapters")
                        .font(Typography.title)
                }

                Spacer()

                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        // Search Button
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                showSearchField.toggle()
                            }
                        } label: {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 16, weight: .bold))
                                .frame(width: 40, height: 40)
                                .contentShape(Circle())
                        }
                        .glassEffect(showSearchField ? .regular.tint(AppTheme.accent) : .regular, in: .circle)

                        // Filter Menu
                        Menu {
                            ForEach(ChapterFilter.allCases) { filter in
                                Button {
                                    selectedFilter = filter
                                } label: {
                                    Label(filter.rawValue, systemImage: filterIcon(filter))
                                }
                            }
                        } label: {
                            Image(systemName: selectedFilter == .all ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                                .font(.system(size: 16, weight: .bold))
                                .frame(width: 40, height: 40)
                                .contentShape(Circle())
                        }
                        .glassEffect(selectedFilter != .all ? .regular.tint(AppTheme.accent) : .regular, in: .circle)

                        // Current Range Menu
                        Menu {
                            Button {
                                selectedRange = .progress
                            } label: {
                                Label("Current Progress", systemImage: "bookmark.fill")
                            }
                            Button {
                                selectedRange = .first
                            } label: {
                                Label("First Chapters", systemImage: "arrow.up.circle.fill")
                            }
                            Button {
                                selectedRange = .last
                            } label: {
                                Label("Last Chapters", systemImage: "arrow.down.circle.fill")
                            }
                        } label: {
                            Image(systemName: rangeIcon(selectedRange))
                                .font(.system(size: 16, weight: .bold))
                                .frame(width: 40, height: 40)
                                .contentShape(Circle())
                        }
                        .glassEffect(selectedRange != .progress ? .regular.tint(AppTheme.accent) : .regular, in: .circle)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)

            // Inline Search bar (expands when toggled)
            if showSearchField {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(Typography.caption)

                    TextField("Search chapters…", text: $searchText)
                        .font(Typography.body)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()

                    if !searchText.isEmpty {
                        Button {
                            withAnimation { searchText = "" }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassEffect(.regular, in: .rect(cornerRadius: 20))
                .contentShape(.rect(cornerRadius: 20))
                .padding(.horizontal)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            Button { showDirectory = true } label: {
                HStack {
                    Image(systemName: "square.grid.2x2").foregroundStyle(AppTheme.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Browse all chapters").font(.subheadline.bold())
                        Text("Jump by number, search, or browse in groups of 50").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.secondary)
                }.padding(14).background(AppTheme.cardBackground, in: .rect(cornerRadius: 16))
            }.buttonStyle(.plain).padding(.horizontal)

            // Chapter rows
            if chapters.isEmpty {
                Text(searchText.isEmpty ? "No chapters available." : "No results for \"\(searchText)\".")
                    .font(Typography.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(chapters) { chapter in
                        ChapterRow(
                            chapter: chapter,
                            novel: novel,
                            pluginId: pluginId
                        )
                        Divider().padding(.leading, 40)
                    }
                }
            }
        }
        .sheet(isPresented: $showDirectory) {
            ChapterDirectoryView(novel: novel, chapters: allChapters.isEmpty ? chapters : allChapters,
                pluginId: pluginId, currentChapterPath: chapters.first(where: { $0.unread })?.path ?? chapters.first?.path)
        }
        .onAppear {
            showSearchField = !searchText.isEmpty
        }
    }

    private func filterIcon(_ filter: ChapterFilter) -> String {
        switch filter {
        case .all:        "line.3.horizontal"
        case .unread:     "eye.slash"
        case .downloaded: "arrow.down.circle"
        case .bookmarked: "bookmark"
        }
    }

    private func rangeLabel(_ range: ChapterRange) -> String {
        switch range {
        case .progress: return "Current"
        case .first:    return "First 10"
        case .last:     return "Last 10"
        }
    }

    private func rangeIcon(_ range: ChapterRange) -> String {
        switch range {
        case .progress: return "bookmark"
        case .first:    return "arrow.up.circle"
        case .last:     return "arrow.down.circle"
        }
    }
}

// MARK: - Unified Chapter Display

/// Bridges SwiftData Chapter and SourceChapter into a single displayable type.
struct ChapterDisplay: Identifiable, Hashable {
    let id: String
    let name: String
    let path: String
    let releaseTime: String?
    let unread: Bool
    let bookmarked: Bool
    let downloaded: Bool
    let progress: Int?
    let position: Int
    let chapterNumber: Double?
    let pluginId: String
    let novelPath: String?

    init(chapter: Chapter) {
        self.id = chapter.path
        self.name = chapter.name
        self.path = chapter.path
        self.releaseTime = chapter.releaseTime
        self.unread = chapter.unread
        self.bookmarked = chapter.bookmark
        self.downloaded = chapter.isDownloaded
        self.progress = chapter.progress
        self.position = chapter.position
        self.chapterNumber = chapter.chapterNumber
        self.pluginId = chapter.novel?.pluginId ?? ""
        self.novelPath = chapter.novel?.path
    }

    init(sourceChapter: SourceChapter, position: Int, pluginId: String = "", novelPath: String? = nil) {
        self.id = sourceChapter.path
        self.name = sourceChapter.name
        self.path = sourceChapter.path
        self.releaseTime = sourceChapter.releaseTime
        self.unread = true
        self.bookmarked = false
        self.downloaded = false
        self.progress = nil
        self.position = position
        self.chapterNumber = sourceChapter.chapterNumber
        self.pluginId = pluginId
        self.novelPath = novelPath
    }
}

/// Bounded chapter pages keep navigation manageable even for very long novels.
struct ChapterDirectoryView: View {
    @Environment(\.dismiss) private var dismiss
    let novel: Novel?
    let chapters: [ChapterDisplay]
    let pluginId: String
    let currentChapterPath: String?
    var onSelect: ((ChapterDisplay) -> Void)? = nil
    var onClose: (() -> Void)? = nil
    @State private var search = ""
    @State private var selectedFilter: ChapterFilter = .all
    @State private var page = 0
    @State private var jumpNumber = ""
    @State private var jumpError: String?
    @State private var initialized = false
    @State private var scrollTarget: String?
    @State private var scrollRequest = UUID()
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
        return "\(items[range.lowerBound].position + 1)–\(items[range.upperBound - 1].position + 1)"
    }
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            List {
                Section {
                    HStack(spacing: 12) {
                        NovelCoverView(url: novel?.cover, aspectRatio: LayoutConstants.coverAspectRatio).frame(width: 42, height: 60)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(novel?.name ?? "Chapters").font(.headline).lineLimit(2)
                            Text("\(chapters.count) chapters").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { goToCurrent() } label: { Image(systemName: "location.fill").frame(width: 44, height: 44) }
                            .accessibilityLabel("Go to current chapter")
                    }
                    HStack {
                        Image(systemName: "number").foregroundStyle(AppTheme.accent)
                        TextField("Jump to chapter", text: $jumpNumber).keyboardType(.numberPad).focused($jumpFocused)
                        Button("Go", action: jump).disabled(jumpNumber.isEmpty)
                    }
                    if let jumpError { Text(jumpError).font(.caption).foregroundStyle(.red) }
                }
                Section {
                    ForEach(visible) { chapter in
                        HStack(spacing: 8) {
                            Text(String(chapter.position + 1)).font(.caption.monospacedDigit()).foregroundStyle(chapter.path == currentChapterPath ? AppTheme.accent : .secondary).frame(minWidth: 32)
                            if let onSelect {
                                Button { onSelect(chapter) } label: {
                                    HStack {
                                        Text(chapter.name).font(.subheadline).foregroundStyle(chapter.path == currentChapterPath ? AppTheme.accent : .primary).lineLimit(2)
                                        Spacer()
                                        if chapter.path == currentChapterPath { Image(systemName: "book.fill").foregroundStyle(AppTheme.accent) }
                                        else if chapter.bookmarked { Image(systemName: "bookmark.fill").foregroundStyle(AppTheme.accent) }
                                    }.frame(minHeight: 44).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            } else { ChapterRow(chapter: chapter, novel: novel, pluginId: pluginId) }
                        }.id(chapter.path)
                    }
                    if visible.isEmpty { ContentUnavailableView("No chapters", systemImage: "text.magnifyingglass", description: Text("Try another number, title, or filter.")) }
                } header: { Text(search.isEmpty ? "Chapters \(pageLabel)" : "\(filtered.count) results") }
            }
            .listStyle(.insetGrouped)
            .id("\(search.isEmpty ? currentPage : -1)-\(selectedFilter.rawValue)")
            .searchable(text: $search, prompt: "Search every chapter")
            .navigationTitle("Chapters").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Filter", selection: Binding(get: { selectedFilter }, set: { selectedFilter = $0; page = 0 })) {
                            ForEach(ChapterFilter.allCases) { Text($0.rawValue).tag($0) }
                        }
                    } label: { Image(systemName: selectedFilter == .all ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill") }.accessibilityLabel("Filter chapters")
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { if let onClose { onClose() } else { dismiss() } } }
            }
            .safeAreaInset(edge: .bottom) {
                if search.isEmpty && pageCount > 1 {
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
            .onChange(of: chapters) { _, _ in if !initialized && !chapters.isEmpty { goToCurrent(); initialized = true } }
            .onAppear { if !initialized && !chapters.isEmpty { goToCurrent(); initialized = true } }
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
