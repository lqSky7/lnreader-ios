// ReaderView.swift
// Full-screen chapter reader with tap-to-toggle controls.

import SwiftData
import SwiftUI

struct ReaderView: View {
    @Environment(PluginManager.self) private var pluginManager
    @Environment(LibraryManager.self) private var libraryManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var currentChapterPath: String
    @State private var currentChapterName: String
    let pluginId: String
    let novel: Novel?

    @State private var htmlContent = ""
    @State private var isLoading = true
    @State private var showControls = true
    @State private var showSettings = false
    @State private var errorMessage: String?

    // Reader settings persisted across sessions
    @AppStorage("reader.fontSize") private var fontSize: Double = 18
    @AppStorage("reader.lineHeight") private var lineHeight: Double = 1.6
    @AppStorage("reader.fontFamily") private var fontFamily = "Georgia"
    @AppStorage("reader.padding") private var horizontalPadding: Double = 16
    @AppStorage("reader.backgroundColor") private var backgroundColorHex: String = ""
    @AppStorage("reader.textColor") private var textColorHex: String = ""

    init(chapterPath: String, chapterName: String, pluginId: String, novel: Novel?) {
        self._currentChapterPath = State(initialValue: chapterPath)
        self._currentChapterName = State(initialValue: chapterName)
        self.pluginId = pluginId
        self.novel = novel
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
                    onTap: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showControls.toggle()
                        }
                    }
                )
                .ignoresSafeArea(edges: showControls ? .bottom : .all)
            }

            // Overlay controls
            ReaderToolbar(
                chapterName: currentChapterName,
                hasPrevious: hasPreviousChapter,
                hasNext: hasNextChapter,
                onDismiss: { dismiss() },
                onSettings: { showSettings = true },
                onPreviousChapter: navigateToPreviousChapter,
                onNextChapter: navigateToNextChapter
            )
            .opacity(showControls ? 1.0 : 0.0)
            .blur(radius: showControls ? 0.0 : 8.0)
            .scaleEffect(showControls ? 1.0 : 0.96)
            .allowsHitTesting(showControls)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .statusBarHidden(!showControls)
        .sheet(isPresented: $showSettings) {
            ReaderSettings(
                fontSize: $fontSize,
                lineHeight: $lineHeight,
                fontFamily: $fontFamily,
                horizontalPadding: $horizontalPadding,
                backgroundColorHex: $backgroundColorHex,
                textColorHex: $textColorHex
            )
            .presentationDetents([.medium, .large])
        }
        .task { await loadChapter() }
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

    // MARK: - Data Loading

    private func loadChapter() async {
        guard let source = pluginManager.plugin(for: pluginId) else {
            errorMessage = "Source plugin not found."
            isLoading = false
            return
        }

        do {
            htmlContent = try await source.parseChapter(path: currentChapterPath)
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
}
