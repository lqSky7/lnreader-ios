// BadgeView.swift
// Small count badge for unread chapters and download indicators.

import SwiftUI

/// A small pill badge showing a numeric count, typically overlaid on novel covers.
struct BadgeView: View {
    let count: Int
    var style: BadgeStyle = .accent

    enum BadgeStyle {
        case accent
        case secondary

        var color: Color {
            switch self {
            case .accent: AppTheme.accent
            case .secondary: .secondary
            }
        }
    }

    var body: some View {
        Text("\(count)")
            .font(Typography.small)
            .fontWeight(.bold)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(style.color, in: .capsule)
    }
}

/// An icon badge for download status or bookmarks.
struct IconBadge: View {
    let icon: String
    var color: Color = .secondary

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .padding(4)
            .background(color, in: .circle)
    }
}

#Preview {
    HStack(spacing: 12) {
        BadgeView(count: 5)
        BadgeView(count: 42, style: .secondary)
        IconBadge(icon: "arrow.down", color: AppTheme.accent)
    }
    .padding()
}
