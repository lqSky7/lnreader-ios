// ChapterRow.swift
// Single chapter row with unread indicator, release time, and status icons.

import SwiftUI

struct ChapterRow: View {
    @Namespace private var chapterTransition
    @ObservedObject private var audioLibrary = TTSOfflineLibrary.shared
    @State private var showAudioDownloads = false
    let chapter: ChapterDisplay
    let novel: Novel?
    let pluginId: String
    private var bookPath: String { novel?.path ?? chapter.novelPath ?? chapter.path }
    private var bookID: String { TTSBookIdentity.make(pluginId: pluginId, novelPath: bookPath) }
    private var audioCount: Int { audioLibrary.downloads(bookId: bookID, chapterId: chapter.path).filter(\.isAvailable).count }

    var body: some View {
        NavigationLink {
            ReaderView(
                chapterPath: chapter.path,
                chapterName: chapter.name,
                pluginId: pluginId,
                novelPath: novel?.path ?? chapter.novelPath
            )
            .id(chapter.path)
            .bookZoom(from: chapter.path, in: chapterTransition)
        } label: {
            HStack(spacing: 12) {
                // Unread indicator dot
                Circle()
                    .fill(chapter.unread ? Color.primary : .clear)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 4) {
                    Text(chapter.name)
                        .font(Typography.body)
                        .foregroundStyle(chapter.unread ? .primary : .secondary)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        if let releaseTime = chapter.releaseTime {
                            Text(releaseTime)
                                .font(Typography.small)
                                .foregroundStyle(.tertiary)
                        }

                        if let progress = chapter.progress, progress > 0 {
                            Text("\(progress)%")
                                .font(Typography.small)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                // Status icons
                HStack(spacing: 8) {
                    if audioCount > 0 {
                        Label("\(audioCount)", systemImage: "headphones").font(Typography.small).foregroundStyle(.secondary)
                            .accessibilityLabel("\(audioCount) voices available offline")
                    }
                    if chapter.bookmarked {
                        Image(systemName: "bookmark.fill")
                            .foregroundStyle(.primary)
                            .font(Typography.small)
                    }
                    if chapter.downloaded {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(Typography.small)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .bookTransitionSource(chapter.path, in: chapterTransition)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Chapter audio", systemImage: "headphones") { showAudioDownloads = true }
        }
        .sheet(isPresented: $showAudioDownloads) {
            BookAudioDownloadsView(bookId: bookID, bookTitle: novel?.name ?? chapter.name, pluginId: pluginId, novelPath: bookPath,
                chapters: [TTSChapterChoice(chapter)], coverURL: novel?.cover, initialChapter: chapter.path)
        }
    }
}
