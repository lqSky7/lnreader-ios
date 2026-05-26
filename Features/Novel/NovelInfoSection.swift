// NovelInfoSection.swift
// Expandable description, genre tags, and metadata grid.

import SwiftUI

struct NovelInfoSection: View {
    let summary: String?
    let genres: [String]
    let author: String?
    let artist: String?
    let status: NovelStatus
    let source: String
    @Binding var showFullDescription: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Description
            if let summary, !summary.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(summary)
                        .font(Typography.body)
                        .lineLimit(showFullDescription ? nil : 4)
                        .foregroundStyle(.secondary)

                    Button(showFullDescription ? "Show Less" : "Show More") {
                        withAnimation { showFullDescription.toggle() }
                    }
                    .font(Typography.caption)
                    .foregroundStyle(AppTheme.accent)
                }
            }

            // Genre tags
            if !genres.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(genres, id: \.self) { genre in
                            Text(genre)
                                .font(Typography.small)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .glassEffect(.regular, in: .capsule)
                        }
                    }
                }
            }

            // Metadata grid
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 8
            ) {
                if let author {
                    MetadataItem(label: "Author", value: author, icon: "person")
                }
                if let artist {
                    MetadataItem(label: "Artist", value: artist, icon: "paintbrush")
                }
                MetadataItem(label: "Status", value: status.displayName, icon: status.iconName)
                MetadataItem(label: "Source", value: source, icon: "globe")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

// MARK: - Metadata Item

struct MetadataItem: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(Typography.caption)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(Typography.small)
                    .foregroundStyle(.tertiary)
                Text(value)
                    .font(Typography.caption)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
