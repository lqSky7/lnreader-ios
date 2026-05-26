import SwiftUI

// MARK: - App Theme

/// Semantic color tokens for the LNReader app.
///
/// Use these instead of raw `Color` literals so the palette can be
/// updated in a single place.
enum AppTheme {

    // MARK: Accent Colors

    /// Primary accent — grey.
    static let accent = Color(hue: 0.0, saturation: 0.0, brightness: 0.60)

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
