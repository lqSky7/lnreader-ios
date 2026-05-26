// EmptyStateView.swift
// Placeholder view for screens with no content.

import SwiftUI

/// A centered empty state with an SF Symbol, title, and optional subtitle and action.
struct EmptyStateView: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            if let subtitle {
                Text(subtitle)
            }
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.glass)
                    #if os(macOS)
                    .tint(.clear)
                    #endif
            }
        }
    }
}

#Preview {
    EmptyStateView(
        icon: "books.vertical",
        title: "Your Library is Empty",
        subtitle: "Browse sources to find novels.",
        actionTitle: "Browse",
        action: {}
    )
}
