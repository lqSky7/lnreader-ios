// GlassControls.swift
// The one set of floating glass controls. Readers, overlays and sheets build
// their chrome from these instead of hand-rolling `.glassEffect` on a frame.

import SwiftUI

/// A round, icon-only glass button. Sized by `controlSize`, not a fixed frame.
struct GlassIconButton: View {
    let symbol: String
    let label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .accessibilityLabel(label)
    }
}

/// A capsule glass button holding a title and optional symbol.
struct GlassPillButton<Label: View>: View {
    var action: () -> Void
    @ViewBuilder var label: () -> Label

    var body: some View {
        Button(action: action, label: label)
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
    }
}

/// Previous / next as one glass capsule with a system separator between them.
struct GlassStepper: View {
    let backLabel: String
    let forwardLabel: String
    var canGoBack = true
    var canGoForward = true
    var back: () -> Void
    var forward: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            step("chevron.left", label: backLabel, enabled: canGoBack, action: back)
            Rectangle()
                .fill(.separator)
                .frame(width: 1, height: 22)
                .accessibilityHidden(true)
            step("chevron.right", label: forwardLabel, enabled: canGoForward, action: forward)
        }
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private func step(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(label)
    }
}
