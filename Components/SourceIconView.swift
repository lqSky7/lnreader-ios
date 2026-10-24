// SourceIconView.swift - A source's icon, remote or bundled.

import SwiftUI

struct SourceIconView: View {

    let source: any CatalogSource
    var size: CGFloat = 34

    var body: some View {
        content
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
    }

    @ViewBuilder
    private var content: some View {
        // Bundled icons are asset-catalog images; installed extensions usually
        // point at a URL from their repository.
        if let asset = source.iconAsset, UIImage(named: asset) != nil {
            Image(asset)
                .resizable()
                .scaledToFit()
        } else if let iconURL = source.iconURL, let url = URL(string: iconURL) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFit()
                } else {
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Image(systemName: source.kind.symbolName)
            .resizable()
            .scaledToFit()
            .fontWeight(.semibold)
            .padding(size * 0.27)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.quaternary)
    }
}
