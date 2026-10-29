import SwiftUI
import SwiftData

struct ReaderChapterListSheet: View {
    let entry: Entry?
    let currentChapterPath: String
    let onSelectChapter: (Chapter) -> Void
    let onDismiss: () -> Void
    @State private var chapters: [ChapterDisplay] = []
    @State private var chapterByPath: [String: Chapter] = [:]

    var body: some View {
        ChapterDirectoryView(entry: entry, chapters: chapters, sourceKey: entry?.sourceKey ?? "",
            currentChapterPath: currentChapterPath,
            onSelect: { chapter in if let stored = chapterByPath[chapter.path] { onSelectChapter(stored) } },
            onClose: onDismiss)
            .onAppear(perform: load)
            // The rows are value snapshots, so a read-state change made in this
            // sheet has to rebuild them before the unread dot can go away.
            .onReceive(NotificationCenter.default.publisher(for: .lnreaderChapterReadChanged)) { _ in load() }
    }

    private func load() {
        let sorted = entry?.chapters.sorted { $0.sourceOrder < $1.sourceOrder } ?? []
        chapters = sorted.map { ChapterDisplay(chapter: $0) }
        chapterByPath = Dictionary(sorted.map { ($0.url, $0) }, uniquingKeysWith: { first, _ in first })
    }
}
