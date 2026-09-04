import Foundation

/// A LightNovelWorld-style site (NovelFire / NovelPhoenix) that exposes
/// the same `/comment/show` + `/account/comment/*` JSON API.
///
/// NovelPhoenix is a re-skin of NovelFire — same HTML markers
/// (`report-post_id`, `parseInt("…")`, `<meta name="csrf-token">`) and the
/// same comment endpoints — only the host and session cookie differ.
enum CommentSite: String, CaseIterable, Sendable, Hashable {
    case novelFire = "novelfire"
    case novelPhoenix = "novelphoenix"

    /// Resolve a plugin id to its comment site, if comments are supported.
    static func site(for pluginId: String) -> CommentSite? {
        CommentSite(rawValue: pluginId.lowercased())
    }

    /// All plugin ids that support chapter comments.
    static var supportedPluginIds: Set<String> {
        Set(CommentSite.allCases.map(\.rawValue))
    }

    /// Whether a plugin id supports chapter comments.
    static func supportsComments(pluginId: String) -> Bool {
        site(for: pluginId) != nil
    }

    var baseURLString: String {
        switch self {
        case .novelFire: return "https://novelfire.net"
        case .novelPhoenix: return "https://novelphoenix.com"
        }
    }

    var domain: String {
        switch self {
        case .novelFire: return "novelfire.net"
        case .novelPhoenix: return "novelphoenix.com"
        }
    }

    /// Laravel session cookie set after Google OAuth.
    var sessionCookieName: String {
        switch self {
        case .novelFire: return "novelfirenet_session"
        case .novelPhoenix: return "novelphoenixcom_session"
        }
    }

    var displayName: String {
        switch self {
        case .novelFire: return "NovelFire"
        case .novelPhoenix: return "NovelPhoenix"
        }
    }

    var googleAuthURL: URL {
        URL(string: "\(baseURLString)/auth/redirect/google")!
    }

    var refererBase: String {
        "\(baseURLString)/"
    }

    func chapterURL(chapterPath: String) -> URL? {
        let fullPath = chapterPath.hasPrefix("/") ? String(chapterPath.dropFirst()) : chapterPath
        return URL(string: "\(baseURLString)/\(fullPath)")
    }

    func referer(chapterPath: String) -> String {
        let fullPath = chapterPath.hasPrefix("/") ? String(chapterPath.dropFirst()) : chapterPath
        return "\(baseURLString)/\(fullPath)"
    }
}
