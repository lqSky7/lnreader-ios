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
    let novel: Novel?

    @State private var htmlContent = ""
    @State private var baseURL: URL? = nil
    @State private var isLoading = true
    @State private var showControls = true
    @State private var showSettings = false
    @State private var showChapterList = false
    @State private var startTTSWhenReady = false
    @State private var errorMessage: String?
    @State private var isPreparingTTS = false

    // Reader settings persisted across sessions
    @AppStorage("reader.fontSize") private var fontSize: Double = 18
    @AppStorage("reader.lineHeight") private var lineHeight: Double = 1.6
    @AppStorage("reader.fontFamily") private var fontFamily = "Georgia"
    @AppStorage("reader.padding") private var horizontalPadding: Double = 16
    @AppStorage("reader.backgroundColor") private var backgroundColorHex: String = ""
    @AppStorage("reader.textColor") private var textColorHex: String = ""
    @AppStorage("tts.voice") private var ttsVoiceId: String = "af_heart"
    @AppStorage("tts.speed") private var ttsSpeed: Double = 1.0

    init(chapterPath: String, chapterName: String, pluginId: String, novel: Novel?) {
        self._currentChapterPath = State(initialValue: chapterPath)
        self._currentChapterName = State(initialValue: chapterName)
        self.pluginId = pluginId
        self.novel = novel
        
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
                    backgroundColorHex: backgroundColorHex,
                    textColorHex: textColorHex,
                    bridge: ttsBridge,
                    baseURL: baseURL,
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
                .ignoresSafeArea(edges: (showControls && !ttsManager.isSpeaking) ? .bottom : .all)
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
                backgroundColorHex: $backgroundColorHex,
                textColorHex: $textColorHex
            )
        }
        .fullScreenCover(isPresented: $showChapterList) {
            ReaderChapterListSheet(
                novel: novel,
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
            if ready && startTTSWhenReady {
                startTTSWhenReady = false
                startTTSPlayback()
            }
        }
        .onChange(of: ttsManager.currentBlockIndex) { _, newIndex in
            ttsBridge.setActiveIndex(newIndex)
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

    // MARK: - Navigation Helpers

    private var sortedChapters: [Chapter] {
        guard let novel else { return [] }
        return novel.chapters.sorted { $0.position < $1.position }
    }

    private var hasPreviousChapter: Bool {
        guard novel != nil,
            let currentIndex = sortedChapters.firstIndex(where: { $0.path == currentChapterPath })
        else { return false }
        return currentIndex > 0
    }

    private var hasNextChapter: Bool {
        guard novel != nil,
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
        
        if pluginId == "local", let novel {
            do {
                let fileManager = FileManager.default
                let docDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let novelId = novel.path.replacingOccurrences(of: "local://", with: "")
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
                if let chapter = novel.chapters.first(where: { $0.path == currentChapterPath }) {
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
            if let novel,
                let chapter = novel.chapters.first(where: { $0.path == currentChapterPath })
            {
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

    private func startTTSPlayback(from startIndex: Int = 0) {
        guard ttsBridge.isReady else {
            startTTSWhenReady = true
            return
        }
        isPreparingTTS = true

        Task {
            let blocks = await ttsBridge.fetchTTSBlocks()
            withAnimation(.easeInOut(duration: 0.3)) {
                ttsManager.startReading(
                    blocks: blocks,
                    chapterName: currentChapterName,
                    novelName: novel?.name,
                    voice: ttsVoice,
                    speed: Float(ttsSpeed),
                    startBlockIndex: startIndex
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
