// NovelHeaderView.swift
// Hero header with cover, background extension effect, and glass action buttons.

import SwiftUI

struct NovelHeaderView: View {
    let name: String
    let author: String?
    let cover: String?
    let status: NovelStatus
    let inLibrary: Bool
    let onToggleLibrary: () -> Void
    let onContinueReading: () -> Void

    @Namespace private var namespace

    var body: some View {
        ZStack(alignment: .bottom) {
            // Hero background with extension effect
            heroBackground

            // Gradient for text legibility over backgroundExtensionEffect
            LinearGradient(
                colors: [.clear, .black.opacity(0.3), .black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )

            // Content overlay
            contentOverlay
        }
        .frame(height: 400)
    }

    // MARK: - Hero Background

    @ViewBuilder
    private var heroBackground: some View {
        if let cover, let url = URL(string: cover) {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(minWidth: 0, maxWidth: .infinity,
                           minHeight: 0, maxHeight: .infinity)
                    .clipped()
                    .backgroundExtensionEffect()
            } placeholder: {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.accent.opacity(0.3), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        } else {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [AppTheme.accent.opacity(0.3), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
    }

    // MARK: - Content Overlay

    private var contentOverlay: some View {
        VStack(alignment: .leading, spacing: 12) {
            Spacer()

            Text(name)
                .font(Typography.largeTitle)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 4, y: 2)

            if let author {
                Text(author)
                    .font(Typography.headline)
                    .foregroundStyle(.white.opacity(0.85))
                    .shadow(radius: 2)
            }

            // Glass action buttons
            GlassEffectContainer(spacing: 12) {
                Button(action: onContinueReading) {
                    Label("Continue Reading", systemImage: "book.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .glassEffectID("continue", in: namespace)

                Button(action: onToggleLibrary) {
                    Label(
                        inLibrary ? "In Library" : "Add to Library",
                        systemImage: inLibrary ? "checkmark.circle.fill" : "plus.circle"
                    )
                }
                .buttonStyle(.glass)
                .glassEffectID("library", in: namespace)
                #if os(macOS)
                .tint(.clear)
                #endif
            }
            .contentShape(.rect)
        }
        .padding()
        .padding(.bottom, 8)
    }
}
