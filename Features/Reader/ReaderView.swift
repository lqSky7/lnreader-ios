// ReaderView.swift
// Full-screen chapter reader with tap-to-toggle controls.

import SwiftUI

struct ReaderView: View {
    let chapterPath: String
    let chapterName: String
    let pluginId: String
    let novel: Novel?

    @Environment(PluginManager.self) private var pluginManager
    @Environment(\.dismiss) private var dismiss

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

    var body: some View {
        ZStack {
            // Background
            AppTheme.readerBackground.ignoresSafeArea()

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
                    horizontalPadding: horizontalPadding
                )
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showControls.toggle()
                    }
                }
            }

            // Overlay controls
            if showControls {
                ReaderToolbar(
                    chapterName: chapterName,
                    onDismiss: { dismiss() },
                    onSettings: { showSettings = true },
                    onPreviousChapter: {}, // TODO: implement
                    onNextChapter: {}      // TODO: implement
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
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
                horizontalPadding: $horizontalPadding
            )
            .presentationDetents([.medium, .large])
        }
        .task { await loadChapter() }
    }

    // MARK: - Data Loading

    private func loadChapter() async {
        guard let source = pluginManager.plugin(for: pluginId) else {
            errorMessage = "Source plugin not found."
            isLoading = false
            return
        }

        do {
            htmlContent = try await source.parseChapter(path: chapterPath)
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}
