// CustomAsyncImage.swift
// Custom AsyncImage component that bypasses default CFNetwork user-agent blocking.

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

/// Simple in-memory cache to prevent redundant image downloads.
final class ImageCache {
    static let shared = NSCache<NSURL, PlatformImage>()
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

        do {
            var request = URLRequest(url: url)
            request.setValue(
                "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1",
                forHTTPHeaderField: "User-Agent"
            )
            request.timeoutInterval = 15

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                phase = .failure(URLError(.badServerResponse))
                return
            }

            guard let downloadedImage = PlatformImage(data: data) else {
                phase = .failure(URLError(.cannotDecodeContentData))
                return
            }

            // Cache for future loads
            ImageCache.shared.setObject(downloadedImage, forKey: url as NSURL)

            phase = .success(Image(platformImage: downloadedImage))
        } catch {
            phase = .failure(error)
        }
    }
}
