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
    @Binding var sortAscending: Bool
    @Binding var selectedFilter: ChapterFilter
    @Binding var searchText: String

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

                Menu {
                    ForEach(ChapterFilter.allCases) { filter in
                        Button {
                            selectedFilter = filter
                        } label: {
                            Label(filter.rawValue, systemImage: filterIcon(filter))
                        }
                    }
                } label: {
                    Label("Filter", systemImage: selectedFilter == .all
                          ? "line.3.horizontal.decrease"
                          : "line.3.horizontal.decrease.circle.fill")
                        .font(Typography.caption)
                }

                Button {
                    withAnimation { sortAscending.toggle() }
                } label: {
                    Label("Sort", systemImage: sortAscending ? "arrow.up" : "arrow.down")
                        .font(Typography.caption)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)

            // Search bar
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
    }

    private func filterIcon(_ filter: ChapterFilter) -> String {
        switch filter {
        case .all:        "line.3.horizontal"
        case .unread:     "eye.slash"
        case .downloaded: "arrow.down.circle"
        case .bookmarked: "bookmark"
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
    }

    init(sourceChapter: SourceChapter, position: Int) {
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
    }
}
