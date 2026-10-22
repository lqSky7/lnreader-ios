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
    @State private var chrome: ReaderChromeState = .control
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
                // A simultaneous gesture, not an overlay: an overlay of
                // `Color.clear` sits above the scroll view and eats the drag, so
                // the webtoon would not scroll and the pager would not swipe.
                .simultaneousGesture(
                    SpatialTapGesture()
                        .onEnded { value in handleTap(at: value.location.x) }
                )

            if chrome.isControl {
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
            chrome = .control
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

    // MARK: - Chrome

    /// Control state: every number and every action, on Liquid Glass.
    private var controls: some View {
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: 0)
            bottomBar
        }
        .background(
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.72), location: 0),
                    .init(color: .clear, location: 0.2),
                    .init(color: .clear, location: 0.8),
                    .init(color: .black.opacity(0.72), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        )
        .transition(.opacity)
    }

    private var topBar: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                glassCircleButton("xmark", label: "Close reader") { dismiss() }

                VStack(alignment: .leading, spacing: 3) {
                    Text(chapterName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(chapterSubtitle)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .glassEffect(.regular, in: .capsule)

                Spacer(minLength: 0)

                glassCircleButton("list.bullet", label: "Chapters") {
                    showChapterSheet = true
                }

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
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .accessibilityLabel("Reader options")
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    private var bottomBar: some View {
        GlassEffectContainer(spacing: 10) {
            VStack(spacing: 10) {
                if pages.count > 1 {
                    HStack(spacing: 12) {
                        Text("1")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.6))
                        Slider(value: pageBinding, in: 0...Double(pages.count - 1), step: 1)
                            .tint(.white)
                            .accessibilityLabel("Page")
                        Text("\(pages.count)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassEffect(.regular, in: .capsule)
                }

                HStack(spacing: 12) {
                    chapterButton(offset: -1, symbol: "chevron.left", label: "Previous chapter")

                    Spacer(minLength: 0)

                    Button {
                        setChrome(.focus)
                    } label: {
                        Text(pageIndicator)
                            .font(.footnote.monospacedDigit().weight(.semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)
                            .glassEffect(.regular.interactive(), in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Hide controls")

                    Spacer(minLength: 0)

                    chapterButton(offset: 1, symbol: "chevron.right", label: "Next chapter")
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    private func glassCircleButton(
        _ symbol: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func chapterButton(offset: Int, symbol: String, label: String) -> some View {
        Button {
            Task { await moveChapter(by: offset) }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .disabled(!hasChapter(offset: offset))
        .opacity(hasChapter(offset: offset) ? 1 : 0.35)
        .accessibilityLabel(label)
    }

    private var pageBinding: Binding<Double> {
        Binding(
            get: { Double(currentIndex) },
            set: { newValue in
                let target = Int(newValue.rounded())
                if target != currentIndex { currentIndex = target }
            }
        )
    }

    private var pageIndicator: String {
        guard !pages.isEmpty else { return "" }
        return "\(min(currentIndex + 1, pages.count)) / \(pages.count)"
    }

    /// `Ch. 200 · 3 / 112 · 27%` — everything the reader knows, in one line.
    private var chapterSubtitle: String {
        var parts: [String] = []

        if let number = storedChapter?.chapterNumber, number > 0 {
            let text = number == number.rounded()
                ? String(Int(number))
                : String(format: "%.1f", number)
            parts.append("Ch. \(text)")
        }

        if !pages.isEmpty {
            parts.append(pageIndicator)
            let percent = Int((Double(currentIndex + 1) / Double(pages.count) * 100).rounded())
            parts.append("\(percent)%")
        }

        return parts.joined(separator: " · ")
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

    /// Pager: left and right thirds turn the page, the middle toggles chrome.
    /// In right-to-left mode the zones swap, matching the swipe direction the
    /// pager itself uses. Webtoon has no zones — every tap toggles.
    private func handleTap(at x: CGFloat) {
        guard mode == .pager else {
            toggleControls()
            return
        }

        #if canImport(UIKit)
        let width = UIScreen.main.bounds.width
        #else
        let width: CGFloat = 400
        #endif

        let third = width / 3
        if x < third {
            turnPage(forward: direction == .rightToLeft)
        } else if x > width - third {
            turnPage(forward: direction != .rightToLeft)
        } else {
            toggleControls()
        }
    }

    private func turnPage(forward: Bool) {
        let target = currentIndex + (forward ? 1 : -1)
        guard pages.indices.contains(target) else { return }
        currentIndex = target
    }

    private func setChrome(_ state: ReaderChromeState) {
        guard chrome != state else { return }
        withAnimation(.easeInOut(duration: 0.2)) { chrome = state }
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    private func toggleControls() {
        setChrome(chrome.toggled)
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
