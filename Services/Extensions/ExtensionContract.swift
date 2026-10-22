// ExtensionContract.swift - What a transpiled extension bundle looks like.
//
// The Kotlin/JS transpiler (plan §3.3) emits one JS file per extension. This is
// the contract that file must satisfy: a single global `extension` object whose
// methods are synchronous and return plain objects. Synchronous on purpose —
// the host blocks the JS thread while `http.get` runs, which keeps bundles
// readable and lets a transpiler emit straight-line code instead of promise
// plumbing.

import Foundation

/// Metadata a repository publishes for one extension.
struct ExtensionManifest: Identifiable, Hashable, Sendable {
    /// Stable package id, e.g. `"eu.kanade.tachiyomi.manga.mangafire"`.
    let pkg: String
    let name: String
    let lang: String
    let versionId: Int
    let iconURL: String?
    /// Where the JS bundle lives, relative to the repository base URL.
    let bundlePath: String
    /// Which kind of content it serves.
    let kind: ContentKind

    var id: String { pkg }
}

/// The JS surface an extension bundle must implement.
///
/// ```js
/// var extension = {
///   id: "mangafire",
///   name: "MangaFire",
///   lang: "en",
///   version: "1.0.0",
///   baseUrl: "https://mangafire.to",
///   supportsLatest: true,
///
///   // page is 1-based
///   popular: function (page) { return { entries: [...], hasNextPage: true }; },
///   latest:  function (page) { ... },
///   search:  function (query, page) { ... },
///
///   details:  function (url) { return entry; },
///   chapters: function (url) { return [{ url, name, number, scanlator, dateUpload }]; },
///   pages:    function (url) { return [{ url, headers }]; }
/// };
/// ```
///
/// `entry` is `{ url, title, thumbnailURL, author, artist, description,
/// genres: [], status }`, where `status` is one of `unknown`, `ongoing`,
/// `completed`, `licensed`, `publishingFinished`, `cancelled`, `onHiatus`.
///
/// Bundles are given two globals:
/// - `http.get(url, headers?)` / `http.post(url, body, headers?)` →
///   `{ status, url, body }` or `{ error }`.
/// - `dom.parse(html)` → handle, `dom.select(handle, css)` → handles,
///   `dom.text/html/attr(handle, …)`.
///
/// Anything a bundle needs beyond that (base64, crypto) it must implement
/// itself; the host deliberately keeps the surface small.
enum ExtensionContract {
    /// Methods every bundle must define.
    static let requiredMethods = [
        "popular", "search", "details", "chapters", "pages",
    ]

    /// Methods that may be absent; the host falls back to `popular`.
    static let optionalMethods = ["latest"]

    static let prelude = """
    var http = {
      get: function (url, headers) {
        return JSON.parse(__nativeGet(url, headers ? JSON.stringify(headers) : null));
      },
      post: function (url, body, headers) {
        return JSON.parse(__nativePost(url, body == null ? null : String(body),
                                       headers ? JSON.stringify(headers) : null));
      }
    };
    var dom = {
      parse: function (html) { return __nativeParse(html); },
      select: function (handle, selector) {
        return JSON.parse(__nativeSelect(handle, selector));
      },
      text: function (handle) { return __nativeText(handle); },
      html: function (handle) { return __nativeHTML(handle); },
      attr: function (handle, name) { return __nativeAttr(handle, name); }
    };
    """
}
