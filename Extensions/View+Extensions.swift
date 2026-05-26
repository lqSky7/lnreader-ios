import SwiftUI

extension View {

    // MARK: - Scroll View

    /// Removes the UIScrollView content-touch delay for the nearest ancestor scroll view.
    /// Without this, iOS waits ~150 ms before passing a touch to subviews while it
    /// decides whether the gesture is a scroll — making long-press feel sluggish.
    func immediateScrollTouches() -> some View {
        #if os(iOS)
            return background(ImmediateScrollTouchesHelper())
        #else
            return self
        #endif
    }

    // MARK: - Keyboard

    /// Dismisses the software keyboard.
    func hideKeyboard() {
        #if os(iOS)
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil, from: nil, for: nil
            )
        #endif
    }

    // MARK: - Conditional Modifier

    /// Applies `transform` only when `condition` is `true`.
    ///
    /// ```swift
    /// Text("Hello")
    ///     .if(isHighlighted) { $0.foregroundStyle(.yellow) }
    /// ```
    @ViewBuilder
    func `if`<Content: View>(
        _ condition: Bool,
        transform: (Self) -> Content
    ) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }

    // MARK: - Platform Helpers

    /// `true` when running on iPhone (not iPad).
    @MainActor
    var isPhone: Bool {
        #if os(iOS)
            UIDevice.current.userInterfaceIdiom == .phone
        #else
            false
        #endif
    }

    /// `true` when running on iPad.
    @MainActor
    var isPad: Bool {
        #if os(iOS)
            UIDevice.current.userInterfaceIdiom == .pad
        #else
            false
        #endif
    }
}

// MARK: - ImmediateScrollTouchesHelper

#if os(iOS)
    import UIKit

    /// Walks up the UIKit view hierarchy from its anchor point and disables
    /// `delaysContentTouches` on the first `UIScrollView` it finds.
    /// Placed as a `.background()` on a SwiftUI `ScrollView`, this makes
    /// gesture recognisers on cells respond immediately instead of waiting
    /// for the scroll view's 150 ms touch-delay heuristic.
    private struct ImmediateScrollTouchesHelper: UIViewRepresentable {
        func makeUIView(context: Context) -> UIView { UIView() }

        func updateUIView(_ uiView: UIView, context: Context) {
            // Defer one run-loop so the view hierarchy is fully assembled.
            DispatchQueue.main.async {
                var ancestor: UIView? = uiView.superview
                while let view = ancestor {
                    if let scrollView = view as? UIScrollView {
                        scrollView.delaysContentTouches = false
                        return
                    }
                    ancestor = view.superview
                }
            }
        }
    }
#endif
