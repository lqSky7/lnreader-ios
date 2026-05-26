// WiggleModifier.swift
// SwiftUI modifier to make views wiggle/jiggle like the iOS home screen.

import SwiftUI

struct WiggleModifier: ViewModifier {
    let isWiggling: Bool

    @State private var isAnimating = false
    // Stored so we can cancel the random-delay task if the view disappears
    // or isWiggling flips before the animation even starts.
    @State private var wiggleTask: Task<Void, Never>? = nil

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(isWiggling ? (isAnimating ? 0.6 : -0.6) : 0))
            .offset(
                x: isWiggling ? (isAnimating ? 0.3 : -0.3) : 0,
                y: isWiggling ? (isAnimating ? -0.3 : 0.3) : 0
            )
            .onAppear {
                if isWiggling { scheduleWiggleStart() }
            }
            .onChange(of: isWiggling) { _, newValue in
                if newValue {
                    scheduleWiggleStart()
                } else {
                    stopWiggle()
                }
            }
            .onDisappear {
                // Cancel any pending delayed start so it doesn't update
                // @State on a view that is no longer in the hierarchy.
                wiggleTask?.cancel()
                wiggleTask = nil
            }
    }

    // MARK: - Private helpers

    private func scheduleWiggleStart() {
        // Guard: if already animating, don't restart — avoids stutter when
        // ForEach re-creates views during drag reorder.
        guard !isAnimating else { return }

        wiggleTask?.cancel()
        // Each item gets a tiny random phase offset so they don't all
        // snap in sync — mirrors the iOS home screen jiggle behaviour.
        wiggleTask = Task { @MainActor in
            let nanoseconds = UInt64(Double.random(in: 0.0...0.08) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            withAnimation(
                Animation.linear(duration: 0.18)
                    .repeatForever(autoreverses: true)
            ) {
                isAnimating = true
            }
        }
    }

    private func stopWiggle() {
        wiggleTask?.cancel()
        wiggleTask = nil
        // Let the item ease back to neutral rather than snapping.
        withAnimation(.easeOut(duration: 0.15)) {
            isAnimating = false
        }
    }
}

extension View {
    /// Applies a wiggling/jiggling animation to the view, mimicking the iOS launcher edit state.
    func wiggle(when isWiggling: Bool) -> some View {
        self.modifier(WiggleModifier(isWiggling: isWiggling))
    }
}
