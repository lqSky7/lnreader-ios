import SwiftUI

// MARK: - Geometry State

/// Tracks the current scroll offset for the flexible header.
///
/// Injected into the environment by ``FlexibleHeaderScrollViewModifier``
/// and consumed by ``FlexibleHeaderContentModifier``.
@Observable
private class FlexibleHeaderGeometry {
    var offset: CGFloat = 0
}

// MARK: - Content Modifier

/// Resizes and repositions the header image based on scroll offset,
/// creating a parallax / stretchy-header effect.
///
/// The target height is derived from half the window height minus the
/// current scroll offset, so pulling down past the top stretches the
/// image while scrolling up shrinks it.
private struct FlexibleHeaderContentModifier: ViewModifier {
    @Environment(\.windowSize) private var windowSize
    @Environment(FlexibleHeaderGeometry.self) private var geometry

    func body(content: Content) -> some View {
        let height = (windowSize.height / 2) - geometry.offset
        content
            .frame(height: height)
            .padding(.bottom, geometry.offset)
            .offset(y: geometry.offset)
    }
}

// MARK: - ScrollView Modifier

/// Observes scroll-geometry changes and feeds the offset into
/// ``FlexibleHeaderGeometry`` so child views can react.
private struct FlexibleHeaderScrollViewModifier: ViewModifier {
    @State private var geometry = FlexibleHeaderGeometry()

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { proxy in
                min(proxy.contentOffset.y + proxy.contentInsets.top, 0)
            } action: { _, offset in
                geometry.offset = offset
            }
            .environment(geometry)
    }
}

// MARK: - View Extensions

extension ScrollView {
    /// Enables flexible-header tracking on this scroll view.
    ///
    /// Pair with ``View/flexibleHeaderContent()`` on the hero image inside
    /// the scroll view to get a stretchy parallax header.
    @MainActor
    func flexibleHeaderScrollView() -> some View {
        modifier(FlexibleHeaderScrollViewModifier())
    }
}

extension View {
    /// Marks this view as the flexible-header hero content.
    ///
    /// The view's height will stretch when the user over-scrolls and
    /// compress as they scroll down. Must be inside a scroll view
    /// modified with ``ScrollView/flexibleHeaderScrollView()``.
    func flexibleHeaderContent() -> some View {
        modifier(FlexibleHeaderContentModifier())
    }
}

// MARK: - Window Size Environment Key

/// Environment key that provides the current window size.
///
/// Set at the app root via `onGeometryChange(for: CGSize.self)`.
private struct WindowSizeKey: EnvironmentKey {
    static let defaultValue: CGSize = CGSize(width: 393, height: 852) // iPhone 15 default
}

extension EnvironmentValues {
    /// The current window size, set at the app level.
    var windowSize: CGSize {
        get { self[WindowSizeKey.self] }
        set { self[WindowSizeKey.self] = newValue }
    }
}
