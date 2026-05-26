// SourceCard.swift
// Row view for a single source plugin in the browse list.

import SwiftUI

struct SourceCard: View {
    let plugin: PluginListItem
    let isInstalled: Bool
    let action: () -> Void

    @Environment(PluginManager.self) private var pluginManager

    private var isInstalling: Bool {
        pluginManager.installingPluginIDs.contains(plugin.id)
    }

    var body: some View {
        HStack(spacing: 12) {
            CustomAsyncImage(url: URL(string: plugin.iconUrl)) { image in
                image.resizable().aspectRatio(contentMode: .fit)
            } placeholder: {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "globe")
                            .foregroundStyle(.secondary)
                    }
            }
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(plugin.name)
                    .font(Typography.headline)

                Text(plugin.lang)
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("v\(plugin.version)")
                .font(Typography.small)
                .foregroundStyle(.tertiary)

            if isInstalling {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button(action: action) {
                    Image(systemName: isInstalled ? "trash" : "arrow.down.circle")
                        .foregroundStyle(
                            isInstalled ? AppTheme.destructive : AppTheme.accent
                        )
                }
                .buttonStyle(.glass)
                #if os(macOS)
                .tint(.clear)
                #endif
            }
        }
    }
}
