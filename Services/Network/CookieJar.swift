// CookieJar.swift - One cookie jar shared by URLSession and WKWebView.

import Foundation
import WebKit

/// Keeps the `URLSession` cookie store and WebKit's cookie store in sync.
///
/// Two cookie stores exist in an iOS app and sources care about both: an
/// in-app web view login (NovelFire, Patreon-gated sources, Cloudflare) writes
/// cookies WebKit owns, while every scrape goes through `URLSession`. Without a
/// bridge the login "works" in the web view and the scrape still 403s.
enum CookieJar {

    // MARK: URLSession side

    static func cookies(for url: URL) -> [HTTPCookie] {
        HTTPCookieStorage.shared.cookies(for: url) ?? []
    }

    static func setCookies(_ cookies: [HTTPCookie], for url: URL) {
        HTTPCookieStorage.shared.setCookies(cookies, for: url, mainDocumentURL: nil)
    }

    /// `Cookie:` header value for a URL, or `nil` when the jar is empty.
    static func cookieHeader(for url: URL) -> String? {
        let cookies = cookies(for: url)
        guard !cookies.isEmpty else { return nil }
        return HTTPCookie.requestHeaderFields(with: cookies)["Cookie"]
    }

    static func clearAll() {
        for cookie in HTTPCookieStorage.shared.cookies ?? [] {
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }
    }

    // MARK: WebKit side

    /// Copy every cookie WebKit holds into the shared `HTTPCookieStorage`.
    ///
    /// Called after a login or a solved challenge, before the next scrape.
    @MainActor
    static func importFromWebKit() async {
        let cookies = await allWebKitCookies()
        for cookie in cookies {
            // `setCookie(_:)` derives the scope from the cookie's own domain.
            HTTPCookieStorage.shared.setCookie(cookie)
        }
    }

    /// Copy the shared jar into WebKit, so a login done over plain HTTP shows
    /// up in the visible web view too.
    @MainActor
    static func exportToWebKit() async {
        let store = WKWebsiteDataStore.default().httpCookieStore
        for cookie in HTTPCookieStorage.shared.cookies ?? [] {
            await withCheckedContinuation { continuation in
                store.setCookie(cookie) { continuation.resume() }
            }
        }
    }

    @MainActor
    private static func allWebKitCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }
}
