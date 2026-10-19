import SwiftUI
import SwiftData

struct ReaderChapterListSheet: View {
    let novel: Novel?
    let currentChapterPath: String
    let onSelectChapter: (Chapter) -> Void
    let onDismiss: () -> Void
    @State private var chapters: [ChapterDisplay] = []
    @State private var chapterByPath: [String: Chapter] = [:]

    var body: some View {
        ChapterDirectoryView(novel: novel, chapters: chapters, pluginId: novel?.pluginId ?? "",
            currentChapterPath: currentChapterPath,
            onSelect: { chapter in if let stored = chapterByPath[chapter.path] { onSelectChapter(stored) } },
            onClose: onDismiss)
            .onAppear {
                let sorted = novel?.chapters.sorted { $0.position < $1.position } ?? []
                chapters = sorted.map { ChapterDisplay(chapter: $0) }
                chapterByPath = Dictionary(sorted.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
            }
    }
}
