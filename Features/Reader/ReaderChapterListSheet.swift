import SwiftUI
import SwiftData

struct ReaderChapterListSheet: View {
    let novel: Novel?
    let currentChapterPath: String
    let onSelectChapter: (Chapter) -> Void
    let onDismiss: () -> Void

    @State private var searchText = ""
    @State private var cachedChapters: [Chapter] = []
    
    // Window coordinates for displaying subset of chapters
    @State private var startIndex: Int = 0
    @State private var endIndex: Int = 0

    private var sortedChapters: [Chapter] {
        cachedChapters
    }

    private var filteredChapters: [Chapter] {
        let chapters = sortedChapters
        if searchText.isEmpty {
            guard !chapters.isEmpty else { return [] }
            let start = min(max(0, startIndex), chapters.count - 1)
            let end = min(max(0, endIndex), chapters.count - 1)
            guard start <= end else { return [] }
            return Array(chapters[start...end])
        } else {
            // Search full list but cap at 100 to prevent layout delays
            return Array(chapters.filter { $0.name.localizedCaseInsensitiveContains(searchText) }.prefix(100))
        }
    }

    private var currentChapterIndex: Int {
        if let index = sortedChapters.firstIndex(where: { $0.path == currentChapterPath }) {
            return index + 1
        }
        return 0
    }

    var body: some View {
        ZStack {
            // Dark Backdrop
            Color(red: 0.08, green: 0.08, blue: 0.10)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header Info Section
                HStack(alignment: .top, spacing: 16) {
                    // Novel Cover
                    NovelCoverView(
                        url: novel?.cover,
                        aspectRatio: LayoutConstants.coverAspectRatio
                    )
                    .frame(width: 54, height: 77)
                    .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 2)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(novel?.name ?? "Novel Title")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        Text("Chapter \(currentChapterIndex) of \(sortedChapters.count)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // Close Button
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.glass)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)

                Divider()
                    .background(Color.white.opacity(0.08))

                // Scrollable Chapter List
                ScrollView {
                    ScrollViewReader { proxy in
                        LazyVStack(spacing: 4) {
                            // Load previous button
                            if searchText.isEmpty && startIndex > 0 {
                                Button(action: loadPrevious) {
                                    Text("Load Previous Chapters (\(startIndex) left)")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(AppTheme.accent)
                                        .padding(.vertical, 12)
                                        .frame(maxWidth: .infinity)
                                        .background(Color.white.opacity(0.03))
                                        .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 12)
                                .padding(.top, 8)
                            }
                            
                            ForEach(filteredChapters, id: \.path) { chapter in
                                let isCurrent = chapter.path == currentChapterPath
                                
                                Button(action: {
                                    onSelectChapter(chapter)
                                }) {
                                    HStack {
                                        Text(chapter.name)
                                            .font(.system(size: 15, weight: isCurrent ? .bold : .regular))
                                            .foregroundColor(isCurrent ? .white : .white.opacity(0.7))
                                            .lineLimit(1)
                                            .multilineTextAlignment(.leading)

                                        Spacer(minLength: 16)

                                        Text("\(chapter.position + 1)")
                                            .font(.system(size: 13, weight: .regular))
                                            .foregroundColor(.white.opacity(0.4))
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)
                                    .contentShape(Rectangle())
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(isCurrent ? Color.white.opacity(0.12) : Color.clear)
                                    )
                                }
                                .buttonStyle(.plain)
                                .id(chapter.path)
                            }

                            // Load next button
                            if searchText.isEmpty && endIndex < sortedChapters.count - 1 {
                                Button(action: loadNext) {
                                    Text("Load Next Chapters (\(sortedChapters.count - 1 - endIndex) left)")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(AppTheme.accent)
                                        .padding(.vertical, 12)
                                        .frame(maxWidth: .infinity)
                                        .background(Color.white.opacity(0.03))
                                        .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 12)
                                .padding(.bottom, 8)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .onAppear {
                            // Automatically scroll to current chapter
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                proxy.scrollTo(currentChapterPath, anchor: .center)
                            }
                        }
                    }
                }

                // Sticky Bottom Search Field
                VStack(spacing: 0) {
                    Divider()
                        .background(Color.white.opacity(0.08))
                    
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                            .font(Typography.caption)

                        TextField("Search chapters…", text: $searchText)
                            .font(Typography.body)
                            .textFieldStyle(.plain)
                            .foregroundColor(.white)
                            .tint(AppTheme.accent)
                            .autocorrectionDisabled()

                        if !searchText.isEmpty {
                            Button(action: {
                                withAnimation { searchText = "" }
                            }) {
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
                    .padding(.vertical, 12)
                }
                .background(Color(red: 0.08, green: 0.08, blue: 0.10).ignoresSafeArea(edges: .bottom))
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if let novel {
                cachedChapters = novel.chapters.sorted { $0.position < $1.position }
            }
            initializeRange()
        }
    }

    private func initializeRange() {
        cachedChapters = novel?.chapters.sorted { $0.position < $1.position } ?? []
        let chapters = sortedChapters
        guard !chapters.isEmpty else { return }

        if let currentIdx = chapters.firstIndex(where: { $0.path == currentChapterPath }) {
            startIndex = max(0, currentIdx - 40)
            endIndex = min(chapters.count - 1, currentIdx + 40)
        } else {
            startIndex = 0
            endIndex = min(chapters.count - 1, 80)
        }
    }

    private func loadPrevious() {
        startIndex = max(0, startIndex - 50)
    }

    private func loadNext() {
        endIndex = min(sortedChapters.count - 1, endIndex + 50)
    }
}
