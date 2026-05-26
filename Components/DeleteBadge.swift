// DeleteBadge.swift
// Circular minus badge shown in the corner of novel cards to remove them from library.

import SwiftUI

struct DeleteBadge: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "minus.circle.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.red)
                .background(
                    Circle()
                        .fill(Color.white)
                        .padding(2)
                )
                .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        // 44×44 pt minimum touch target — prevents the parent drag gesture
        // from stealing taps on the small icon.
        .frame(width: 44, height: 44)
        .contentShape(Circle())
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.2).ignoresSafeArea()
        DeleteBadge {}
    }
}
