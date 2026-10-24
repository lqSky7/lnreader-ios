// PageImageCache.swift - Decoded page images and their aspect ratios.

import SwiftUI

/// Decoded page images, kept so scrolling back over a page does not decode it
/// again. `PageLoader` caches the *bytes*; decoding is the expensive half and
/// was being redone every time a page came back into view.
enum PageImageCache {
    static let shared: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        // Byte-accounted: full-page images are large and the strip only ever
        // needs the neighbourhood. The count is a backstop, the budget is bytes.
        cache.countLimit = 24
        cache.totalCostLimit = 160 * 1024 * 1024
        return cache
    }()

    /// Width ÷ height of every page seen so far. A page that scrolled away
    /// releases its bitmap but keeps this, so its slot keeps its height and the
    /// strip does not jump when the page comes back.
    @MainActor static var aspectRatios: [String: CGFloat] = [:]

    /// Posted (object: the page URL) when a page's aspect ratio becomes known
    /// or changes, so the strip can resize its slot.
    static let ratioLearned = Notification.Name("PageImageCache.ratioLearned")

    @MainActor
    static func setRatio(_ ratio: CGFloat, forKey key: String) {
        guard ratio > 0 else { return }
        // The decoded bitmap is rounded to whole pixels, so its ratio can differ
        // from the header's in the third decimal; that is not a new height.
        if let old = aspectRatios[key], abs(old - ratio) / old < 0.01 { return }
        aspectRatios[key] = ratio
        NotificationCenter.default.post(name: ratioLearned, object: key)
    }

    /// Record the ratio from the image header alone, long before it decodes.
    @MainActor
    static func noteRatio(from data: Data, forKey key: String) {
        if let ratio = PageDecode.aspectRatio(of: data) { setRatio(ratio, forKey: key) }
    }
}

extension PageImageCache {
    @MainActor
    static func store(_ image: UIImage, forKey key: String) {
        shared.setObject(
            image,
            forKey: key as NSString,
            cost: Int(image.size.width * image.scale * image.size.height * image.scale * 4)
        )
        if image.size.height > 0 {
            setRatio(image.size.width / image.size.height, forKey: key)
        }
    }
}
