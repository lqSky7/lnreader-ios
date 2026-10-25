// MangaZoom.swift - Pinch and button zoom for the manga reader.
//
// One zoom for both layouts: the whole reader content is scaled, so the pager
// and the webtoon strip need no zoom code of their own.

import SwiftUI

/// Scale and pan of the reader content. Pure value logic, kept apart from the gestures.
struct MangaZoomState: Equatable {
    static let minScale: CGFloat = 1
    static let maxScale: CGFloat = 4
    /// One press of a zoom button.
    static let step: CGFloat = 1.5

    var scale: CGFloat = 1
    var offset: CGSize = .zero

    var isZoomed: Bool { scale > 1.01 }
    var canZoomIn: Bool { scale < Self.maxScale - 0.01 }

    /// Offset limit per axis: how far the scaled content overhangs the screen.
    static func limit(for length: CGFloat, scale: CGFloat) -> CGFloat {
        max(0, length * (scale - 1) / 2)
    }

    /// Sets the scale within bounds and pulls the pan back inside the new limits.
    mutating func setScale(_ value: CGFloat, in size: CGSize) {
        scale = min(max(value, Self.minScale), Self.maxScale)
        offset = Self.clamp(offset, scale: scale, in: size)
    }

    mutating func zoom(by factor: CGFloat, in size: CGSize) {
        setScale(scale * factor, in: size)
    }

    /// Zooms so the point under the finger stays put (clamped to the content edges).
    mutating func zoom(to target: CGFloat, at point: CGPoint, in size: CGSize, horizontalOnly: Bool) {
        let clamped = min(max(target, Self.minScale), Self.maxScale)
        let proposed = CGSize(
            width: (size.width / 2 - point.x) * (clamped - 1),
            height: horizontalOnly ? 0 : (size.height / 2 - point.y) * (clamped - 1)
        )
        scale = clamped
        offset = Self.clamp(proposed, scale: clamped, in: size)
    }

    mutating func reset() {
        scale = 1
        offset = .zero
    }

    static func clamp(_ offset: CGSize, scale: CGFloat, in size: CGSize) -> CGSize {
        let x = limit(for: size.width, scale: scale)
        let y = limit(for: size.height, scale: scale)
        return CGSize(width: min(max(offset.width, -x), x), height: min(max(offset.height, -y), y))
    }
}

private struct MangaZoomModifier: ViewModifier {
    @Binding var zoom: MangaZoomState
    let size: CGSize
    /// The webtoon scrolls vertically on its own, so it pans sideways only.
    let horizontalOnly: Bool

    // Captured when a gesture begins, so the zoom buttons can change the zoom between gestures.
    @State private var baseScale: CGFloat?
    @State private var baseOffset: CGSize?

    func body(content: Content) -> some View {
        content
            .scaleEffect(zoom.scale)
            .offset(zoom.offset)
            .simultaneousGesture(pinch)
            .simultaneousGesture(pan)
    }

    private var pinch: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = baseScale ?? zoom.scale
                baseScale = start
                zoom.setScale(start * value.magnification, in: size)
            }
            .onEnded { _ in
                baseScale = nil
            }
    }

    private var pan: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard zoom.isZoomed else { return }
                let start = baseOffset ?? zoom.offset
                baseOffset = start
                let proposed = CGSize(
                    width: start.width + value.translation.width,
                    height: horizontalOnly ? 0 : start.height + value.translation.height
                )
                zoom.offset = MangaZoomState.clamp(proposed, scale: zoom.scale, in: size)
            }
            .onEnded { _ in
                baseOffset = nil
            }
    }
}

extension View {
    /// Pinch to zoom and pan while zoomed. `zoom` is also driven by the reader's zoom buttons.
    func mangaZoom(_ zoom: Binding<MangaZoomState>, in size: CGSize, horizontalOnly: Bool) -> some View {
        modifier(MangaZoomModifier(zoom: zoom, size: size, horizontalOnly: horizontalOnly))
    }
}
