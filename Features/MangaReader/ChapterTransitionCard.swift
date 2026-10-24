// ChapterTransitionCard.swift - The card shown past the first or last page of a chapter.

import SwiftUI

/// The card between two chapters: what just ended and what comes next.
struct ChapterTransitionCard: View {
    enum Direction { case previous, next }
    let direction: Direction
    let title: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: direction == .next ? "chevron.down.circle" : "chevron.up.circle")
                .font(.system(size: 34, weight: .light))
            Text(direction == .next ? "Next chapter" : "Previous chapter")
                .font(.footnote.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.6))
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
                .lineLimit(3)
            ProgressView().tint(.white).padding(.top, 6)
        }
        .foregroundStyle(.white)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .accessibilityElement(children: .combine)
    }
}
