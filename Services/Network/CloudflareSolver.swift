// CloudflareSolver.swift - Solves Cloudflare interstitials in a hidden web view.
//
// Some sources (Comick, several Madara sites) gate every page behind a
// `cf_clearance` cookie that only a real browser can earn. We load the
// challenged URL in an off-screen WKWebView, wait for the challenge to clear,
// and hand the cookies back to the HTTP client. See plan §3.2.

import Foundation
import WebKit

/// `CloudflareChallengeSolving` backed by a hidden `WKWebView`.
struct WebKitCloudflareSolver: CloudflareChallengeSolving {

    /// How long to let the interstitial run before giving up.
    var timeout: TimeInterval = 25

    func solve(url: URL) async throws -> [HTTPCookie] {
        try await CloudflareWebView.solve(url: url, timeout: timeout)
    }
}

// MARK: - Web view driver

/// Headless challenge solving. Main-actor isolated because `WKWebView` is.
@MainActor
private enum CloudflareWebView {

    static func solve(url: URL, timeout: TimeInterval) async throws -> [HTTPCookie] {
        let configuration = WKWebViewConfiguration()
        // Share the app's data store so a solved challenge also helps the
        // login flows that use a visible web view.
        configuration.websiteDataStore = .default()

        let webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 390, height: 844),
            configuration: configuration
        )
        // Keep the view in a window-less container: WebKit still runs JS and
        // the challenge's own redirects without the user seeing anything.
        webView.load(URLRequest(url: url))

        let store = configuration.websiteDataStore.httpCookieStore
        let deadline = Date().addingTimeInterval(timeout)

        defer {
            webView.stopLoading()
            webView.loadHTMLString("", baseURL: nil)
        }

        while Date() < deadline {
            try Task.checkCancellation()
            try? await Task.sleep(for: .milliseconds(600))

            let cookies = await allCookies(in: store)
            if cookies.contains(where: { $0.name == "cf_clearance" }) {
                return cookies
            }
        }

        throw HTTPError.cloudflareChallenge(url: url.absoluteString)
    }

    private static func allCookies(in store: WKHTTPCookieStore) async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            store.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }
}
