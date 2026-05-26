import SwiftUI

// MARK: - App Theme

/// Semantic color tokens for the LNReader app.
///
/// Use these instead of raw `Color` literals so the palette can be
/// updated in a single place.
enum AppTheme {

    // MARK: Accent Colors

    /// Primary accent — warm amber/gold.
    static let accent = Color(hue: 0.08, saturation: 0.80, brightness: 0.95)

    /// Secondary accent — soft teal.
    static let secondaryAccent = Color(hue: 0.50, saturation: 0.45, brightness: 0.80)

    // MARK: Reader

    /// Warm, paper-like background for the reader view.
    static let readerBackground = Color(
        light: Color(hue: 0.10, saturation: 0.08, brightness: 0.98),
        dark: Color(hue: 0.10, saturation: 0.05, brightness: 0.12)
    )

    /// Primary text color for the reader view.
    static let readerText = Color(
        light: Color(hue: 0.0, saturation: 0.0, brightness: 0.12),
        dark: Color(hue: 0.0, saturation: 0.0, brightness: 0.90)
    )

    // MARK: Surface & Text

    /// Subtle card background.
    static let cardBackground = Color(
        light: Color(hue: 0.0, saturation: 0.0, brightness: 0.96),
        dark: Color(hue: 0.0, saturation: 0.0, brightness: 0.16)
    )

    /// Secondary / subtitle text.
    static let subtitleText = Color.secondary

    // MARK: Semantic

    /// Destructive action color (delete, remove).
    static let destructive = Color.red
}

// MARK: - Adaptive Color Helper

private extension Color {
    /// Creates a color that adapts between light and dark appearances.
    init(light: Color, dark: Color) {
        #if os(iOS)
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(dark)
                : UIColor(light)
        })
        #elseif os(macOS)
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(dark)
                : NSColor(light)
        })
        #else
        self = light
        #endif
    }
}

// MARK: - Typography

/// Typographic scale for the LNReader app.
///
/// Provides a consistent set of fonts sized for the app's
/// information hierarchy — from large titles down to small captions.
enum Typography {

    /// Extra-large heading — 28pt bold rounded.
    static let largeTitle: Font = .system(size: 28, weight: .bold, design: .rounded)

    /// Section heading — 22pt semibold rounded.
    static let title: Font = .system(size: 22, weight: .semibold, design: .rounded)

    /// Row / card heading — 17pt semibold.
    static let headline: Font = .system(size: 17, weight: .semibold)

    /// Body text — 15pt regular.
    static let body: Font = .system(size: 15)

    /// Captions and metadata — 13pt medium.
    static let caption: Font = .system(size: 13, weight: .medium)

    /// Smallest text — 11pt regular.
    static let small: Font = .system(size: 11)
}
