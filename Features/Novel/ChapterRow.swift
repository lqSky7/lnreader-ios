// ChapterRow.swift
// Single chapter row with unread indicator, release time, and status icons.

import SwiftUI

struct ChapterRow: View {
    @Environment(ReaderRouter.self) private var readerRouter
    @Namespace private var chapterTransition
    @ObservedObject private var audioLibrary = TTSOfflineLibrary.shared
    @State private var showAudioDownloads = false
    let chapter: ChapterDisplay
    let entry: Entry?
    let sourceKey: String
    private var bookPath: String { entry?.url ?? chapter.entryURL ?? chapter.path }
    private var bookID: String { TTSBookIdentity.make(pluginId: sourceKey, novelPath: bookPath) }
    private var audioCount: Int { audioLibrary.downloads(bookId: bookID, chapterId: chapter.path).filter(\.isAvailable).count }

    var body: some View {
        Button {
            readerRouter.open(
                chapter,
                sourceKey: sourceKey,
                entryURL: entry?.url ?? chapter.entryURL,
                kind: entry?.kind ?? chapter.kind
            )
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
                        if let scanlator = chapter.scanlator, !scanlator.isEmpty {
                            Text(scanlator.prefix(1).uppercased() + scanlator.dropFirst())
                                .font(Typography.small)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }

                        if let releaseTime = chapter.releaseTime {
                            Text(releaseTime)
                                .font(Typography.small)
                                .foregroundStyle(.tertiary)
                        }

                        if chapter.unread, let progress = chapter.progress, progress > 0, progress < 100 {
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
            BookAudioDownloadsView(bookId: bookID, bookTitle: entry?.displayTitle ?? chapter.name, sourceKey: sourceKey, entryURL: bookPath,
                chapters: [TTSChapterChoice(chapter)], coverURL: entry?.displayThumbnailURL, initialChapter: chapter.path)
        }
    }
}
