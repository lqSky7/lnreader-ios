// ChapterListView.swift
// Sortable, filterable chapter list supporting both SwiftData and source chapters.

import SwiftUI

struct ChapterListView: View {
    let novel: Novel?
    let sourceChapters: [SourceChapter]
    let pluginId: String
    @Binding var sortAscending: Bool
    @Binding var selectedFilter: ChapterFilter

    /// Unified chapter list from either source.
    private var chapters: [ChapterDisplay] {
        if let novel, !novel.chapters.isEmpty {
            return novel.chapters.map { ChapterDisplay(chapter: $0) }
        }
        return sourceChapters.map { ChapterDisplay(sourceChapter: $0) }
    }

    private var filteredChapters: [ChapterDisplay] {
        var result = chapters
        switch selectedFilter {
        case .all: break
        case .unread: result = result.filter { $0.unread }
        case .downloaded: result = result.filter { $0.downloaded }
        case .bookmarked: result = result.filter { $0.bookmarked }
        }
        return sortAscending ? result : result.reversed()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("\(chapters.count) Chapters")
                    .font(Typography.title)

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
                    Label("Filter", systemImage: "line.3.horizontal.decrease")
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

            // Chapter rows
            LazyVStack(spacing: 0) {
                ForEach(filteredChapters) { chapter in
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

    private func filterIcon(_ filter: ChapterFilter) -> String {
        switch filter {
        case .all: "line.3.horizontal"
        case .unread: "eye.slash"
        case .downloaded: "arrow.down.circle"
        case .bookmarked: "bookmark"
        }
    }
}

// MARK: - Unified Chapter Display

/// Bridges SwiftData Chapter and SourceChapter into a single displayable type.
struct ChapterDisplay: Identifiable {
    let id: String
    let name: String
    let path: String
    let releaseTime: String?
    let unread: Bool
    let bookmarked: Bool
    let downloaded: Bool
    let progress: Int?

    init(chapter: Chapter) {
        self.id = chapter.path
        self.name = chapter.name
        self.path = chapter.path
        self.releaseTime = chapter.releaseTime
        self.unread = chapter.unread
        self.bookmarked = chapter.bookmark
        self.downloaded = chapter.isDownloaded
        self.progress = chapter.progress
    }

    init(sourceChapter: SourceChapter) {
        self.id = sourceChapter.path
        self.name = sourceChapter.name
        self.path = sourceChapter.path
        self.releaseTime = sourceChapter.releaseTime
        self.unread = true
        self.bookmarked = false
        self.downloaded = false
        self.progress = nil
    }
}
