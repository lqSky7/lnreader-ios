// LoadingView.swift
// Branded loading indicator with optional message.

import SwiftUI

/// A centered loading spinner with an optional descriptive message.
struct LoadingView: View {
    var message: String? = nil

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
                .tint(AppTheme.accent)

            if let message {
                Text(message)
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    LoadingView(message: "Loading chapters...")
}
