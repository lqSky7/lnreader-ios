// SourceCard.swift
// Row view for a single source plugin in the browse list.
//
// Installed rows are plain navigation rows (delete lives in a swipe action);
// available rows end in a "Get" capsule, the App Store idiom for install.

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
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "globe")
                            .foregroundStyle(.secondary)
                    }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(plugin.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)

                Text("\(plugin.lang) · v\(plugin.version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if !isInstalled {
                Spacer(minLength: 8)
                getControl
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var getControl: some View {
        if isInstalling {
            ProgressView()
                .controlSize(.regular)
        } else {
            Button("Get", action: action)
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .controlSize(.regular)
            .accessibilityLabel("Install \(plugin.name)")
        }
    }
}
