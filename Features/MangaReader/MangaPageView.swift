// MangaPageView.swift - One page image, loaded through PageLoader.

import ImageIO
import SwiftUI

/// Decoded page images, kept so scrolling back over a page does not decode it
/// again. `PageLoader` caches the *bytes*; decoding is the expensive half and
/// was being redone every time a page came back into view.
enum PageImageCache {
    static let shared: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        // Byte-accounted: full-page images are large and the strip only ever
        // needs the neighbourhood. The count is a backstop, the budget is bytes.
        cache.countLimit = 16
        cache.totalCostLimit = 160 * 1024 * 1024
        return cache
    }()

    /// Width ÷ height of every page seen so far. A page that scrolled away
    /// releases its bitmap but keeps this, so its slot keeps its height and the
    /// strip does not jump when the page comes back.
    @MainActor static var aspectRatios: [String: CGFloat] = [:]
}

/// Page decoding. Pages are scaled to the screen's pixel width while decoding:
/// a 1600×2400 page is 15 MB as a bitmap and a webtoon strip can be 40 MB, but
/// the screen never shows more than its own width in pixels.
enum PageDecode {

    /// Decode on the cooperative pool, never on the caller's actor, and not at
    /// all if the page has already scrolled away by the time it is its turn.
    @concurrent
    static func decode(_ data: Data, targetWidth: CGFloat, screenScale: CGFloat) async -> UIImage? {
        await PageDecodeGate.shared.acquire()
        defer { Task { await PageDecodeGate.shared.release() } }
        guard !Task.isCancelled else { return nil }
        return image(from: data, targetWidth: targetWidth, screenScale: screenScale)
    }

    nonisolated static func image(from data: Data, targetWidth: CGFloat, screenScale: CGFloat = 1) -> UIImage? {
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
        // Tag the bitmap with the screen's scale so one image pixel is one
        // screen pixel. At scale 1 a 1290 px page reads as 1290 pt wide and the
        // GPU minifies it three-to-one on every composited frame.
        return UIImage(cgImage: cg, scale: max(screenScale, 1), orientation: .up)
    }
}

/// Limits concurrent page decodes.
///
/// A fast flick down a strip instantiates a dozen pages at once; decoding them
/// all in parallel saturates every core and starves the main thread, which is
/// the stutter. Two at a time keeps one core free for the UI, and a queued
/// decode for a page that has since scrolled away is skipped when its turn comes.
actor PageDecodeGate {
    static let shared = PageDecodeGate(limit: 2)

    private let limit: Int
    private var running = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) { self.limit = limit }

    func acquire() async {
        if running < limit {
            running += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty {
            running -= 1
        } else {
            waiters.removeFirst().resume()
        }
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

    @Environment(\.displayScale) private var displayScale
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
                placeholder
            }
        }
        // Re-runs when the page changes or the user retries, and on every
        // reappearance (a `.task` restarts when its view comes back on screen).
        .task(id: "\(page.url)#\(attempt)") {
            await load()
        }
        // Off screen, give the bitmap back. The decoded-image cache still holds
        // the neighbourhood, so scrolling straight back is instant; a long
        // chapter no longer keeps every page's bitmap alive.
        .onDisappear {
            image = nil
        }
    }

    /// Keeps the page's real height when it is known, so releasing the bitmap
    /// does not collapse the slot to a spinner-sized row.
    @ViewBuilder
    private var placeholder: some View {
        if let ratio = PageImageCache.aspectRatios[page.url], ratio > 0 {
            Color.clear
                .aspectRatio(ratio, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay { ProgressView().tint(.white) }
        } else {
            ProgressView()
                .tint(.white)
                .frame(maxWidth: .infinity, minHeight: 220)
        }
    }

    /// Width of the screen this app is on, without the deprecated `UIScreen.main`.
    private static var screenWidth: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.screen.bounds.width }
            .first ?? 390
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
            guard !Task.isCancelled else { return }
            let decoded = await PageDecode.decode(
                data,
                targetWidth: Self.screenWidth * displayScale,
                screenScale: displayScale
            )
            guard !Task.isCancelled else { return }
            guard let decoded else {
                throw HTTPError.transport("Page \(page.index + 1) is not a valid image")
            }
            PageImageCache.shared.setObject(
                decoded,
                forKey: requestedURL as NSString,
                cost: Int(decoded.size.width * decoded.scale * decoded.size.height * decoded.scale * 4)
            )
            if decoded.size.height > 0 {
                PageImageCache.aspectRatios[requestedURL] = decoded.size.width / decoded.size.height
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
