import SwiftUI

/// Wraps content in a padded Liquid Glass rounded-rect card.
///
/// Use this modifier on floating overlays, info panels, or any
/// small element that should look like a glass surface.
/// **Do not** apply to content areas (lists, text blocks).
struct GlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = LayoutConstants.glassCornerRadius

    func body(content: Content) -> some View {
        content
            .padding()
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 1)
            )
    }
}

extension View {
    /// Wraps the view in a Liquid Glass card.
    ///
    /// - Parameter cornerRadius: Corner radius for the glass shape.
    ///   Defaults to ``LayoutConstants/glassCornerRadius``.
    func glassCard(cornerRadius: CGFloat = LayoutConstants.glassCornerRadius) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius))
    }
}
