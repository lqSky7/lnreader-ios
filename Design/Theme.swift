import SwiftUI

// MARK: - App Theme

/// Semantic color tokens for the LNReader app.
///
/// Use these instead of raw `Color` literals so the palette can be
/// updated in a single place.
enum AppTheme {

    // MARK: Interactive Palette

    /// Primary interactive color: black in light mode, white in dark mode.
    ///
    /// The interface is deliberately monochrome. Red is *not* the accent — it
    /// is reserved for destructive actions and error states so that it still
    /// means something when it does appear.
    static let accent = Color.primary

    /// Softer interactive tone for secondary controls and metadata actions.
    static let secondaryAccent = Color.secondary

    /// High-contrast fill for a primary control (play button, selected dot).
    static let primaryFill = Color.primary

    /// Track fill for switches. Pure primary would render an enabled switch
    /// white-on-white in dark mode, so dark mode uses a legible mid gray.
    static let controlFill = Color(light: Color(white: 0.12), dark: Color(white: 0.62))

    /// Content drawn on top of `primaryFill`.
    static let onPrimaryFill = Color(light: .white, dark: .black)

    /// Grouped surface for cards and inset rows (systemGray6).
    static let surface = Color(
        light: Color(red: 242 / 255, green: 242 / 255, blue: 247 / 255),
        dark: Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)
    )

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

    /// Subtle card background (systemGray6).
    static let cardBackground = surface

    /// Secondary / subtitle text.
    static let subtitleText = Color.secondary

    // MARK: Semantic

    /// Destructive action color (delete, remove, failed state).
    ///
    /// Red is intentionally rare: use it only where the user must recognize a
    /// destructive or failed outcome, never for decoration or ordinary accents.
    static let destructive = Color.red
}

// MARK: - Adaptive Color Helper

extension Color {
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

    // Every token is a text style, so the scale follows the user's Dynamic Type
    // setting. The point sizes in the comments are the default (Large) sizes.

    /// Extra-large heading — 28pt bold rounded.
    static let largeTitle: Font = .system(.title, design: .rounded, weight: .bold)

    /// Section heading — 22pt semibold rounded.
    static let title: Font = .system(.title2, design: .rounded, weight: .semibold)

    /// Row / card heading — 17pt semibold.
    static let headline: Font = .headline

    /// Body text — 15pt regular.
    static let body: Font = .subheadline

    /// Captions and metadata — 13pt medium.
    static let caption: Font = .footnote.weight(.medium)

    /// Smallest text — 11pt regular.
    static let small: Font = .caption2
}

// MARK: - Hex Color Helper

extension Color {
    /// Initialize Color from a hex string (e.g. "#RRGGBB" or "#RRGGBBAA").
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0

        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r, g, b, a: Double
        if hexSanitized.count == 6 {
            r = Double((rgb & 0xFF0000) >> 16) / 255.0
            g = Double((rgb & 0x00FF00) >> 8) / 255.0
            b = Double(rgb & 0x0000FF) / 255.0
            a = 1.0
        } else if hexSanitized.count == 8 {
            r = Double((rgb & 0xFF000000) >> 24) / 255.0
            g = Double((rgb & 0x00FF0000) >> 16) / 255.0
            b = Double((rgb & 0x0000FF00) >> 8) / 255.0
            a = Double(rgb & 0x000000FF) / 255.0
        } else {
            return nil
        }

        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    /// Converts a Color to its hex string representation (e.g. "#RRGGBB").
    func toHex() -> String? {
        #if os(iOS)
        let uiColor = UIColor(self)
        guard let cgColor = uiColor.cgColor.converted(to: CGColorSpaceCreateDeviceRGB(), intent: .defaultIntent, options: nil),
              let components = cgColor.components,
              components.count >= 3 else {
            return nil
        }
        let red = components[0]
        let green = components[1]
        let blue = components[2]
        let alpha = components.count > 3 ? components[3] : 1.0
        #elseif os(macOS)
        let nsColor = NSColor(self)
        guard let rgbColor = nsColor.usingColorSpace(.deviceRGB) else { return nil }
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        rgbColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #endif
        
        if alpha < 1.0 {
            return String(format: "#%02lX%02lX%02lX%02lX",
                          Int(round(red * 255)),
                          Int(round(green * 255)),
                          Int(round(blue * 255)),
                          Int(round(alpha * 255)))
        } else {
            return String(format: "#%02lX%02lX%02lX",
                          Int(round(red * 255)),
                          Int(round(green * 255)),
                          Int(round(blue * 255)))
        }
    }
}

// Native navigation keeps the source view alive for the interactive return zoom.
extension View {
    @ViewBuilder func bookTransitionSource<ID: Hashable>(_ id: ID, in namespace: Namespace.ID?) -> some View {
        #if os(iOS)
        if let namespace { self.matchedTransitionSource(id: id, in: namespace) } else { self }
        #else
        self
        #endif
    }
    func bookZoom<ID: Hashable>(from id: ID, in namespace: Namespace.ID) -> some View {
        modifier(BookZoomTransition(sourceID: id, namespace: namespace))
    }
}
private struct BookZoomTransition<ID: Hashable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let sourceID: ID
    let namespace: Namespace.ID
    @ViewBuilder func body(content: Content) -> some View {
        #if os(iOS)
        if reduceMotion { content } else { content.navigationTransition(.zoom(sourceID: sourceID, in: namespace)) }
        #else
        content
        #endif
    }
}


// MARK: - Ambient Background

/// Slow, touch-reactive light field for full-screen surfaces.
///
/// A blurred mesh gradient: soft, static in feel, and cheap enough to keep behind
/// frosted cards without fighting the content for attention.
struct AuroraBackdrop: View {
    /// Finger position in this view's coordinate space.
    var touch: CGPoint = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let px = Float(min(max(touch.x / 390, 0), 1)) - 0.5
            let py = Float(min(max(touch.y / 800, 0), 1)) - 0.5
            MeshGradient(
                width: 3,
                height: 3,
                points: [
                    SIMD2<Float>(0, 0),
                    SIMD2<Float>(Float(0.5 + 0.03 * sin(t * 0.20)), 0),
                    SIMD2<Float>(1, 0),
                    SIMD2<Float>(0, Float(0.5 + 0.04 * cos(t * 0.16))),
                    SIMD2<Float>(Float(0.5 + 0.07 * sin(t * 0.12)) + px * 0.08,
                                 Float(0.5 + 0.06 * cos(t * 0.18)) + py * 0.08),
                    SIMD2<Float>(1, Float(0.5 + 0.04 * sin(t * 0.21))),
                    SIMD2<Float>(0, 1),
                    SIMD2<Float>(Float(0.5 + 0.03 * cos(t * 0.14)), 1),
                    SIMD2<Float>(1, 1)
                ],
                colors: [
                    .black, Color(white: 0.07), .black,
                    Color(white: 0.10), Color(white: 0.42), Color(white: 0.09),
                    .black, Color(white: 0.05), .black
                ]
            )
            .blur(radius: 40)
        }
        .overlay(Color.black.opacity(0.30))
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

extension View {
    /// Chrome shared by every settings screen: a large sentence-case title and
    /// the app's control tint, so switches look the same wherever they are.
    func settingsScreen(_ title: String) -> some View {
        self
            .tint(AppTheme.controlFill)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
    }
}
