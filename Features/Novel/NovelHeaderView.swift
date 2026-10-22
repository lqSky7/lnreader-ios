// NovelHeaderView.swift
// Hero header with cover, background extension effect, and glass action buttons.

import SwiftUI
import Glur

struct NovelHeaderView: View {
    var transitionNamespace: Namespace.ID? = nil
    let name: String
    let author: String?
    let cover: String?
    let status: EntryStatus
    let inLibrary: Bool
    /// True while the entry is being written to the store. The button shows a
    /// spinner and refuses taps instead of silently doing the work twice.
    var isAddingToLibrary: Bool = false
    let onToggleLibrary: () -> Void
    var hasStartedReading: Bool = true
    /// False until there is a chapter to open. The button used to look enabled
    /// and do nothing when tapped.
    var canStartReading: Bool = true
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
        .frame(height: 660)
    }

    // MARK: - Hero Background

    @ViewBuilder
    private var heroBackground: some View {
        Group {
            if let cover, let url = URL(string: cover) {
                CustomAsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(
                            minWidth: 0, maxWidth: .infinity,
                            minHeight: 0, maxHeight: .infinity
                        )
                        .clipped()
                        .backgroundExtensionEffect()
                } placeholder: {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [Color.primary.opacity(0.12), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            } else {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.primary.opacity(0.12), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        }
        .glur(radius: 20.0, offset: 0.75, interpolation: 0.25, direction: .down)
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
                HStack(spacing: 12) {
                    Button(action: onContinueReading) {
                        Label(hasStartedReading ? "Continue" : "Start Reading", systemImage: "book.fill")
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .foregroundStyle(.black)
                            .background(.white, in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canStartReading)
                    .opacity(canStartReading ? 1 : 0.45)
                    .glassEffectID("continue", in: namespace)
                    .bookTransitionSource("continue", in: transitionNamespace)

                    Button(action: onToggleLibrary) {
                        HStack(spacing: 6) {
                            if isAddingToLibrary {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(.black)
                            } else {
                                Image(systemName: inLibrary ? "checkmark.circle.fill" : "plus.circle")
                            }
                            Text(libraryButtonTitle)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(.black)
                        .background(.white, in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .disabled(isAddingToLibrary)
                    .glassEffectID("library", in: namespace)
                }
            }
            .contentShape(.rect)
            // Tapping "Add" now answers immediately: the label changes to a
            // spinner, then to "In Library" with a spring, and the change is
            // acknowledged by a haptic.
            .animation(.spring(response: 0.32, dampingFraction: 0.8), value: inLibrary)
            .animation(.easeInOut(duration: 0.18), value: isAddingToLibrary)
            .sensoryFeedback(.success, trigger: inLibrary)
        }
        .padding()
        .padding(.bottom, 8)
    }

    private var libraryButtonTitle: String {
        if isAddingToLibrary { return "Adding…" }
        return inLibrary ? "In Library" : "Add to Library"
    }
}
