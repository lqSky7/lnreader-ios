// MangaReaderView.swift - The manga reader: paged or continuous strip.
//
// One view for both layouts; the mode is a setting, not a different screen.
// Pages come from `MangaSource`, bytes from `PageLoader`, progress goes back
// through `LibraryManager`. See docs/MANGA_SUPPORT_PLAN.md §4.

import SwiftData
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct MangaReaderView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryManager.self) private var libraryManager
    @Environment(SourceManager.self) private var sourceManager

    let sourceKey: String
    let entryURL: String?

    @AppStorage("manga.readingMode") private var modeRaw = MangaReadingMode.pager.rawValue
    @AppStorage("manga.pagingDirection") private var directionRaw = MangaPagingDirection.leftToRight.rawValue

    @State private var chapterURL: String
    @State private var chapterName: String

    @State private var loader = PageLoader()
    @State private var pages: [SourcePage] = []
    @State private var storedChapters: [Chapter] = []
    @State private var currentIndex = 0
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showControls = true
    @State private var showChapterSheet = false

    init(sourceKey: String, entryURL: String?, chapterURL: String, chapterName: String) {
        self.sourceKey = sourceKey
        self.entryURL = entryURL
        self._chapterURL = State(initialValue: chapterURL)
        self._chapterName = State(initialValue: chapterName)
    }

    private var mode: MangaReadingMode {
        MangaReadingMode(rawValue: modeRaw) ?? .pager
    }

    private var direction: MangaPagingDirection {
        MangaPagingDirection(rawValue: directionRaw) ?? .leftToRight
    }

    private var storedChapter: Chapter? {
        storedChapters.first { $0.url == chapterURL }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            content
                .contentShape(Rectangle())
                .overlay {
                    if mode == .pager, !isLoading, errorMessage == nil {
                        pageTapZones
                    } else {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { toggleControls() }
                    }
                }

            if showControls {
                controls
            }
        }
        .statusBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .task { await loadChapter() }
        .sheet(isPresented: $showChapterSheet) { chapterSheet }
        .onAppear { setScreenAwake(true) }
        .onDisappear { setScreenAwake(false) }
        .onChange(of: currentIndex) { _, index in handlePageChange(index) }
        .onChange(of: modeRaw) { _, _ in
            // Re-run the layout without refetching the page list.
            showControls = true
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView().tint(.white)
        } else if let errorMessage {
            errorView(errorMessage)
        } else if pages.isEmpty {
            errorView("This chapter has no pages.")
        } else if mode == .webtoon {
            webtoon
        } else {
            pager
        }
    }

    private var pager: some View {
        TabView(selection: $currentIndex) {
            ForEach(pages.indices, id: \.self) { index in
                MangaPageView(page: pages[index], sourceKey: sourceKey, loader: loader)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .environment(\.layoutDirection, direction.layoutDirection)
        .ignoresSafeArea()
    }

    private var webtoon: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(pages.indices, id: \.self) { index in
                    MangaPageView(page: pages[index], sourceKey: sourceKey, loader: loader)
                        .id(index)
                        .onAppear {
                            if currentIndex != index { currentIndex = index }
                        }
                }
            }
        }
        .ignoresSafeArea()
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.white.opacity(0.8))
            Text(message)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
            Button("Try again") {
                Task { await loadChapter() }
            }
            .buttonStyle(.bordered)
            .tint(.white)
        }
        .padding(32)
    }

    // MARK: - Controls

    private var controls: some View {
        VStack {
            topBar
            Spacer()
            bottomBar
        }
        .background(
            LinearGradient(
                colors: [.black.opacity(0.65), .clear, .clear, .black.opacity(0.65)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        )
        .transition(.opacity)
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Close reader")

            VStack(alignment: .leading, spacing: 2) {
                Text(chapterName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(pageIndicator)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.7))
            }

            Spacer()

            Button {
                showChapterSheet = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Chapters")

            Menu {
                Picker("Layout", selection: $modeRaw) {
                    ForEach(MangaReadingMode.allCases) { readingMode in
                        Label(readingMode.displayName, systemImage: readingMode.iconName)
                            .tag(readingMode.rawValue)
                    }
                }
                if mode == .pager {
                    Picker("Direction", selection: $directionRaw) {
                        ForEach(MangaPagingDirection.allCases) { option in
                            Text(option.displayName).tag(option.rawValue)
                        }
                    }
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Reader options")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
    }

    private var bottomBar: some View {
        VStack(spacing: 6) {
            if pages.count > 1 {
                Slider(
                    value: Binding(
                        get: { Double(currentIndex) },
                        set: { newValue in
                            let target = Int(newValue.rounded())
                            if target != currentIndex { currentIndex = target }
                        }
                    ),
                    in: 0...Double(pages.count - 1),
                    step: 1
                )
                .tint(.white)
                .padding(.horizontal, 8)
                .accessibilityLabel("Page")
            }
            chapterArrows
        }
    }

    private var chapterArrows: some View {
        HStack {
            Button {
                Task { await moveChapter(by: -1) }
            } label: {
                Label("Previous", systemImage: "chevron.left")
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
            }
            .disabled(!hasChapter(offset: -1))
            .opacity(hasChapter(offset: -1) ? 1 : 0.3)
            .accessibilityLabel("Previous chapter")

            Spacer()

            Button {
                showControls = false
            } label: {
                Text(pageIndicator)
                    .font(.caption.monospacedDigit())
            }
            .accessibilityLabel("Hide controls")

            Spacer()

            Button {
                Task { await moveChapter(by: 1) }
            } label: {
                Label("Next", systemImage: "chevron.right")
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
            }
            .disabled(!hasChapter(offset: 1))
            .opacity(hasChapter(offset: 1) ? 1 : 0.3)
            .accessibilityLabel("Next chapter")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }

    private var pageIndicator: String {
        guard !pages.isEmpty else { return "" }
        return "\(min(currentIndex + 1, pages.count)) / \(pages.count)"
    }

    // MARK: - Loading

    private func loadChapter() async {
        isLoading = true
        errorMessage = nil
        loadStoredChapters()

        guard let source = sourceManager.mangaSource(forKey: sourceKey) else {
            errorMessage = "This source is not available. Reinstall it and try again."
            isLoading = false
            return
        }

        let chapter = SourceChapter(url: chapterURL, name: chapterName)
        do {
            let fetched = try await source.pages(chapter)
            pages = fetched
            currentIndex = resumeIndex(pageCount: fetched.count)
            isLoading = false

            if let storedChapter, let entry = storedChapter.entry {
                libraryManager.recordHistory(entry: entry, chapter: storedChapter, context: modelContext)
            }
            await loader.prefetch(pages, current: currentIndex, sourceKey: sourceKey)
        } catch {
            pages = []
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func loadStoredChapters() {
        guard let entryURL else { return }
        let key = sourceKey
        let predicate = #Predicate<Chapter> { $0.entry?.url == entryURL && $0.entry?.sourceKey == key }
        let descriptor = FetchDescriptor<Chapter>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.sourceOrder)]
        )
        storedChapters = (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Resume a chapter that was left part-read, otherwise start at the top.
    private func resumeIndex(pageCount: Int) -> Int {
        guard pageCount > 0 else { return 0 }
        guard let storedChapter, !storedChapter.read else { return 0 }
        return min(max(storedChapter.lastPageRead, 0), pageCount - 1)
    }

    // MARK: - Progress

    private func handlePageChange(_ index: Int) {
        guard !pages.isEmpty else { return }

        if let storedChapter {
            libraryManager.recordMangaProgress(
                chapter: storedChapter,
                pageIndex: index,
                pageCount: pages.count,
                context: modelContext
            )
        }
        Task { await loader.prefetch(pages, current: index, sourceKey: sourceKey) }
    }

    // MARK: - Chapter navigation

    private func hasChapter(offset: Int) -> Bool {
        guard let current = storedChapters.firstIndex(where: { $0.url == chapterURL }) else {
            return false
        }
        let target = current + offset
        return storedChapters.indices.contains(target)
    }

    // MARK: - Interaction

    /// Pager only: left and right thirds turn the page, the middle toggles the
    /// controls. In right-to-left mode the zones swap, matching the swipe
    /// direction the pager itself uses.
    private var pageTapZones: some View {
        HStack(spacing: 0) {
            tapZone { turnPage(forward: direction == .rightToLeft) }
            tapZone { toggleControls() }
            tapZone { turnPage(forward: direction != .rightToLeft) }
        }
    }

    private func tapZone(_ action: @escaping () -> Void) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
    }

    private func turnPage(forward: Bool) {
        let target = currentIndex + (forward ? 1 : -1)
        guard pages.indices.contains(target) else { return }
        currentIndex = target
    }

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.18)) { showControls.toggle() }
    }

    /// Reading should not be interrupted by the idle timer.
    private func setScreenAwake(_ awake: Bool) {
        #if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = awake
        #endif
    }

    // MARK: - Chapter sheet

    private var chapterSheet: some View {
        NavigationStack {
            Group {
                if storedChapters.isEmpty {
                    ContentUnavailableView(
                        "No chapters yet",
                        systemImage: "list.bullet",
                        description: Text("Add this title to your library to navigate its chapters here.")
                    )
                } else {
                    List(storedChapters) { chapter in
                        Button {
                            showChapterSheet = false
                            Task { await jumpToChapter(chapter) }
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(chapter.name)
                                        .font(.subheadline)
                                        .lineLimit(2)
                                    if !chapter.read {
                                        Text("Unread")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if chapter.url == chapterURL {
                                    Image(systemName: "book.fill")
                                        .foregroundStyle(.tint)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Chapters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showChapterSheet = false }
                }
            }
        }
    }

    private func jumpToChapter(_ chapter: Chapter) async {
        guard chapter.url != chapterURL else { return }
        chapterURL = chapter.url
        chapterName = chapter.name
        currentIndex = 0
        await loadChapter()
    }

    private func moveChapter(by offset: Int) async {
        guard let current = storedChapters.firstIndex(where: { $0.url == chapterURL }) else { return }
        let target = current + offset
        guard storedChapters.indices.contains(target) else { return }

        let next = storedChapters[target]
        chapterURL = next.url
        chapterName = next.name
        currentIndex = 0
        await loadChapter()
    }
}
