// MangaReaderView.swift - The manga reader: paged or continuous strip.
//
// One view for both layouts; the mode is a setting, not a different screen.
// Pages come from `MangaSource`, bytes from `PageLoader`, progress goes back
// through `LibraryManager`. See docs/MANGA_SUPPORT_PLAN.md §4.

import SwiftData
import SwiftUI
import GlurBackdrop
#if canImport(UIKit)
import UIKit
#endif

struct MangaReaderView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryManager.self) private var libraryManager
    @Environment(SourceManager.self) private var sourceManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let sourceKey: String
    let entryURL: String?

    /// Layout settings for this series: its own overrides over the global defaults.
    @State private var seriesSettings: MangaSeriesSettings
    // Observed so a changed global default re-renders a series that follows it.
    @AppStorage(MangaReaderSettingsKey.readingMode) private var defaultModeRaw = MangaReadingMode.pager.rawValue
    @AppStorage(MangaReaderSettingsKey.direction) private var defaultDirectionRaw = MangaPagingDirection.leftToRight.rawValue

    @State private var chapterURL: String
    @State private var chapterName: String

    @State private var loader = PageLoader()
    @State private var pages: [SourcePage] = []
    @State private var storedChapters: [Chapter] = []
    @State private var sourceChapters: [SourceChapter] = []
    @State private var isLoadingChapters = false
    @State private var chapterListError: String?
    @State private var chapterSourceEntry: SourceEntry?
    /// `chapterChoices` after scanlator rules.
    ///
    /// State, not a computed property: `hasChapter` asks for it twice per body
    /// evaluation, and rebuilding it means mapping every chapter plus a
    /// scanlator pass — over the whole list, for every tap and page turn.
    @State private var navigable: [SourceChapter] = []
    @State private var webtoonPosition: Int?
    @State private var readerWidth: CGFloat = 0
    @State private var currentIndex = 0
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var chrome: ReaderChromeState = .control
    @State private var showChapterSheet = false
    @State private var isDismissing = false
    @State private var scanlatorSettings: ScanlatorSettings

    init(sourceKey: String, entryURL: String?, chapterURL: String, chapterName: String) {
        self.sourceKey = sourceKey
        self.entryURL = entryURL
        self._chapterURL = State(initialValue: chapterURL)
        self._chapterName = State(initialValue: chapterName)
        self._scanlatorSettings = State(initialValue: ScanlatorSettings(key: "\(sourceKey)::\(entryURL ?? "")"))
        // A chapter opened outside a library entry has no series to remember,
        // so it is keyed by the chapter instead of sharing one empty-URL key.
        self._seriesSettings = State(initialValue: MangaSeriesSettings(key: "\(sourceKey)::\(entryURL ?? chapterURL)"))
    }

    private var mode: MangaReadingMode {
        _ = defaultModeRaw
        return seriesSettings.resolved.readingMode
    }

    private var direction: MangaPagingDirection {
        _ = defaultDirectionRaw
        return seriesSettings.resolved.direction
    }

    private var storedChapter: Chapter? {
        storedChapters.first { $0.url == chapterURL }
    }

    private var chapterChoices: [SourceChapter] {
        if !storedChapters.isEmpty {
            return storedChapters.map {
                SourceChapter(url: $0.url, name: $0.name, chapterNumber: $0.chapterNumber,
                              scanlator: $0.scanlator)
            }
        }
        return sourceChapters
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
                .simultaneousGesture(dismissSwipe)

            if chrome.isControl {
                controls
            }
        }
        .statusBarHidden(true)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { readerWidth = $0 }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .task {
            await loadChapter()
            await loadChapterChoices()
        }
        .sheet(isPresented: $showChapterSheet) { chapterSheet }
        .onAppear { setScreenAwake(true) }
        .onDisappear {
            setScreenAwake(false)
            libraryManager.flushProgress(context: modelContext)
        }
        .onChange(of: currentIndex) { _, index in handlePageChange(index) }
        .onChange(of: scanlatorSettings.value) { rebuildNavigable() }
        .onChange(of: mode) { _, _ in
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
        .id(chapterURL)
        .environment(\.layoutDirection, direction.layoutDirection)
        .ignoresSafeArea()
    }

    private var webtoon: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(pages.indices, id: \.self) { index in
                    MangaPageView(page: pages[index], sourceKey: sourceKey, loader: loader)
                        .id(index)
                }
            }
            .scrollTargetLayout()
        }
        .scrollPosition(id: $webtoonPosition, anchor: .top)
        .onAppear { webtoonPosition = currentIndex }
        .onChange(of: webtoonPosition) { _, index in
            if let index, pages.indices.contains(index) { currentIndex = index }
        }
        .id(chapterURL)
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

    /// Keep the image legible beneath the controls with a light edge blur.
    private var controls: some View {
        ZStack {
            VStack(spacing: 0) {
                GlurView(radius: 8, direction: .up)
                    .frame(height: 140)
                Spacer(minLength: 0)
                GlurView(radius: 8, direction: .down)
                    .frame(height: 140)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                bottomBar
            }
        }
        .transition(.opacity)
    }

    private var topBar: some View {
        GlassEffectContainer {
            ZStack {
                HStack {
                    glassCircleButton("chevron.left", label: "Close reader") { dismiss() }
                    Spacer()
                    optionsMenu
                }

                Button { showChapterSheet = true } label: {
                    Text(chapterName)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                        .frame(height: 46)
                        .padding(.horizontal, 20)
                        .glassEffect(.regular.interactive(), in: .capsule)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 60)
                .accessibilityLabel("Chapters: \(chapterName)")
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private var optionsMenu: some View {
        Menu {
            Picker("Layout", selection: Binding(
                get: { mode },
                set: { seriesSettings.setReadingMode($0) }
            )) {
                ForEach(MangaReadingMode.allCases) { readingMode in
                    Label(readingMode.displayName, systemImage: readingMode.iconName)
                        .tag(readingMode)
                }
            }
            if mode == .pager {
                Picker("Direction", selection: Binding(
                    get: { direction },
                    set: { seriesSettings.setDirection($0) }
                )) {
                    ForEach(MangaPagingDirection.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
            }
            Section("This series") {
                Button("Use for all series", systemImage: "square.stack") {
                    seriesSettings.makeDefault()
                }
                if seriesSettings.hasOverrides {
                    Button("Reset to default", systemImage: "arrow.uturn.backward") {
                        seriesSettings.reset()
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

    private var bottomBar: some View {
        GlassEffectContainer {
            HStack(spacing: 12) {
                if pages.count > 1 {
                    MangaPageSlider(index: Binding(get: { currentIndex }, set: seekPage), pageCount: pages.count)
                }
                HStack(spacing: 0) {
                    chapterButton(offset: -1, symbol: "chevron.left", label: "Previous chapter")
                    Divider().frame(height: 24)
                    chapterButton(offset: 1, symbol: "chevron.right", label: "Next chapter")
                }
                .glassEffect(.regular.interactive(), in: .capsule)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
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
        let available = !isLoading && hasChapter(offset: offset)
        return Button {
            Task { await moveChapter(by: offset) }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .disabled(!available)
        .opacity(available ? 1 : 0.35)
        .accessibilityLabel(label)
    }

    private var dismissSwipe: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                guard !isDismissing, value.startLocation.x > readerWidth - 36,
                      value.translation.width < -100,
                      abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                isDismissing = true
                dismiss()
            }
    }

    // MARK: - Loading

    private func loadChapter() async {
        let requestedURL = chapterURL
        isLoading = true
        pages = []
        errorMessage = nil
        loadStoredChapters()

        if let entryURL, let downloaded = OfflineChapters.manga(sourceKey: sourceKey, entryURL: entryURL, chapterURL: requestedURL) {
            pages = downloaded
            currentIndex = resumeIndex(pageCount: downloaded.count)
            isLoading = false
            if let storedChapter, let entry = storedChapter.entry {
                libraryManager.recordHistory(entry: entry, chapter: storedChapter, context: modelContext)
            }
            return
        }

        guard let source = sourceManager.mangaSource(forKey: sourceKey) else {
            errorMessage = "This source is not available. Reinstall it and try again."
            isLoading = false
            return
        }

        let chapter = SourceChapter(url: chapterURL, name: chapterName)
        do {
            let fetched = try await source.pages(chapter)
            guard !Task.isCancelled, chapterURL == requestedURL else { return }
            pages = fetched
            currentIndex = resumeIndex(pageCount: fetched.count)
            isLoading = false

            if let storedChapter, let entry = storedChapter.entry {
                libraryManager.recordHistory(entry: entry, chapter: storedChapter, context: modelContext)
            }
            await loader.prefetch(pages, current: currentIndex, sourceKey: sourceKey)
        } catch {
            guard !Task.isCancelled, chapterURL == requestedURL else { return }
            pages = []
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func loadStoredChapters() {
        guard let entryURL else {
            storedChapters = []
            return
        }
        let key = sourceKey
        let predicate = #Predicate<Chapter> { $0.entry?.url == entryURL && $0.entry?.sourceKey == key }
        let descriptor = FetchDescriptor<Chapter>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.sourceOrder)]
        )
        storedChapters = ((try? modelContext.fetch(descriptor)) ?? []).sorted { lhs, rhs in
            if lhs.chapterNumber != rhs.chapterNumber {
                return lhs.chapterNumber < rhs.chapterNumber
            }
            return lhs.sourceOrder < rhs.sourceOrder
        }
        rebuildNavigable()
    }

    private func loadChapterChoices() async {
        guard !isLoadingChapters, storedChapters.isEmpty, sourceChapters.isEmpty, let entryURL,
              let source = sourceManager.mangaSource(forKey: sourceKey) else { return }
        isLoadingChapters = true
        chapterListError = nil
        defer { isLoadingChapters = false }
        do {
            let entry = SourceEntry(sourceKey: sourceKey, kind: .manga, url: entryURL, title: "")
            sourceChapters = try await source.chapters(entry).sorted { lhs, rhs in
                if lhs.chapterNumber != rhs.chapterNumber {
                    return lhs.chapterNumber < rhs.chapterNumber
                }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            chapterSourceEntry = try? await source.details(entry)
            rebuildNavigable()
        } catch {
            chapterListError = error.localizedDescription
        }
    }

    /// Resume a chapter that was left part-read, otherwise start at the top.
    private func resumeIndex(pageCount: Int) -> Int {
        guard pageCount > 0 else { return 0 }
        guard let storedChapter, !storedChapter.read else { return 0 }
        return min(max(storedChapter.lastPageRead, 0), pageCount - 1)
    }

    // MARK: - Progress

    private func handlePageChange(_ index: Int) {
        guard !isLoading, pages.indices.contains(index) else { return }

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
        guard let current = navigableChapters.firstIndex(where: { $0.url == chapterURL }) else {
            return false
        }
        let target = current + offset
        return navigableChapters.indices.contains(target)
    }

    // MARK: - Interaction

    private func seekPage(_ index: Int) {
        guard pages.indices.contains(index) else { return }
        currentIndex = index
        if mode == .webtoon { webtoonPosition = index }
    }

    /// Pager: left and right thirds turn the page, the middle toggles chrome.
    /// In right-to-left mode the zones swap, matching the swipe direction the
    /// pager itself uses. Webtoon has no zones — every tap toggles.
    private func handleTap(at x: CGFloat) {
        guard mode == .pager else {
            toggleControls()
            return
        }

        let third = readerWidth / 3
        if x < third {
            turnPage(forward: direction == .rightToLeft)
        } else if x > readerWidth - third {
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
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { chrome = state }
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

    private var directoryChapters: [ChapterDisplay] {
        let stored = Dictionary(storedChapters.map { ($0.url, $0) }, uniquingKeysWith: { first, _ in first })
        return navigableChapters.enumerated().map { index, chapter in
            if let saved = stored[chapter.url] {
                return ChapterDisplay(chapter: saved, position: index)
            }
            return ChapterDisplay(sourceChapter: chapter, position: index, sourceKey: sourceKey,
                                  entryURL: entryURL, kind: .manga)
        }
    }

    private var navigableChapters: [SourceChapter] { navigable }

    private func rebuildNavigable() {
        let choices = chapterChoices
        let items = choices.map {
            ScanlatorRules.Item(number: $0.chapterNumber > 0 ? $0.chapterNumber : nil, scanlator: $0.scanlator)
        }
        navigable = ScanlatorRules.keptIndices(for: items, preference: scanlatorSettings.value).map { choices[$0] }
    }

    private var chapterSheet: some View {
        Group {
            if !chapterChoices.isEmpty {
                ChapterDirectoryView(
                    entry: storedChapters.first?.entry,
                    chapters: directoryChapters,
                    sourceKey: sourceKey,
                    currentChapterPath: chapterURL,
                    onSelect: { selected in
                        guard let chapter = chapterChoices.first(where: { $0.url == selected.path }) else { return }
                        showChapterSheet = false
                        Task { await jumpToChapter(chapter) }
                    },
                    onClose: { showChapterSheet = false },
                    sourceEntry: chapterSourceEntry
                )
            } else {
                NavigationStack {
                    Group {
                        if isLoadingChapters {
                            ProgressView("Loading chapters…")
                        } else {
                            VStack(spacing: 16) {
                                ContentUnavailableView("Chapters unavailable", systemImage: "list.bullet",
                                    description: Text(chapterListError ?? "This source has no chapters to show."))
                                Button("Try again") { Task { await loadChapterChoices() } }
                            }
                        }
                    }
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showChapterSheet = false }
                        }
                    }
                }
            }
        }
        .task { await loadChapterChoices() }
    }

    private func jumpToChapter(_ chapter: SourceChapter) async {
        guard chapter.url != chapterURL else { return }
        chapterURL = chapter.url
        chapterName = chapter.name
        currentIndex = 0
        await loadChapter()
    }

    private func moveChapter(by offset: Int) async {
        guard !isLoading, let current = navigableChapters.firstIndex(where: { $0.url == chapterURL }) else { return }
        let target = current + offset
        guard navigableChapters.indices.contains(target) else { return }

        let next = navigableChapters[target]
        chapterURL = next.url
        chapterName = next.name
        currentIndex = 0
        await loadChapter()
    }
}

/// A 44-point control so the scrubber aligns with the chapter navigation capsule.
private struct MangaPageSlider: View {
    @Binding var index: Int
    let pageCount: Int

    private var progress: CGFloat {
        CGFloat(index) / CGFloat(max(pageCount - 1, 1))
    }

    var body: some View {
        GeometryReader { geometry in
            let trackWidth = max(geometry.size.width - 88, 1)
            HStack(spacing: 8) {
                Text("\(index + 1)")
                    .frame(width: 24, alignment: .trailing)
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.25))
                    Capsule().fill(.white)
                        .frame(width: max(6, trackWidth * progress))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 6)
                .accessibilityHidden(true)
                Text("\(pageCount)")
                    .frame(width: 24, alignment: .leading)
            }
            .font(.caption.monospacedDigit().weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .glassEffect(.regular.interactive(), in: .capsule)
            .contentShape(Capsule())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let fraction = min(max((value.location.x - 44) / trackWidth, 0), 1)
                        index = Int((fraction * CGFloat(max(pageCount - 1, 0))).rounded())
                    }
            )
        }
        .frame(height: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page")
        .accessibilityValue("\(index + 1) of \(pageCount)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: index = min(index + 1, pageCount - 1)
            case .decrement: index = max(index - 1, 0)
            @unknown default: break
            }
        }
    }
}
