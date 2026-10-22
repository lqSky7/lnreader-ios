// MangaPageView.swift - One page image, loaded through PageLoader.

import ImageIO
import SwiftUI

/// Decoded page images, kept so scrolling back over a page does not decode it
/// again. `PageLoader` caches the *bytes*; decoding is the expensive half and
/// was being redone every time a page came back into view.
enum PageImageCache {
    static let shared: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        // A handful of pages, byte-accounted: full-page images are large and
        // the webtoon strip only ever needs the neighbourhood.
        cache.countLimit = 8
        cache.totalCostLimit = 120 * 1024 * 1024
        return cache
    }()
}

/// Page decoding. Pages are scaled to the screen's pixel width while decoding:
/// a 1600×2400 page is 15 MB as a bitmap and a webtoon strip can be 40 MB, but
/// the screen never shows more than its own width in pixels.
enum PageDecode {
    static func image(from data: Data, targetWidth: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        var maxPixel = 0
        if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let w = props[kCGImagePropertyPixelWidth] as? CGFloat,
           let h = props[kCGImagePropertyPixelHeight] as? CGFloat, w > 0 {
            let scale = min(1, targetWidth / w)
            maxPixel = Int((max(w, h) * scale).rounded(.up))
        }
        guard maxPixel > 0 else { return UIImage(data: data)?.preparingForDisplay() }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }
}

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

        if let cached = PageImageCache.shared.object(forKey: requestedURL as NSString) {
            image = cached
            loadedURL = requestedURL
            return
        }

        image = nil
        do {
            let data = try await loader.image(for: page, sourceKey: sourceKey)
            // Decode off the main actor and force the decode to happen there:
            // a full page is a few megabytes of compressed data, and decoding
            // it lazily inside the render pass stalls scrolling.
            let targetWidth = await MainActor.run { UIScreen.main.bounds.width * UIScreen.main.scale }
            let decoded = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                PageDecode.image(from: data, targetWidth: targetWidth)
            }.value
            guard !Task.isCancelled else { return }
            guard let decoded else {
                throw HTTPError.transport("Page \(page.index + 1) is not a valid image")
            }
            PageImageCache.shared.setObject(
                decoded,
                forKey: requestedURL as NSString,
                cost: Int(decoded.size.width * decoded.scale * decoded.size.height * decoded.scale * 4)
            )
            image = decoded
            loadedURL = requestedURL
        } catch {
            if !Task.isCancelled {
                didFail = true
            }
        }
    }
}
