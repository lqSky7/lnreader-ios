// ReaderView.swift
// Full-screen chapter reader with tap-to-toggle controls.

import SwiftData
import SwiftUI

struct ReaderView: View {
    @Environment(PluginManager.self) private var pluginManager
    @Environment(LibraryManager.self) private var libraryManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @StateObject private var modelManager: TTSModelManager
    @StateObject private var ttsBridge = ReaderContentBridge()
    @StateObject private var ttsManager: ReaderTTSManager

    @State private var currentChapterPath: String
    @State private var currentChapterName: String
    let pluginId: String
    let novelPath: String?

    private func fetchNovel() -> Novel? {
        guard let novelPath else { return nil }
        let predicate = #Predicate<Novel> { $0.path == novelPath && $0.pluginId == pluginId }
        var descriptor = FetchDescriptor<Novel>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    @State private var htmlContent = ""
    @State private var baseURL: URL? = nil
    @State private var isLoading = true
    @State private var showControls = true
    @State private var showSettings = false
    @State private var showChapterList = false
    @State private var startTTSWhenReady = false
    @State private var errorMessage: String?
    @State private var isPreparingTTS = false
    @State private var cachedChapters: [Chapter] = []

    // Reader settings persisted across sessions
    @AppStorage("reader.fontSize") private var fontSize: Double = 18
    @AppStorage("reader.lineHeight") private var lineHeight: Double = 1.6
    @AppStorage("reader.fontFamily") private var fontFamily = "Georgia"
    @AppStorage("reader.padding") private var horizontalPadding: Double = 16
    @AppStorage("reader.backgroundColor") private var backgroundColorHex: String = ""
    @AppStorage("reader.textColor") private var textColorHex: String = ""
    @AppStorage("reader.bionicReading") private var bionicReading = false
    @AppStorage("reader.characterSpacing") private var characterSpacing: Double = 0.0
    @AppStorage("reader.wordSpacing") private var wordSpacing: Double = 0.0
    @AppStorage("reader.grainIntensity") private var grainIntensity: Double = 10.0
    @AppStorage("reader.lineFocusEnabled") private var lineFocusEnabled = false
    @AppStorage("reader.lineFocusLines") private var lineFocusLines = 1
    @AppStorage("reader.lineFocusDulling") private var lineFocusDulling = "mid"
    @AppStorage("reader.readingMode") private var readingMode = "scroll"
    @AppStorage("reader.verticalPadding") private var verticalPadding: Double = 20
    @AppStorage("tts.voice") private var ttsVoiceId: String = "af_heart"
    @AppStorage("tts.speed") private var ttsSpeed: Double = 1.0

    @ObservedObject private var focusManager = FocusModeManager.shared

    init(chapterPath: String, chapterName: String, pluginId: String, novelPath: String?) {
        self._currentChapterPath = State(initialValue: chapterPath)
        self._currentChapterName = State(initialValue: chapterName)
        self.pluginId = pluginId
        self.novelPath = novelPath
        
        let model = TTSModelManager()
        self._modelManager = StateObject(wrappedValue: model)
        self._ttsManager = StateObject(wrappedValue: ReaderTTSManager(modelManager: model))
    }

    var body: some View {
        ZStack {
            // Background
            resolvedBackgroundColor.ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showControls.toggle()
                    }
                }

            // Content
            if isLoading {
                LoadingView(message: "Loading chapter...")
            } else if let error = errorMessage {
                EmptyStateView(
                    icon: "exclamationmark.triangle",
                    title: "Error",
                    subtitle: error
                )
            } else {
                ReaderContent(
                    htmlContent: htmlContent,
                    fontSize: fontSize,
                    lineHeight: lineHeight,
                    fontFamily: fontFamily,
                    horizontalPadding: horizontalPadding,
                    verticalPadding: verticalPadding,
                    backgroundColorHex: backgroundColorHex,
                    textColorHex: textColorHex,
                    bionicReading: bionicReading,
                    lineFocusEnabled: lineFocusEnabled,
                    lineFocusLines: lineFocusLines,
                    lineFocusDulling: lineFocusDulling,
                    readingMode: readingMode,
                    showControls: showControls,
                    bridge: ttsBridge,
                    baseURL: baseURL,
                    characterSpacing: characterSpacing,
                    wordSpacing: wordSpacing,
                    grainIntensity: grainIntensity,
                    onTap: {
                        guard !ttsManager.isSpeaking else { return }
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showControls.toggle()
                        }
                    },
                    onParagraphTap: { index in
                        if ttsManager.isSpeaking {
                            // Restart TTS from the tapped paragraph immediately
                            ttsManager.stop()
                            Task {
                                try? await Task.sleep(nanoseconds: 100_000_000)
                                startTTSPlayback(from: index)
                            }
                        }
                    }
                )
                .ignoresSafeArea(.all)
            }

            // Normal Toolbar (visible when showControls is true AND ttsManager.isSpeaking is false)
            ReaderToolbar(
                chapterName: currentChapterName,
                hasPrevious: hasPreviousChapter,
                hasNext: hasNextChapter,
                isPreparingTTS: isPreparingTTS,
                onDismiss: { dismiss() },
                onSettings: { showSettings = true },
                onTTSStart: { startTTSPlayback() },
                onPreviousChapter: navigateToPreviousChapter,
                onNextChapter: navigateToNextChapter,
                onChapterClick: { showChapterList = true }
            )
            .opacity((showControls && !ttsManager.isSpeaking) ? 1.0 : 0.0)
            .blur(radius: (showControls && !ttsManager.isSpeaking) ? 0.0 : 8.0)
            .scaleEffect((showControls && !ttsManager.isSpeaking) ? 1.0 : 0.96)
            .allowsHitTesting(showControls && !ttsManager.isSpeaking)

            // TTS Controls Overlay (visible when ttsManager.isSpeaking is true)
            ttsControlsOverlay
                .opacity(ttsManager.isSpeaking ? 1.0 : 0.0)
                .blur(radius: ttsManager.isSpeaking ? 0.0 : 8.0)
                .scaleEffect(ttsManager.isSpeaking ? 1.0 : 0.96)
                .allowsHitTesting(ttsManager.isSpeaking)

            // Focus Status Indicator Overlay (visible when controls and TTS speaking overlay are hidden)
            VStack {
                if !showControls && !ttsManager.isSpeaking {
                    ReaderFocusIndicator()
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
                Spacer()
            }
            .ignoresSafeArea(.keyboard)
            .allowsHitTesting(true)
            .padding(.top, 12)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .statusBarHidden(!showControls || ttsManager.isSpeaking)
        .fullScreenCover(isPresented: $showSettings) {
            ReaderSettings(
                fontSize: $fontSize,
                lineHeight: $lineHeight,
                fontFamily: $fontFamily,
                horizontalPadding: $horizontalPadding,
                verticalPadding: $verticalPadding,
                backgroundColorHex: $backgroundColorHex,
                textColorHex: $textColorHex,
                bionicReading: $bionicReading,
                lineFocusEnabled: $lineFocusEnabled,
                lineFocusLines: $lineFocusLines,
                lineFocusDulling: $lineFocusDulling,
                readingMode: $readingMode,
                characterSpacing: $characterSpacing,
                wordSpacing: $wordSpacing,
                grainIntensity: $grainIntensity
            )
        }
        .fullScreenCover(isPresented: $showChapterList) {
            ReaderChapterListSheet(
                novel: fetchNovel(),
                currentChapterPath: currentChapterPath,
                onSelectChapter: { chapter in
                    showChapterList = false
                    navigateToChapter(chapter)
                },
                onDismiss: {
                    showChapterList = false
                }
            )
        }
        .task { await loadChapter() }
        .onChange(of: ttsBridge.isReady) { _, ready in
            if ready {
                if let lastIndex = currentChapter?.lastReadParagraphIndex, lastIndex > 0 {
                    ttsBridge.scrollToParagraph(lastIndex)
                }
                if startTTSWhenReady {
                    startTTSWhenReady = false
                    startTTSPlayback()
                }
            }
        }
        .onChange(of: ttsManager.currentBlockIndex) { _, newIndex in
            if let newIndex = newIndex {
                ttsBridge.setActiveIndex(newIndex)
                
                // Save reading progress to database
                if let chapter = currentChapter {
                    chapter.lastReadParagraphIndex = newIndex
                    
                    let total = ttsManager.totalBlocks
                    if total > 0 {
                        let percent = Int(Double(newIndex + 1) / Double(total) * 100)
                        chapter.progress = min(max(percent, 0), 100)
                    }
                    try? modelContext.save()
                }
            }
        }
        .onChange(of: ttsManager.isSpeaking) { _, isSpeaking in
            if isSpeaking {
                isPreparingTTS = false
            } else {
                ttsBridge.clearActive()
            }
        }
        .onChange(of: ttsManager.errorMessage) { _, error in
            if error != nil {
                isPreparingTTS = false
            }
        }
        .onReceive(ttsBridge.paragraphScrollPublisher) { index in
            // Only update progress when TTS is not active (TTS updates it automatically)
            guard !ttsManager.isSpeaking else { return }
            if let chapter = currentChapter {
                chapter.lastReadParagraphIndex = index
                try? modelContext.save()
            }
        }
        .onAppear {
            FocusModeManager.shared.updateFocusStatus()
        }
        .onDisappear {
            ttsManager.stop()
            modelManager.cancelDownload()
        }
    }

    private var resolvedBackgroundColor: Color {
        if backgroundColorHex.isEmpty {
            return AppTheme.readerBackground
        }
        return Color(hex: backgroundColorHex) ?? AppTheme.readerBackground
    }

    private var currentChapter: Chapter? {
        cachedChapters.first(where: { $0.path == currentChapterPath })
    }

    // MARK: - Navigation Helpers

    private var sortedChapters: [Chapter] {
        cachedChapters
    }

    private var hasPreviousChapter: Bool {
        guard novelPath != nil,
            let currentIndex = sortedChapters.firstIndex(where: { $0.path == currentChapterPath })
        else { return false }
        return currentIndex > 0
    }

    private var hasNextChapter: Bool {
        guard novelPath != nil,
            let currentIndex = sortedChapters.firstIndex(where: { $0.path == currentChapterPath })
        else { return false }
        return currentIndex < sortedChapters.count - 1
    }

    private func navigateToPreviousChapter() {
        ttsManager.stop()
        guard
            let currentIndex = sortedChapters.firstIndex(where: { $0.path == currentChapterPath }),
            currentIndex > 0
        else { return }
        let prevChapter = sortedChapters[currentIndex - 1]
        currentChapterPath = prevChapter.path
        currentChapterName = prevChapter.name
        isLoading = true
        Task {
            await loadChapter()
        }
    }

    private func navigateToNextChapter() {
        ttsManager.stop()
        guard
            let currentIndex = sortedChapters.firstIndex(where: { $0.path == currentChapterPath }),
            currentIndex < sortedChapters.count - 1
        else { return }
        let nextChapter = sortedChapters[currentIndex + 1]
        currentChapterPath = nextChapter.path
        currentChapterName = nextChapter.name
        isLoading = true
        Task {
            await loadChapter()
        }
    }

    private func navigateToChapter(_ chapter: Chapter) {
        ttsManager.stop()
        currentChapterPath = chapter.path
        currentChapterName = chapter.name
        isLoading = true
        Task {
            await loadChapter()
        }
    }

    // MARK: - Data Loading

    private func loadChapter() async {
        ttsManager.stop()
        ttsBridge.contentDidChange()
        
        if cachedChapters.isEmpty, let novelPath {
            let predicate = #Predicate<Chapter> { $0.novel?.path == novelPath && $0.novel?.pluginId == pluginId }
            var descriptor = FetchDescriptor<Chapter>(predicate: predicate, sortBy: [SortDescriptor(\.position)])
            descriptor.relationshipKeyPathsForPrefetching = []
            if let fetched = try? modelContext.fetch(descriptor) {
                self.cachedChapters = fetched
            }
        }
        
        if pluginId == "local", let novelPath {
            do {
                let fileManager = FileManager.default
                let docDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let novelId = novelPath.replacingOccurrences(of: "local://", with: "")
                let bookDir = docDir.appendingPathComponent("LocalNovels").appendingPathComponent(novelId)
                let chapterURL = bookDir.appendingPathComponent(currentChapterPath)
                
                guard fileManager.fileExists(atPath: chapterURL.path) else {
                    errorMessage = "Chapter file not found: \(currentChapterPath)"
                    isLoading = false
                    return
                }
                
                let rawHtml = try String(contentsOf: chapterURL, encoding: .utf8)
                htmlContent = rawHtml
                baseURL = chapterURL.deletingLastPathComponent()
                isLoading = false
                
                // Record reading history
                if let chapter = cachedChapters.first(where: { $0.path == currentChapterPath }),
                   let novel = fetchNovel() {
                    libraryManager.recordHistory(novel: novel, chapter: chapter, context: modelContext)
                }
            } catch {
                errorMessage = "Failed to load local chapter: \(error.localizedDescription)"
                isLoading = false
            }
            return
        }
        
        guard let source = pluginManager.plugin(for: pluginId) else {
            errorMessage = "Source plugin not found."
            isLoading = false
            return
        }

        do {
            htmlContent = try await source.parseChapter(path: currentChapterPath)
            baseURL = nil
            isLoading = false

            // Record reading history
            if let novel = fetchNovel(),
               let chapter = cachedChapters.first(where: { $0.path == currentChapterPath }) {
                libraryManager.recordHistory(novel: novel, chapter: chapter, context: modelContext)
            }
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private var ttsVoice: String {
        ttsVoiceId.isEmpty ? "af_heart" : ttsVoiceId
    }

    private func toggleTTSPlayback() {
        if ttsManager.isSpeaking {
            ttsManager.togglePause()
        } else {
            startTTSPlayback()
        }
    }

    private func startTTSPlayback(from startIndex: Int? = nil) {
        print("🔊 [ReaderView] startTTSPlayback called. ttsBridge.isReady: \(ttsBridge.isReady)")
        guard ttsBridge.isReady else {
            print("🔊 [ReaderView] ttsBridge is not ready. Delaying start.")
            startTTSWhenReady = true
            return
        }
        isPreparingTTS = true

        let resolvedStartIndex = startIndex ?? currentChapter?.lastReadParagraphIndex ?? 0
        print("🔊 [ReaderView] Resolving start index: \(resolvedStartIndex). Fetching blocks…")

        Task {
            let blocks = await ttsBridge.fetchTTSBlocks()
            print("🔊 [ReaderView] Fetched blocks: \(blocks.count). Calling ttsManager.startReading.")
            withAnimation(.easeInOut(duration: 0.3)) {
                ttsManager.startReading(
                    blocks: blocks,
                    chapterName: currentChapterName,
                    voice: ttsVoice,
                    speed: Float(ttsSpeed),
                    startBlockIndex: resolvedStartIndex
                )
            }
        }
    }

    private func stopTTSPlayback() {
        isPreparingTTS = false
        withAnimation(.easeInOut(duration: 0.3)) {
            ttsManager.stop()
        }
    }

    private func updateSpeed(_ newSpeed: Double) {
        ttsSpeed = newSpeed
        if ttsManager.isSpeaking {
            let currentIndex = ttsManager.currentBlockIndex ?? 0
            ttsManager.stop()
            Task {
                try? await Task.sleep(nanoseconds: 100_000_000)
                startTTSPlayback(from: currentIndex)
            }
        }
    }

    private var ttsControlsOverlay: some View {
        VStack {
            Spacer()
            
            HStack(alignment: .bottom) {
                // Bottom left: Exit TTS mode button
                Button {
                    stopTTSPlayback()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 46, height: 46)
                        .contentShape(Circle())
                }
                .buttonStyle(InteractivePlainButtonStyle())
                .glassEffect(.regular.interactive(), in: .circle)
                
                Spacer()
                
                // Bottom mid: Play/Pause + Stop capsule
                HStack(spacing: 0) {
                    Button {
                        toggleTTSPlayback()
                    } label: {
                        Image(systemName: ttsManager.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 46, height: 46)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                    Divider()
                        .frame(height: 24)
                        .background(Color.white.opacity(0.2))
                    
                    Button {
                        stopTTSPlayback()
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 46, height: 46)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .glassEffect(.regular.interactive(), in: .capsule)
                
                Spacer()
                
                // Bottom right: Speed menu popup
                Menu {
                    ForEach([1.0, 1.2, 1.5, 1.7, 1.8, 2.0], id: \.self) { speedOption in
                        Button {
                            updateSpeed(speedOption)
                        } label: {
                            HStack {
                                Text(String(format: "%.1fx", speedOption))
                                if ttsSpeed == speedOption {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Text(String(format: "%.1fx", ttsSpeed))
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 46, height: 46)
                        .contentShape(Circle())
                }
                .buttonStyle(InteractivePlainButtonStyle())
                .glassEffect(.regular.interactive(), in: .circle)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }
}

// MARK: - Focus Indicator View Overlay
struct ReaderFocusIndicator: View {
    @ObservedObject var focusManager = FocusModeManager.shared
    @State private var showLabel = false
    @State private var labelTimer: Timer? = nil

    var body: some View {
        let activeType = focusManager.currentFocusType
        if activeType != .none {
            VStack(spacing: 8) {
                Button {
                    // Show label temporarily on tap
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        showLabel = true
                    }
                    // Start timer to hide label
                    labelTimer?.invalidate()
                    labelTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { _ in
                        withAnimation(.easeInOut(duration: 0.5)) {
                            showLabel = false
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: activeType.iconName)
                            .font(.system(size: 11, weight: .bold))
                        
                        if showLabel {
                            Text(activeType.displayName)
                                .font(.system(size: 11, weight: .bold))
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .trailing)),
                                    removal: .opacity
                                ))
                        }
                    }
                    .foregroundColor(.white.opacity(0.75))
                    .padding(.horizontal, showLabel ? 12 : 8)
                    .padding(.vertical, 6)
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
                .buttonStyle(.plain)
                
                // If label is shown, offer a small manual override selector
                if showLabel {
                    HStack(spacing: 12) {
                        Button {
                            cycleOverride()
                        } label: {
                            Text("Change Focus")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.white.opacity(0.8))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .glassEffect(.regular.interactive(), in: .capsule)
                        }
                        .buttonStyle(.plain)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
        }
    }
    
    private func cycleOverride() {
        let options = ["auto", "dnd", "work", "sleep", "none"]
        if let index = options.firstIndex(of: focusManager.overrideType) {
            let nextIndex = (index + 1) % options.count
            withAnimation {
                focusManager.overrideType = options[nextIndex]
                focusManager.updateFocusStatus()
            }
        }
    }
}
