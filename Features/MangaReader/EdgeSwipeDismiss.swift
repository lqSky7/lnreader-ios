// EdgeSwipeDismiss.swift - Swipe in from a screen edge to leave the reader.

import SwiftUI
import UIKit

/// Calls `onSwipe` when the user swipes in from a screen edge: right from the
/// left edge (the standard iOS back gesture), or left from the right edge.
///
/// A screen-edge pan recognizer rather than a SwiftUI `DragGesture` on the
/// reader: a drag gesture over the whole strip joins the scroll view's gesture
/// arbitration for every touch, to serve a swipe that only starts in a 36 pt
/// margin. The edge recognizer only ever begins at the edge, so the strip's own
/// scrolling is never in its way.
struct EdgeSwipeDismiss: UIViewRepresentable {
    var edges: [UIRectEdge] = [.left, .right]
    let onSwipe: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> HostView {
        let view = HostView()
        view.isUserInteractionEnabled = false
        context.coordinator.edges = edges
        view.onWindow = { [weak coordinator = context.coordinator] window in
            coordinator?.install(on: window)
        }
        return view
    }

    func updateUIView(_ uiView: HostView, context: Context) {
        context.coordinator.onSwipe = onSwipe
    }

    static func dismantleUIView(_ uiView: HostView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class HostView: UIView {
        var onWindow: ((UIWindow?) -> Void)?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            onWindow?(window)
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onSwipe: (() -> Void)?
        var edges: [UIRectEdge] = [.left, .right]
        private var recognizers: [UIScreenEdgePanGestureRecognizer] = []
        private weak var window: UIWindow?

        func install(on window: UIWindow?) {
            uninstall()
            guard let window else { return }
            for edge in edges {
                let recognizer = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(panned(_:)))
                recognizer.edges = edge
                recognizer.delegate = self
                window.addGestureRecognizer(recognizer)
                recognizers.append(recognizer)
            }
            self.window = window
        }

        func uninstall() {
            for recognizer in recognizers { window?.removeGestureRecognizer(recognizer) }
            recognizers = []
            window = nil
        }

        @objc private func panned(_ gesture: UIScreenEdgePanGestureRecognizer) {
            guard gesture.state == .ended else { return }
            let translation = gesture.translation(in: gesture.view)
            // Inward from the edge, mostly horizontal, and far enough to be deliberate.
            let inward = gesture.edges == .left ? translation.x : -translation.x
            guard inward > 100, abs(translation.x) > abs(translation.y) * 1.5 else { return }
            onSwipe?()
        }

        nonisolated func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { true }
    }
}
