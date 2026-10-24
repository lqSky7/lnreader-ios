// PagePrerender.swift - Decode pages before they are on screen.

import SwiftUI

/// Decodes pages ahead of the reader into `PageImageCache`, so a page that
/// scrolls into view is already a bitmap with a known height. The strip calls
/// this from its collection view's prefetching.
enum PagePrerender {

    @MainActor private static var tasks: [String: Task<Void, Never>] = [:]

    /// Start decoding these pages, skipping any already decoded or in progress.
    @MainActor
    static func prime(
        _ pages: [SourcePage],
        sourceKey: String,
        loader: PageLoader,
        targetWidth: CGFloat,
        screenScale: CGFloat
    ) {
        for page in pages {
            let url = page.url
            if tasks[url] != nil || PageImageCache.shared.object(forKey: url as NSString) != nil { continue }
            tasks[url] = Task { @MainActor in
                defer { tasks[url] = nil }
                guard let data = try? await loader.image(for: page, sourceKey: sourceKey),
                      !Task.isCancelled else { return }
                PageImageCache.noteRatio(from: data, forKey: url)
                guard let decoded = await PageDecode.decode(data, targetWidth: targetWidth, screenScale: screenScale),
                      !Task.isCancelled else { return }
                PageImageCache.store(decoded, forKey: url)
            }
        }
    }
}
