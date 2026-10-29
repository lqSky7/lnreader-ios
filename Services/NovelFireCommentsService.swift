import Foundation
import SwiftSoup

/// Service for interacting with the NovelFire / NovelPhoenix comments API.
///
/// Both sites run the same backend (same `/comment/show` JSON shape, same
/// `post_id` / `chapter_id` / `csrf-token` markers, same
/// `/account/comment/like|dislike` actions) — only host + session cookie differ.
/// Use ``CommentSite`` to pick the target. Overloads without a `site`
/// default to `.novelFire` for backwards compatibility.
final class NovelFireCommentsService {

    static let shared = NovelFireCommentsService()

    /// Convenience accessor for call sites that already resolved the site.
    static func shared(for site: CommentSite) -> NovelFireCommentsService { shared }

    private init() {}

    struct CommentsResponse: Decodable {
        let html: String
        let next_cursor: String?
        let has_more_pages: Bool
    }

    struct ActionResponse: Decodable {
        let status: Int
        let likes: Int
        let dislikes: Int
    }

    typealias ChapterMeta = (postId: String, chapterId: String, csrfToken: String)

    private let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"

    // MARK: - Cached state (perf)

    /// Pre-compiled regexes — compiling NSRegularExpression per request is expensive.
    private static let postIdRegex = try! NSRegularExpression(pattern: "report-post_id=\"(\\d+)\"|post_id\\s*=\\s*parseInt\\(\"(\\d+)\"\\)", options: [])
    private static let chapterIdRegex = try! NSRegularExpression(pattern: "report-chapter_id=\"(\\d+)\"|chapter_id\\s*=\\s*parseInt\\(\"(\\d+)\"\\)", options: [])
    private static let csrfRegex = try! NSRegularExpression(pattern: "<meta name=\"csrf-token\" content=\"([^\"]+)\">", options: [])

    private final class MetaBox: NSObject {
        let meta: ChapterMeta
        let expires: Date
        init(_ meta: ChapterMeta, expires: Date) { self.meta = meta; self.expires = expires }
    }
    /// Chapter metadata cache: key = "<site.rawValue>::<chapterPath>". 10 min TTL.
    /// Avoids re-downloading the full chapter HTML every time the sheet opens.
    private let metaCache: NSCache<NSString, MetaBox> = {
        let c = NSCache<NSString, MetaBox>()
        c.countLimit = 100
        return c
    }()
    private static let metaTTL: TimeInterval = 600

    /// Session with an on-disk/memory URLCache so chapter HTML + comment JSON
    /// can be revalidated instead of re-downloaded.
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadRevalidatingCacheData
        config.urlCache = URLCache(memoryCapacity: 8 * 1024 * 1024, diskCapacity: 32 * 1024 * 1024)
        config.httpMaximumConnectionsPerHost = 4
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()

    // MARK: - Session helpers

    /// Whether the user holds a login session cookie for the given site.
    func hasSession(for site: CommentSite = .novelFire) -> Bool {
        let cookies = HTTPCookieStorage.shared.cookies ?? []
        return UserDefaults.standard.bool(forKey: "comments.authenticated." + site.rawValue) && cookies.contains { site.matches(host: $0.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))) && $0.name == site.sessionCookieName && ($0.expiresDate.map { $0 > Date() } ?? true) }
    }

    /// Forget the stored session for `site`.
    ///
    /// The flag alone is not enough: a still-valid cookie would be reused the
    /// next time the site is opened, so the site's cookies go too.
    func disconnect(from site: CommentSite) {
        UserDefaults.standard.set(false, forKey: "comments.authenticated." + site.rawValue)
        let host = CharacterSet(charactersIn: ".")
        for cookie in HTTPCookieStorage.shared.cookies ?? [] where site.matches(host: cookie.domain.trimmingCharacters(in: host)) {
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }
        metaCache.removeAllObjects()
    }

    // MARK: - Metadata

    /// Fetches the raw HTML of the chapter page and extracts the post_id, chapter_id, and csrf-token
    func fetchChapterMetadata(chapterPath: String, site: CommentSite = .novelFire, forceRefresh: Bool = false) async throws -> ChapterMeta {
        let cacheKey = "\(site.rawValue)::\(chapterPath)" as NSString
        if !forceRefresh, let box = metaCache.object(forKey: cacheKey), box.expires > Date() {
            return box.meta
        }

        guard let url = site.chapterURL(chapterPath: chapterPath) else {
            throw NSError(domain: "NovelFireComments", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL for path: \(chapterPath)"])
        }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        // Chapter HTML changes rarely; allow revalidation instead of forced download.
        request.cachePolicy = .reloadRevalidatingCacheData
        request.timeoutInterval = 30

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw NSError(domain: "NovelFireComments", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch chapter page (status code: \(code))"])
        }

        guard let html = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "NovelFireComments", code: -3, userInfo: [NSLocalizedDescriptionKey: "Chapter page is not valid UTF-8"])
        }

        guard let postId = Self.firstCapture(regex: Self.postIdRegex, in: html),
              let chapterId = Self.firstCapture(regex: Self.chapterIdRegex, in: html),
              let csrfToken = Self.firstCapture(regex: Self.csrfRegex, in: html) else {
            throw NSError(domain: "NovelFireComments", code: -4, userInfo: [NSLocalizedDescriptionKey: "Failed to parse required comments metadata (postId, chapterId, or csrf-token) from page."])
        }

        let meta: ChapterMeta = (postId, chapterId, csrfToken)
        metaCache.setObject(MetaBox(meta, expires: Date().addingTimeInterval(Self.metaTTL)), forKey: cacheKey)
        return meta
    }

    /// Refresh only the CSRF token (cheap path used after a 419).
    func refreshCsrfToken(chapterPath: String, site: CommentSite = .novelFire) async throws -> String {
        let meta = try await fetchChapterMetadata(chapterPath: chapterPath, site: site, forceRefresh: true)
        return meta.csrfToken
    }

    // MARK: - Comments

    /// Fetches the comments from the site's comments endpoint
    func fetchComments(postId: String, chapterId: String, cursor: String? = nil, site: CommentSite = .novelFire) async throws -> CommentsResponse {
        var components = URLComponents(string: "\(site.baseURLString)/comment/show")!
        var items = [
            URLQueryItem(name: "post_id", value: postId),
            URLQueryItem(name: "chapter_id", value: chapterId),
            URLQueryItem(name: "order_by", value: "newest"),
        ]
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        components.queryItems = items

        guard let url = components.url else {
            throw NSError(domain: "NovelFireComments", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid comments URL"])
        }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(site.refererBase, forHTTPHeaderField: "Referer")
        injectCookies(into: &request, site: site)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw NSError(domain: "NovelFireComments", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch comments (status code: \(code))"])
        }

        return try JSONDecoder().decode(CommentsResponse.self, from: data)
    }

    // MARK: - Like / dislike

    /// Perform the like POST action for a comment
    func likeComment(commentId: String, csrfToken: String, referer: String, site: CommentSite = .novelFire) async throws -> ActionResponse {
        try await performAction(urlPath: "/account/comment/like", commentId: commentId, csrfToken: csrfToken, referer: referer, site: site)
    }

    /// Perform the dislike POST action for a comment
    func dislikeComment(commentId: String, csrfToken: String, referer: String, site: CommentSite = .novelFire) async throws -> ActionResponse {
        try await performAction(urlPath: "/account/comment/dislike", commentId: commentId, csrfToken: csrfToken, referer: referer, site: site)
    }

    private func performAction(urlPath: String, commentId: String, csrfToken: String, referer: String, site: CommentSite) async throws -> ActionResponse {
        guard let url = URL(string: "\(site.baseURLString)\(urlPath)") else {
            throw NSError(domain: "NovelFireComments", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid action URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue(referer, forHTTPHeaderField: "Referer")

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "comment_id", value: commentId),
            URLQueryItem(name: "_token", value: csrfToken),
        ]
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        injectCookies(into: &request, site: site)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "NovelFireComments", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid network response for action"])
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 419 {
                // CSRF expired — drop cached metadata so the next fetch re-reads it.
                metaCache.removeAllObjects()
                throw NSError(domain: "NovelFireComments", code: 419, userInfo: [NSLocalizedDescriptionKey: "CSRF Token expired or invalid. Please reload the chapter."])
            }
            throw NSError(domain: "NovelFireComments", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Action failed (status code: \(httpResponse.statusCode))"])
        }

        return try JSONDecoder().decode(ActionResponse.self, from: data)
    }

    // MARK: - Helpers

    /// Return the first non-empty capture group.
    private static func firstCapture(regex: NSRegularExpression, in text: String) -> String? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }
        for i in 1..<match.numberOfRanges {
            let groupRange = match.range(at: i)
            if groupRange.location != NSNotFound, let r = Range(groupRange, in: text) {
                let value = String(text[r])
                if !value.isEmpty { return value }
            }
        }
        return nil
    }

    private func injectCookies(into request: inout URLRequest, site: CommentSite) {
        guard let base = URL(string: site.baseURLString),
              let cookies = HTTPCookieStorage.shared.cookies(for: base),
              !cookies.isEmpty else {
            #if DEBUG
            print("⚠️ [CommentsService:\(site.rawValue)] No cookies for \(site.domain)")
            #endif
            return
        }
        let cookieHeader = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
    }
}

struct NativeChapterComment: Identifiable, Sendable {
    let id: String
    let parentID: String?
    let author: String
    let text: String
    let date: String
    var likes: Int
    var dislikes: Int
    let isSpoiler: Bool
    var replies: [NativeChapterComment] = []
}

extension NovelFireCommentsService {
    /// The provider returns HTML inside JSON. Parse it as data; never execute or
    /// render the provider's scripts, ads, avatar resources, or page controls.
    static func nativeComments(from html: String) throws -> [NativeChapterComment] {
        guard html.utf8.count <= 2_000_000 else { throw URLError(.dataLengthExceedsMaximum) }
        let document = try SwiftSoup.parseBodyFragment(html)
        try document.select("script,style,iframe").remove()
        let elements = try document.select("[id^=lnw-comment-]").array()
        var comments: [NativeChapterComment] = []
        var seen = Set<String>()
        for element in elements.prefix(1000) {
            let id = String(element.id().dropFirst("lnw-comment-".count))
            guard !id.isEmpty, id.allSatisfy(\.isNumber), seen.insert(id).inserted else { continue }
            let parent = element.parents().array().first { $0.id().hasPrefix("lnw-comment-") }
            let parentID = parent.map { String($0.id().dropFirst("lnw-comment-".count)) }
            guard let content = try element.select(".comment-text, .comment-content").first() else { continue }
            // A parent's content must never be borrowed from one of its replies.
            guard content.parents().array().first(where: { $0.id().hasPrefix("lnw-comment-") })?.id() == element.id() else { continue }
            let body = try content.text().trimmingCharacters(in: .whitespacesAndNewlines)
            if body.isEmpty { continue }
            let author = try element.select(".username, .user-name").first()?.text() ?? "Reader"
            let date = try element.select("time, .comment-date, .date").first()?.text() ?? ""
            func count(_ selector: String) throws -> Int {
                guard let button = try element.select(selector).first() else { return 0 }
                let raw = try button.text().replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                let number = raw.filter { $0.isNumber || $0 == "." }
                let multiplier: Double = raw.lowercased().hasSuffix("k") ? 1000 : raw.lowercased().hasSuffix("m") ? 1_000_000 : 1
                return Int((Double(number) ?? 0) * multiplier)
            }
            comments.append(NativeChapterComment(id: id, parentID: parentID, author: author, text: body, date: date,
                likes: try count(".like-button"), dislikes: try count(".dislike-button"),
                isSpoiler: try !content.select(".spoiler, .spoiler-content").isEmpty() || content.hasClass("spoiler")))
        }
        let hasCommentMarkup = try !document.select(".comment-text, .comment-content").isEmpty()
        if comments.isEmpty && !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && hasCommentMarkup {
            throw NSError(domain: "NativeComments", code: 1, userInfo: [NSLocalizedDescriptionKey: "The site returned an unsupported comment format. Pull to refresh."])
        }
        let knownIDs = Set(comments.map(\.id))
        let children = Dictionary(grouping: comments, by: { $0.parentID ?? "" })
        func thread(_ comment: NativeChapterComment, depth: Int = 0) -> NativeChapterComment {
            var result = comment
            if depth < 20 { result.replies = (children[comment.id] ?? []).map { thread($0, depth: depth + 1) } }
            return result
        }
        return comments.filter { $0.parentID == nil || !knownIDs.contains($0.parentID!) }.map { thread($0) }
    }

    static func isAuthenticatedPage(_ html: String) -> Bool {
        guard html.utf8.count <= 2_000_000, let document = try? SwiftSoup.parse(html) else { return false }
        return (try? !document.select("a[href*='/logout'], form[action*='/logout'], form#logout-form").isEmpty()) ?? false
    }
}
