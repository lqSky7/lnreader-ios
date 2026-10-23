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
            .onAppear {
                let sorted = entry?.chapters.sorted { $0.sourceOrder < $1.sourceOrder } ?? []
                chapters = sorted.map { ChapterDisplay(chapter: $0) }
                chapterByPath = Dictionary(sorted.map { ($0.url, $0) }, uniquingKeysWith: { first, _ in first })
            }
    }
}
