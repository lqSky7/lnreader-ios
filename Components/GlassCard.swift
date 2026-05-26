// GlassCard.swift
// Reusable glass card container for floating UI elements.

import SwiftUI

/// A reusable container that wraps content in a Liquid Glass card effect.
/// Use only for controls and navigation elements — never for content.
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = LayoutConstants.glassCornerRadius
    var tint: Color? = nil
    var interactive: Bool = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding()
            .background(glassBackground)
            .overlay(glassStroke)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var glassBackground: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill((tint ?? .clear).opacity(0.18))
            )
    }

    private var glassStroke: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(.white.opacity(interactive ? 0.3 : 0.18), lineWidth: 1)
    }
}

#Preview {
    VStack(spacing: 16) {
        GlassCard {
            Label("Default Glass Card", systemImage: "sparkles")
        }

        GlassCard(tint: .blue) {
            Label("Tinted Glass Card", systemImage: "paintbrush")
        }
    }
    .padding()
}
