// CustomAsyncImage.swift
// Custom AsyncImage component that bypasses default CFNetwork user-agent blocking.

import ImageIO
import SwiftUI

#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
#endif

extension Image {
    init(platformImage: PlatformImage) {
        #if canImport(UIKit)
        self.init(uiImage: platformImage)
        #elseif canImport(AppKit)
        self.init(nsImage: platformImage)
        #endif
    }
}

/// Decoding helpers for cover art.
///
/// `UIImage(data:)` keeps the compressed data and decodes lazily on first
/// draw — on the main thread, inside the render pass. A 1200×1800 cover
/// decodes to ~8 MB, and a library grid asks for a dozen at once. Downsampling
/// with ImageIO decodes once, off the main thread, to the size actually shown.
enum CoverDecode {

    /// Longest edge of a decoded cover. A grid cell is at most ~200 pt wide
    /// (600 px at 3×), so a 1200 px cover is 4× the memory for no visible gain.
    static let defaultMaxPixelSize = 700

    static func image(from data: Data, maxPixelSize: Int = defaultMaxPixelSize) -> PlatformImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }

        // `ShouldCacheImmediately` decodes now rather than at draw time, which
        // is the whole point: the work happens on whatever executor we are on.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return PlatformImage(cgImage: cgImage)
    }

    /// Bytes the decoded image occupies, for `NSCache` cost accounting.
    static func cost(of image: PlatformImage) -> Int {
        #if canImport(UIKit)
        let size = image.size
        let scale = image.scale
        #else
        let size = image.size
        let scale: CGFloat = 1
        #endif
        return max(Int(size.width * scale * size.height * scale * 4), 1)
    }
}

/// Simple in-memory cache to prevent redundant image downloads.
final class ImageCache {
    static let shared: NSCache<NSURL, PlatformImage> = {
        let cache = NSCache<NSURL, PlatformImage>()
        // Cost is set from the decoded pixel size on every insert, so this is a
        // real byte budget rather than a count that happens to be bounded.
        cache.countLimit = 200
        cache.totalCostLimit = 96 * 1024 * 1024
        return cache
    }()

    /// In-flight downloads keyed by URL so 20 cells showing the same cover
    /// share one network request instead of firing 20.
    private static let lock = NSLock()
    private static var inFlight: [NSURL: Task<PlatformImage, Error>] = [:]

    static func dedupedDownload(for key: NSURL, download: @escaping () async throws -> PlatformImage) async throws -> PlatformImage {
        let (task, isOwner) = claim(key, download: download)
        // Only the request's owner clears the entry; waiters just share its result.
        defer { if isOwner { release(key) } }
        return try await task.value
    }

    // Synchronous so the lock is never held across a suspension point.
    private static func claim(_ key: NSURL, download: @escaping () async throws -> PlatformImage) -> (Task<PlatformImage, Error>, Bool) {
        lock.withLock {
            if let existing = inFlight[key] { return (existing, false) }
            let task = Task<PlatformImage, Error> { try await download() }
            inFlight[key] = task
            return (task, true)
        }
    }

    private static func release(_ key: NSURL) {
        lock.withLock { _ = inFlight.removeValue(forKey: key) }
    }

    static func store(_ image: PlatformImage, for key: NSURL) {
        shared.setObject(image, forKey: key, cost: CoverDecode.cost(of: image))
    }
}

/// Shared session with a real URLCache so covers survive restarts and
/// revalidates with the CDN instead of re-downloading.
private enum CoverNetwork {
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.urlCache = URLCache(memoryCapacity: 20 * 1024 * 1024, diskCapacity: 200 * 1024 * 1024)
        config.httpMaximumConnectionsPerHost = 6
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()
}

/// A drop-in replacement for SwiftUI's AsyncImage that fetches images with
/// a standard browser User-Agent to bypass Cloudflare/CDN blocking.
struct CustomAsyncImage: View {
    private let url: URL?
    private let content: (AsyncImagePhase) -> AnyView

    @State private var phase: AsyncImagePhase = .empty

    /// Initialize with a phase closure.
    init<Content: View>(
        url: URL?,
        @ViewBuilder content: @escaping (AsyncImagePhase) -> Content
    ) {
        self.url = url
        self.content = { phase in AnyView(content(phase)) }
    }

    /// Initialize with separate success and placeholder closures.
    init<I: View, P: View>(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> I,
        @ViewBuilder placeholder: @escaping () -> P
    ) {
        self.url = url
        self.content = { phase in
            switch phase {
            case .success(let image):
                return AnyView(content(image))
            default:
                return AnyView(placeholder())
            }
        }
    }

    var body: some View {
        content(phase)
            .task(id: url) {
                await loadImage()
            }
    }

    private func loadImage() async {
        guard let url else {
            phase = .empty
            return
        }

        // Check in-memory cache first
        if let cachedImage = ImageCache.shared.object(forKey: url as NSURL) {
            phase = .success(Image(platformImage: cachedImage))
            return
        }

        phase = .empty

        if url.scheme == "local" || url.isFileURL {
            do {
                let fileURL: URL
                if url.scheme == "local" {
                    let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    let pathComponent = (url.host ?? "").appending(url.path)
                    fileURL = docDir.appendingPathComponent(pathComponent)
                } else {
                    fileURL = url
                }
                
                let data = try Data(contentsOf: fileURL)
                guard let image = CoverDecode.image(from: data) else {
                    phase = .failure(URLError(.cannotDecodeContentData))
                    return
                }
                ImageCache.store(image, for: url as NSURL)
                phase = .success(Image(platformImage: image))
            } catch {
                print("❌ [CustomAsyncImage] Failed to load local cover: \(error.localizedDescription) for URL \(url)")
                phase = .failure(error)
            }
            return
        }

        do {
            var request = URLRequest(url: url)
            request.setValue(
                "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1",
                forHTTPHeaderField: "User-Agent"
            )
            request.timeoutInterval = 15
            // Let URLCache serve stored covers without hitting the network.
            request.cachePolicy = .returnCacheDataElseLoad

            let key = url as NSURL
            let downloadedImage = try await ImageCache.dedupedDownload(for: key) {
                let (data, response) = try await CoverNetwork.session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode),
                      let image = CoverDecode.image(from: data) else {
                    throw URLError(.badServerResponse)
                }
                return image
            }

            // Cache for future loads
            ImageCache.store(downloadedImage, for: key)

            phase = .success(Image(platformImage: downloadedImage))
        } catch {
            phase = .failure(error)
        }
    }
}
