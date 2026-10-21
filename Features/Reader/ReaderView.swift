// ReaderView.swift
// Full-screen chapter reader with tap-to-toggle controls.

import SwiftData
import SwiftUI
import WebKit

struct ReaderView: View {
    @Environment(PluginManager.self) private var pluginManager
    @Environment(LibraryManager.self) private var libraryManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("reader.highlightColor") private var highlightColorHex = ""
    @AppStorage("reader.highlightOpacity") private var highlightOpacity = 0.26
    @AppStorage("reader.justifyText") private var justifyText = true

    @StateObject private var ttsBridge = ReaderContentBridge()
    @ObservedObject private var ttsManager = ReaderTTSManager.shared
    @ObservedObject private var audioLibrary = TTSOfflineLibrary.shared
    @State private var showAudioDownloads = false
    @State private var showSleepPicker = false
    @State private var showSpeedPicker = false
    @State private var speechScrubTime: Double?

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
    @State private var displayedAudioRevision: String?
    @State private var chapterLoadID = UUID()
    @State private var baseURL: URL? = nil
    @State private var isLoading = true
    @State private var showControls = true
    @State private var showSettings = false
    @State private var showChapterList = false
    @State private var startTTSWhenReady = false
    @State private var errorMessage: String?
    @State private var isPreparingTTS = false
    @State private var cachedChapters: [Chapter] = []
    
    // NovelFire / NovelPhoenix Comments State (same backend, different host)
    @State private var novelfirePostId = ""
    @State private var novelfireChapterId = ""
    @State private var novelfireCsrfToken = ""
    @State private var commentsHtml = ""
    @State private var nextCursor: String? = nil
    @State private var hasMoreComments = false
    @State private var showLoginSheet = false
    @State private var showCommentsSheet = false
    @State private var commentsTask: Task<Void, Never>?

    /// Comment site for the current plugin, if chapter comments are supported.
    private var commentSite: CommentSite? { CommentSite.site(for: pluginId) }

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
    @AppStorage("reader.verticalPadding") private var verticalPadding: Double = 20
    @AppStorage("tts.voice") private var ttsVoiceId: String = "qwen-ryan"
    @AppStorage("tts.speed") private var ttsSpeed: Double = 1.0

    @ObservedObject private var focusManager = FocusModeManager.shared

    init(chapterPath: String, chapterName: String, pluginId: String, novelPath: String?) {
        self._currentChapterPath = State(initialValue: chapterPath)
        self._currentChapterName = State(initialValue: chapterName)
        self.pluginId = pluginId
        self.novelPath = novelPath
        

    }

    private func toggleControls() {
        withAnimation(AppMotion.gentle(reduceMotion: reduceMotion)) { showControls.toggle() }
    }

    var body: some View {
        ZStack {
            // Background
            resolvedBackgroundColor.ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { toggleControls() }

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
                    showControls: showControls,
                    bridge: ttsBridge,
                    baseURL: baseURL,
                    characterSpacing: characterSpacing,
                    wordSpacing: wordSpacing,
                    grainIntensity: grainIntensity,
                    highlightColorHex: highlightColorHex,
                    highlightOpacity: highlightOpacity,
                    justifyText: justifyText,
                    commentsHtml: "",
                    hasMoreComments: false,
                    onTap: { toggleControls() },
                    onParagraphTap: { _ in },
                    onLoadMoreComments: nil,
                    onLikeComment: nil,
                    onDislikeComment: nil
                )
                .ignoresSafeArea(.all)
                .opacity(ttsBridge.isReady ? 1 : 0)
            }

            // Keep scrolled text clear of the toolbar without resizing the document.
            VStack {
                LinearGradient(stops: [.init(color: resolvedBackgroundColor, location: 0), .init(color: resolvedBackgroundColor, location: 0.88), .init(color: resolvedBackgroundColor.opacity(0), location: 1)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 136)
                Spacer()
            }
            .ignoresSafeArea()
            .opacity(showControls ? 1 : 0)
            .animation(AppMotion.gentle(reduceMotion: reduceMotion), value: showControls)
            .allowsHitTesting(false)

            // Reading and listening share the same top navigation.
            ReaderToolbar(
                chapterName: currentChapterName,
                hasPrevious: hasPreviousChapter,
                hasNext: hasNextChapter,
                isPreparingTTS: isPreparingTTS,
                onDismiss: { dismiss() },
                onSettings: { showSettings = true },
                onTTSStart: { isCurrentSpeech ? stopTTSPlayback() : startTTSPlayback() },
                onPreviousChapter: navigateToPreviousChapter,
                onNextChapter: navigateToNextChapter,
                onChapterClick: { showChapterList = true },
                onComments: commentSite != nil ? { showCommentsSheet = true } : nil,
                isListening: isCurrentSpeech
            )
            .opacity(showControls ? 1.0 : 0.0)
            .animation(AppMotion.gentle(reduceMotion: reduceMotion), value: showControls)
            .allowsHitTesting(showControls)
            .accessibilityHidden(!showControls)

            // TTS Controls Overlay (visible when isCurrentSpeech is true)
            ttsControlsOverlay
                .opacity(isCurrentSpeech && showControls ? 1.0 : 0.0)
                .animation(AppMotion.gentle(reduceMotion: reduceMotion), value: showControls)
                .animation(AppMotion.gentle(reduceMotion: reduceMotion), value: isCurrentSpeech)
                .allowsHitTesting(isCurrentSpeech && showControls)
                .accessibilityHidden(!isCurrentSpeech || !showControls)

            // Focus Status Indicator Overlay (visible when controls and TTS speaking overlay are hidden, and Line Focus mode is active)
            VStack {
                if !showControls && !isCurrentSpeech && lineFocusEnabled {
                    ReaderFocusIndicator()
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
                Spacer()
            }
            .ignoresSafeArea(.keyboard)
            .allowsHitTesting(!showControls && !isCurrentSpeech && lineFocusEnabled)
            .padding(.top, 12)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .statusBarHidden(true)
        .onChange(of: showControls) { _, visible in ttsBridge.setControlsVisible(visible) }
        .sheet(isPresented: $showSettings) {
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
                characterSpacing: $characterSpacing,
                wordSpacing: $wordSpacing,
                grainIntensity: $grainIntensity
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
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
        .sheet(isPresented: $showLoginSheet) {
            NovelFireLoginView(onLoginSuccess: {
                loadNovelFireComments()
            }, site: commentSite ?? .novelFire)
        }
        .sheet(isPresented: $showCommentsSheet) {
            NovelFireCommentsView(
                postId: novelfirePostId,
                chapterId: novelfireChapterId,
                csrfToken: novelfireCsrfToken,
                initialCommentsHtml: commentsHtml,
                initialNextCursor: nextCursor,
                initialHasMore: hasMoreComments,
                chapterPath: currentChapterPath,
                backgroundColorHex: backgroundColorHex,
                textColorHex: textColorHex,
                site: commentSite ?? .novelFire
            )
        }
        .task { await loadChapter() }
        .onChange(of: ttsBridge.isReady) { _, ready in
            if ready {
                ttsBridge.setSpeechMode(isCurrentSpeech)
                if isCurrentSpeech { ttsBridge.setActiveWord(displayedSpeechWord) }
                if !isCurrentSpeech, let lastIndex = currentChapter?.lastReadParagraphIndex, lastIndex > 0 {
                    ttsBridge.scrollToParagraph(lastIndex)
                }
                if startTTSWhenReady {
                    startTTSWhenReady = false
                    startTTSPlayback()
                }
            }
        }
        .onChange(of: ttsManager.currentBlockIndex) { _, newIndex in
            guard isCurrentSpeech else { return }
            if let newIndex = newIndex {
                if speechScrubTime == nil { ttsBridge.setActiveWord(ttsManager.currentWord) }
                
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
        .onChange(of: isCurrentSpeech) { _, isSpeaking in
            ttsBridge.setSpeechMode(isSpeaking)
            if isSpeaking {
                isPreparingTTS = false
                ttsBridge.setActiveWord(displayedSpeechWord)
            } else {
                speechScrubTime = nil
                ttsBridge.clearActive()
            }
        }
        .onChange(of: ttsManager.errorMessage) { _, error in
            if error != nil {
                isPreparingTTS = false
            }
        }
        .alert("Narration", isPresented: Binding(get: { ttsManager.errorMessage != nil }, set: { if !$0 { ttsManager.errorMessage = nil } })) {
            Button("OK", role: .cancel) { ttsManager.errorMessage = nil }
        } message: { Text(ttsManager.errorMessage ?? "") }
        .onReceive(ttsBridge.paragraphScrollPublisher) { index in
            // Only update progress when TTS is not active (TTS updates it automatically)
            guard !isCurrentSpeech else { return }
            if let chapter = currentChapter {
                chapter.lastReadParagraphIndex = index
                try? modelContext.save()
            }
        }
        .onAppear {
            FocusModeManager.shared.updateFocusStatus()
        }
        .onReceive(ttsBridge.wordTapPublisher) { position in
            guard isCurrentSpeech else { return }
            ttsManager.seek(paragraph: position.paragraphIndex, offset: position.offset)
            ttsManager.resume()
            ttsBridge.resumeFollowing()
        }
        .onChange(of: ttsManager.currentWord) { _, word in
            guard isCurrentSpeech, speechScrubTime == nil else { return }
            ttsBridge.setActiveWord(word)
        }
        .onChange(of: ttsManager.manifest?.id) { _, _ in
            guard let manifest = ttsManager.manifest, manifest.bookId == audioBookId else { return }
            if currentChapterPath != manifest.chapterId || displayedAudioRevision != manifest.contentRevision {
                currentChapterPath = manifest.chapterId; currentChapterName = manifest.title; isLoading = true
                Task { await loadChapter() }
            }
        }
        .sheet(isPresented: $showAudioDownloads) {
            BookAudioDownloadsView(bookId: audioBookId, bookTitle: fetchNovel()?.name ?? currentChapterName,
                pluginId: pluginId, novelPath: novelPath ?? "",
                chapters: audioChapterChoices, coverURL: fetchNovel()?.cover, initialChapter: currentChapterPath)
        }
        .confirmationDialog("Playback speed", isPresented: $showSpeedPicker) {
            ForEach([0.75, 1, 1.25, 1.5, 1.75, 2, 2.5], id: \.self) { speed in
                Button(String(format: "%.2gx", speed)) { updateSpeed(speed) }
            }
        }
        .confirmationDialog("Sleep timer", isPresented: $showSleepPicker) {
            ForEach([15, 30, 60], id: \.self) { minutes in Button("\(minutes) minutes") { ttsManager.setSleep(minutes: minutes) } }
            Button("End of chapter") { ttsManager.sleepAfterChapter() }
            Button("Off") { ttsManager.setSleep(minutes: nil) }
        }
        .onDisappear { commentsTask?.cancel() }
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
        let loadID = UUID(); chapterLoadID = loadID
        let requestedPath = currentChapterPath
        errorMessage = nil
        ttsBridge.contentDidChange()
        displayedAudioRevision = nil
        if cachedChapters.isEmpty, let novelPath {
            let predicate = #Predicate<Chapter> { $0.novel?.path == novelPath && $0.novel?.pluginId == pluginId }
            var descriptor = FetchDescriptor<Chapter>(predicate: predicate, sortBy: [SortDescriptor(\.position)])
            descriptor.relationshipKeyPathsForPrefetching = []
            if let fetched = try? modelContext.fetch(descriptor) {
                self.cachedChapters = fetched
            }
        }
        if let manifest = ttsManager.manifest, manifest.bookId == audioBookId, manifest.chapterId == currentChapterPath {
            htmlContent = TTSBookIdentity.html(blocks: manifest.blocks)
            displayedAudioRevision = manifest.contentRevision
            baseURL = nil; isLoading = false
            return
        }
        let selected = audioLibrary.selectedVoice(bookId: audioBookId, chapterId: currentChapterPath)
        if let local = audioLibrary.downloaded(bookId: audioBookId, chapterId: currentChapterPath, voiceId: selected) ?? audioLibrary.downloaded(bookId: audioBookId, chapterId: currentChapterPath),
           let manifest = try? audioLibrary.localManifest(local.id) {
            htmlContent = TTSBookIdentity.html(blocks: manifest.blocks)
            displayedAudioRevision = manifest.contentRevision
            baseURL = nil; isLoading = false
            return
        }
        if let local = audioLibrary.localText(bookId: audioBookId, chapterId: currentChapterPath) {
            htmlContent = TTSBookIdentity.html(blocks: local.blocks)
            displayedAudioRevision = local.contentRevision
            baseURL = nil; isLoading = false
            return
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
            let parsed = try await source.parseChapter(path: requestedPath)
            guard chapterLoadID == loadID, currentChapterPath == requestedPath else { return }
            htmlContent = parsed
            baseURL = nil
            isLoading = false

            // Record reading history
            if let novel = fetchNovel(),
               let chapter = cachedChapters.first(where: { $0.path == currentChapterPath }) {
                libraryManager.recordHistory(novel: novel, chapter: chapter, context: modelContext)
            }
            
            // Fetch NovelFire / NovelPhoenix comments asynchronously
            if commentSite != nil {
                loadNovelFireComments()
            }
        } catch {
            guard chapterLoadID == loadID else { return }
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
    
    private func loadNovelFireComments() {
        guard let site = commentSite else { return }
        // Cancel any in-flight fetch from a previous chapter so a slow
        // response can't overwrite the current chapter's comments.
        commentsTask?.cancel()
        self.novelfirePostId = ""
        self.novelfireChapterId = ""
        self.novelfireCsrfToken = ""
        self.commentsHtml = ""
        self.nextCursor = nil
        self.hasMoreComments = false

        commentsTask = Task {
            do {
                let meta = try await NovelFireCommentsService.shared.fetchChapterMetadata(chapterPath: currentChapterPath, site: site)
                guard !Task.isCancelled else { return }
                self.novelfirePostId = meta.postId
                self.novelfireChapterId = meta.chapterId
                self.novelfireCsrfToken = meta.csrfToken

                let response = try await NovelFireCommentsService.shared.fetchComments(postId: meta.postId, chapterId: meta.chapterId, site: site)
                guard !Task.isCancelled else { return }
                self.commentsHtml = response.html
                self.nextCursor = response.next_cursor
                self.hasMoreComments = response.has_more_pages
            } catch is CancellationError {
                // Superseded by a newer chapter — ignore.
            } catch {
                #if DEBUG
                print("⚠️ Failed to load \(site.displayName) comments: \(error.localizedDescription)")
                #endif
            }
        }
    }

    private func loadMoreComments() {
        guard let site = commentSite,
              !novelfirePostId.isEmpty && !novelfireChapterId.isEmpty,
              let cursor = nextCursor else { return }
        Task {
            do {
                let response = try await NovelFireCommentsService.shared.fetchComments(
                    postId: novelfirePostId,
                    chapterId: novelfireChapterId,
                    cursor: cursor,
                    site: site
                )
                self.commentsHtml += response.html
                self.nextCursor = response.next_cursor
                self.hasMoreComments = response.has_more_pages

                // Append comments via JS to prevent losing scroll position.
                // JSON-encode the fragment so quotes/newlines/emoji survive.
                let encoded: String = {
                    if let data = try? JSONEncoder().encode(response.html),
                       let s = String(data: data, encoding: .utf8) { return s }
                    return "\"\""
                }()
                let js = "window.appendComments(\(encoded), \(response.has_more_pages ? "true" : "false"));"
                _ = try? await ttsBridge.webView?.evaluateJavaScript(js)
            } catch {
                #if DEBUG
                print("⚠️ Failed to load more comments: \(error)")
                #endif
            }
        }
    }

    private func handleLikeComment(commentId: String) {
        handleCommentAction(commentId: commentId, isLike: true)
    }

    private func handleDislikeComment(commentId: String) {
        handleCommentAction(commentId: commentId, isLike: false)
    }

    private func handleCommentAction(commentId: String, isLike: Bool) {
        guard let site = commentSite else { return }
        if !NovelFireCommentsService.shared.hasSession(for: site) {
            self.showLoginSheet = true
            return
        }

        let csrf = self.novelfireCsrfToken
        let referer = site.referer(chapterPath: currentChapterPath)

        Task {
            do {
                let response: NovelFireCommentsService.ActionResponse
                if isLike {
                    response = try await NovelFireCommentsService.shared.likeComment(commentId: commentId, csrfToken: csrf, referer: referer, site: site)
                } else {
                    response = try await NovelFireCommentsService.shared.dislikeComment(commentId: commentId, csrfToken: csrf, referer: referer, site: site)
                }

                // Success! Update WebView UI
                let js = "window.updateCommentLikes(\"\(commentId)\", \(response.likes), \(response.dislikes), \(isLike ? "true" : "false"));"
                _ = try? await ttsBridge.webView?.evaluateJavaScript(js)
            } catch {
                #if DEBUG
                print("⚠️ Comment action failed: \(error)")
                #endif
                if (error as NSError).code == 419 {
                    do {
                        let meta = try await NovelFireCommentsService.shared.fetchChapterMetadata(chapterPath: currentChapterPath, site: site, forceRefresh: true)
                        self.novelfireCsrfToken = meta.csrfToken
                        let js = "alert('Session refreshed. Please try liking/disliking again.');"
                        _ = try? await ttsBridge.webView?.evaluateJavaScript(js)
                    } catch {
                        #if DEBUG
                        print("⚠️ Failed to refresh CSRF token: \(error)")
                        #endif
                    }
                }
            }
        }
    }

    private var audioBookId: String { TTSBookIdentity.make(pluginId: pluginId, novelPath: novelPath ?? currentChapterPath) }
    private var isCurrentSpeech: Bool {
        ttsManager.isSpeaking && ttsManager.manifest?.bookId == audioBookId && ttsManager.manifest?.chapterId == currentChapterPath
    }
    private var audioChapterChoices: [TTSChapterChoice] {
        if cachedChapters.isEmpty { return [.init(path: currentChapterPath, title: currentChapterName, position: 0)] }
        return cachedChapters.map { .init(path: $0.path, title: $0.name, position: $0.position) }
    }
    private func toggleTTSPlayback() {
        if isCurrentSpeech { ttsManager.togglePause() } else { startTTSPlayback() }
    }
    private func startTTSPlayback(from startIndex: Int? = nil) {
        let voice = audioLibrary.selectedVoice(bookId: audioBookId, chapterId: currentChapterPath)
        guard let record = audioLibrary.downloaded(bookId: audioBookId, chapterId: currentChapterPath, voiceId: voice) ?? audioLibrary.downloads(bookId: audioBookId, chapterId: currentChapterPath).first(where: { $0.rendition.voiceId == voice && $0.rendition.completedChunks > 0 }) else {
            showAudioDownloads = true
            return
        }
        ttsManager.attachCover(url: fetchNovel()?.cover, bookId: audioBookId)
        if record.isAvailable { ttsManager.play(renditionID: record.id, paragraph: startIndex) }
        else { ttsManager.playAvailable(record) }
        ttsBridge.setSpeechMode(true)
        ttsBridge.resumeFollowing()
        isPreparingTTS = false
    }
    private func stopTTSPlayback() {
        ttsManager.stop(); ttsBridge.setSpeechMode(false); ttsBridge.clearActive()
    }
    private func updateSpeed(_ newSpeed: Double) { ttsSpeed = newSpeed; ttsManager.setRate(newSpeed) }
    private var displayedSpeechWord: TTSWordTiming? {
        if let speechScrubTime { return ttsManager.manifest?.word(at: speechScrubTime) }
        return ttsManager.currentWord
    }
    private var ttsControlsOverlay: some View {
        TTSPlaybackControls(
            isPlaying: !ttsManager.isPaused, isBuffering: ttsManager.isBuffering,
            elapsed: ttsManager.elapsed, duration: ttsManager.duration, rate: ttsManager.rate,
            voiceId: ttsManager.manifest?.voiceId ?? ttsVoiceId,
            voiceName: ttsManager.manifest?.voiceName ?? "Qwen",
            isFollowing: ttsBridge.isFollowing, sleepTimerLabel: ttsManager.sleepTimerLabel, playbackStatus: ttsManager.playbackStatus,
            onSettings: { showSettings = true },
            onPlayPause: { ttsManager.togglePause() }, onSkipBack: { ttsManager.skip(-15) },
            onSkipForward: { ttsManager.skip(30) }, onRate: { showSpeedPicker = true },
            onVoice: { showAudioDownloads = true },
            onBookmark: { if let chapter = currentChapter { chapter.bookmark.toggle(); try? modelContext.save() } },
            onSleep: { showSleepPicker = true },
            onFollow: { ttsBridge.resumeFollowing() },
            onSeek: { ttsManager.seek(to: $0); ttsBridge.resumeFollowing() },
            onScrub: { time in
                let wasScrubbing = speechScrubTime != nil
                speechScrubTime = time
                if time != nil && !wasScrubbing { ttsBridge.resumeFollowing() }
                ttsBridge.setActiveWord(displayedSpeechWord)
            }
        )
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
