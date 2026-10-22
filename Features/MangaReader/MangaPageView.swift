// MangaPageView.swift - One page image, loaded through PageLoader.

import SwiftUI

/// Displays a single page, with its own loading and failure state.
///
/// Each page owns its load task, so a slow page in the middle of a chapter never
/// blocks the ones around it.
struct MangaPageView: View {

    let page: SourcePage
    let sourceKey: String
    let loader: PageLoader
    /// `.fit` in paged mode, `.fill` width in webtoon mode.
    var contentMode: ContentMode = .fit

    @State private var image: UIImage?
    @State private var loadedURL: String?
    @State private var didFail = false
    @State private var attempt = 0

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .frame(maxWidth: .infinity)
            } else if didFail {
                VStack(spacing: 14) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title)
                        .foregroundStyle(.white.opacity(0.7))
                    Text("Page \(page.index + 1) could not be loaded")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                    Button("Retry") {
                        attempt += 1
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                }
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, minHeight: 220)
            }
        }
        // Re-runs when the page changes or the user retries.
        .task(id: "\(page.url)#\(attempt)") {
            await load()
        }
    }

    private func load() async {
        let requestedURL = page.url
        didFail = false
        if image != nil, loadedURL == requestedURL { return }
        image = nil
        do {
            let data = try await loader.image(for: page, sourceKey: sourceKey)
            // Decode off the main actor: a full page is a few megabytes of
            // compressed data and decoding it inline stalls scrolling.
            let decoded = await Task.detached(priority: .userInitiated) {
                UIImage(data: data)
            }.value
            guard !Task.isCancelled else { return }
            guard let decoded else {
                throw HTTPError.transport("Page \(page.index + 1) is not a valid image")
            }
            image = decoded
            loadedURL = requestedURL
        } catch {
            if !Task.isCancelled {
                didFail = true
            }
        }
    }
}
