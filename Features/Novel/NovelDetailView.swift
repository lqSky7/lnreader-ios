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
    @State private var chapterSortAscending = true
    @State private var selectedFilter: ChapterFilter = .all
    @State private var errorMessage: String?

    // Pagination + search state
    @State private var chapterPage = 0
    @State private var chapterSearch = ""
    @State private var navigateToChapter: ChapterDisplay? = nil

    @Namespace private var paginationNamespace

    private let pageSize = 20

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
        NovelDetailScrollView(
            totalChapterPages: totalChapterPages,
            content: VStack(spacing: 0) {
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
                        chapters: pagedChapters,
                        totalCount: allChapters.count,
                        filteredCount: filteredChapters.count,
                        pluginId: pluginId,
                        sortAscending: $chapterSortAscending,
                        selectedFilter: $selectedFilter,
                        searchText: $chapterSearch
                    )
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                hideKeyboard()
            },
            paginationBar: paginationBar
        )
        .toolbar(removing: .title)
        .navigationDestination(item: $navigateToChapter) { chapter in
            ReaderView(
                chapterPath: chapter.path,
                chapterName: chapter.name,
                pluginId: pluginId,
                novel: novel
            )
        }
        .onChange(of: selectedFilter) { chapterPage = 0 }
        .onChange(of: chapterSortAscending) { chapterPage = 0 }
        .onChange(of: chapterSearch) { chapterPage = 0 }
        .task { await fetchNovelData() }
    }

    // MARK: - Chapter Computation

    private var allChapters: [ChapterDisplay] {
        if let novel, !novel.chapters.isEmpty {
            return novel.chapters
                .map { ChapterDisplay(chapter: $0) }
                .sorted { ch1, ch2 in
                    if ch1.position != ch2.position {
                        return ch1.position < ch2.position
                    }
                    if let num1 = ch1.chapterNumber, let num2 = ch2.chapterNumber {
                        return num1 < num2
                    }
                    return ch1.name.localizedStandardCompare(ch2.name) == .orderedAscending
                }
        }
        return (sourceNovel?.chapters ?? [])
            .enumerated()
            .map { ChapterDisplay(sourceChapter: $1, position: $0) }
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
        return chapterSortAscending ? result : result.reversed()
    }

    private var totalChapterPages: Int {
        max(1, Int(ceil(Double(filteredChapters.count) / Double(pageSize))))
    }

    private var pagedChapters: [ChapterDisplay] {
        let start = chapterPage * pageSize
        let end = min(start + pageSize, filteredChapters.count)
        guard start < filteredChapters.count else { return [] }
        return Array(filteredChapters[start..<end])
    }

    // MARK: - Pagination Bar

    @ViewBuilder
    private var paginationBar: some View {
        HStack {
            Spacer()
            GlassEffectContainer(spacing: 0) {
                HStack(spacing: 0) {
                    Button {
                        withAnimation(.smooth) {
                            chapterPage = max(0, chapterPage - 1)
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.glass)
                    .glassEffectID("pg-prev", in: paginationNamespace)
                    .disabled(chapterPage == 0)

                    Text("\(chapterPage + 1) / \(totalChapterPages)")
                        .font(Typography.caption)
                        .monospacedDigit()
                        .frame(minWidth: 64)
                        .frame(height: 44)
                        .padding(.horizontal, 4)

                    Button {
                        withAnimation(.smooth) {
                            chapterPage = min(totalChapterPages - 1, chapterPage + 1)
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.glass)
                    .glassEffectID("pg-next", in: paginationNamespace)
                    .disabled(chapterPage == totalChapterPages - 1)
                }
            }
            Spacer()
        }
        .padding(.bottom, 8)
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
            if let novel {
                libraryManager.updateNovel(novel, sourceNovel: parsed, context: modelContext)
            }
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
        if let novel, !novel.chapters.isEmpty {
            let sorted = novel.chapters.sorted { $0.position < $1.position }
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

/// A performance-optimized ScrollView wrapper that isolates scroll offset tracking
/// to prevent parent views from re-evaluating their layout on every scroll frame.
struct NovelDetailScrollView<Content: View, Pagination: View>: View {
    let totalChapterPages: Int
    let content: Content
    let paginationBar: Pagination

    @State private var scrollOffset: CGFloat = 0

    var body: some View {
        ScrollView {
            content
        }
        .ignoresSafeArea(edges: .top)
        .scrollDismissesKeyboard(.immediately)
        .onScrollGeometryChange(for: CGFloat.self) { proxy in
            proxy.contentOffset.y + proxy.contentInsets.top
        } action: { _, offset in
            scrollOffset = offset
        }
        .safeAreaInset(edge: .bottom) {
            if totalChapterPages > 1 {
                let showPagination = scrollOffset > 300
                paginationBar
                    .opacity(showPagination ? 1.0 : 0.0)
                    .blur(radius: showPagination ? 0.0 : 10.0)
                    .scaleEffect(showPagination ? 1.0 : 0.95)
                    .allowsHitTesting(showPagination)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showPagination)
            }
        }
    }
}
