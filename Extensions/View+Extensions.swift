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

    /// Steps through `options` on a clearly horizontal swipe.
    ///
    /// Replaces a page-style `TabView` nested inside the app's tab bar: that
    /// built every page up front, re-evaluated all of them on any state change,
    /// and fought the scroll view for the gesture. This renders one page and
    /// only reacts when a drag ends, so vertical scrolling is never touched.
    /// Whatever changes `selection` (swipe or segmented control) gets the same
    /// animated page change.
    func horizontalSwipe(
        selection: Binding<String>,
        options: [String],
        isEnabled: Bool = true
    ) -> some View {
        modifier(HorizontalSwipePager(selection: selection, options: options, isEnabled: isEnabled))
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

/// Cross-fades between pages as `selection` changes, drifting slightly in the
/// direction of travel so a swipe reads as movement instead of a cut.
private struct HorizontalSwipePager: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selection: String
    let options: [String]
    let isEnabled: Bool
    @State private var travel: CGFloat = 1

    func body(content: Content) -> some View {
        ZStack {
            content
                .id(selection)
                .transition(reduceMotion ? .opacity : .asymmetric(
                    insertion: .opacity.combined(with: .offset(x: 28 * travel)),
                    removal: .opacity.combined(with: .offset(x: -28 * travel))
                ))
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: selection)
        .onChange(of: selection) { old, new in
            guard let from = options.firstIndex(of: old), let to = options.firstIndex(of: new) else { return }
            travel = to > from ? 1 : -1
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    guard isEnabled,
                          abs(value.translation.width) > 80,
                          abs(value.translation.width) > abs(value.translation.height) * 2,
                          let current = options.firstIndex(of: selection) else { return }
                    let next = current + (value.translation.width < 0 ? 1 : -1)
                    guard options.indices.contains(next) else { return }
                    selection = options[next]
                }
        )
    }
}
