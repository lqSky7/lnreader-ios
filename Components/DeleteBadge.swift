// DeleteBadge.swift
// Circular minus badge shown in the corner of novel cards to remove them from library.

import SwiftUI

struct DeleteBadge: View {
    let action: () -> Void

    var body: some View {
        Button(role: .destructive, action: action) {
            Image(systemName: "minus")
                .font(.body.weight(.bold))
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.regular)
        .accessibilityLabel("Remove from library")
    }
}

#Preview {
    ZStack {
        Color.secondary.opacity(0.2).ignoresSafeArea()
        DeleteBadge {}
    }
}
