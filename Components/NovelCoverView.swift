// NovelCoverView.swift
// Async image view for novel covers with placeholder and loading states.

import SwiftUI

/// Displays a novel cover image loaded asynchronously with a styled placeholder.
struct NovelCoverView: View {
    let url: String?
    var aspectRatio: CGFloat = LayoutConstants.coverAspectRatio
    var cornerRadius: CGFloat = LayoutConstants.cornerRadius

    var body: some View {
        // `Color.clear` + `aspectRatio` gives a flexible box with a fixed ratio
        // without a `GeometryReader` per cell. A GeometryReader in every grid
        // cell costs a layout pass each and is a known scroll-time drag.
        Color.clear
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay {
                if let urlString = url, let imageURL = URL(string: urlString) {
                    CustomAsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            placeholderView
                        case .empty:
                            shimmerPlaceholder
                        @unknown default:
                            placeholderView
                        }
                    }
                } else {
                    placeholderView
                }
            }
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var placeholderView: some View {
        RoundedRectangle(cornerRadius: 0)
            .fill(Color.secondary.opacity(0.15))
            .overlay {
                Image(systemName: "book.closed.fill")
                    .font(.title2)
                    .foregroundStyle(.quaternary)
            }
    }

    private var shimmerPlaceholder: some View {
        RoundedRectangle(cornerRadius: 0)
            .fill(Color.secondary.opacity(0.1))
            .overlay {
                ProgressView()
                    .tint(.secondary)
            }
    }
}

#Preview {
    HStack {
        NovelCoverView(url: "https://picsum.photos/300/420")
            .frame(width: 120)
        NovelCoverView(url: nil)
            .frame(width: 120)
    }
    .padding()
}
