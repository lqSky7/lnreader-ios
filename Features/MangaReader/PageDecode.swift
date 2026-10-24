// PageDecode.swift - Decoding page bytes into screen-sized bitmaps.

import ImageIO
import SwiftUI

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

    /// Width ÷ height from the image header, orientation applied.
    nonisolated static func aspectRatio(of data: Data) -> CGFloat? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? CGFloat,
              let h = props[kCGImagePropertyPixelHeight] as? CGFloat, w > 0, h > 0 else { return nil }
        let orientation = props[kCGImagePropertyOrientation] as? Int ?? 1
        return (5...8).contains(orientation) ? h / w : w / h
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
