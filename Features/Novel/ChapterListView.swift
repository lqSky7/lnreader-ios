// ChapterListView.swift
// Sortable, filterable chapter list. Pagination and filtering are driven
// from the parent (NovelDetailView); this view only renders what it receives.

import SwiftUI

struct ChapterListView: View {
    let novel: Novel?
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
