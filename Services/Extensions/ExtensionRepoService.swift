// ExtensionRepoService.swift - Repositories, trust and install.
//
// A repository is a static site: `repo.json` describes it (including the
// signing-key fingerprint to pin) and `index.min.json` lists extensions. Trust
// is established once, on first use, and every later fetch must match.
// See docs/MANGA_SUPPORT_PLAN.md §3.4.

import CryptoKit
import Foundation

/// `repo.json`.
struct ExtensionRepoMeta: Decodable {
    struct Meta: Decodable {
        let name: String
        let shortName: String?
        let website: String?
        let signingKeyFingerprint: String?
    }
    let meta: Meta
}

/// One row of `index.min.json`. Accepts both the Mihon shape (`apk`) and ours
/// (`bundle`), so a repository can serve either.
struct RemoteExtension: Decodable {
    let name: String
    let pkg: String
    let lang: String
    let versionId: Int
    let iconUrl: String?
    let apk: String?
    let bundle: String?

    var bundlePath: String? { bundle ?? apk }
}

enum ExtensionRepoError: LocalizedError {
    case badURL(String)
    case untrusted(expected: String, actual: String)
    case missingFingerprint
    case missingBundle
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .badURL(let value): "Invalid repository URL: \(value)"
        case .untrusted(let expected, let actual):
            "Repository signing key changed. Expected \(expected.prefix(16))…, got \(actual.prefix(16))…"
        case .missingFingerprint:
            "This repository does not publish a signing key, so it cannot be trusted."
        case .missingBundle:
            "The extension entry has no bundle to download."
        case .http(let status): "Repository returned HTTP \(status)."
        }
    }
}

actor ExtensionRepoService {

    static let shared = ExtensionRepoService()

    private let client: HTTPClient

    init(client: HTTPClient = .shared) {
        self.client = client
    }

    /// Fetch and decode a repository's metadata and index.
    func fetchIndex(baseURL: String) async throws -> (meta: ExtensionRepoMeta.Meta, extensions: [RemoteExtension]) {
        let base = try Self.baseURL(baseURL)

        let metaResponse = try await client.get(base.appending(path: "repo.json").absoluteString)
        guard metaResponse.isSuccess else { throw ExtensionRepoError.http(metaResponse.statusCode) }
        let meta = try metaResponse.decoded(ExtensionRepoMeta.self).meta

        let indexResponse = try await client.get(base.appending(path: "index.min.json").absoluteString)
        guard indexResponse.isSuccess else { throw ExtensionRepoError.http(indexResponse.statusCode) }
        let extensions = try indexResponse.decoded([RemoteExtension].self)

        return (meta, extensions)
    }

    /// Check the repository against a previously pinned fingerprint.
    ///
    /// - Parameter pinned: the fingerprint stored when the repository was added,
    ///   or `nil` on first use (in which case `meta` must publish one).
    /// - Returns: the fingerprint to store.
    @discardableResult
    static func verify(
        _ meta: ExtensionRepoMeta.Meta,
        pinned: String?
    ) throws -> String {
        guard let published = meta.signingKeyFingerprint, !published.isEmpty else {
            throw ExtensionRepoError.missingFingerprint
        }
        let normalized = Self.normalize(published)

        if let pinned {
            guard Self.normalize(pinned) == normalized else {
                throw ExtensionRepoError.untrusted(expected: pinned, actual: published)
            }
        }
        return published
    }

    /// Download one extension's bundle and install it.
    func install(
        _ remote: RemoteExtension,
        from baseURL: String,
        kind: ContentKind
    ) async throws -> InstalledExtension {
        guard let path = remote.bundlePath, !path.isEmpty else {
            throw ExtensionRepoError.missingBundle
        }
        let base = try Self.baseURL(baseURL)
        let url = path.hasPrefix("http")
            ? (URL(string: path) ?? base)
            : base.appending(path: path)

        let response = try await client.get(url.absoluteString)
        guard response.isSuccess else { throw ExtensionRepoError.http(response.statusCode) }
        let bundle = response.text
        guard !bundle.isEmpty else { throw ExtensionRepoError.missingBundle }

        let installed = InstalledExtension(
            pkg: remote.pkg,
            name: remote.name,
            lang: remote.lang,
            versionId: remote.versionId,
            iconURL: remote.iconUrl,
            kind: kind,
            repoBaseURL: baseURL,
            installedAt: .now
        )
        try ExtensionStore.install(installed, bundle: bundle)
        return installed
    }

    // MARK: - Helpers

    static func baseURL(_ string: String) throws -> URL {
        guard var components = URLComponents(string: string.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = components.scheme,
              scheme == "https" || scheme == "http",
              components.host != nil
        else {
            throw ExtensionRepoError.badURL(string)
        }
        // `appending(path:)` needs a directory URL.
        if !components.path.hasSuffix("/") {
            components.path += "/"
        }
        guard let url = components.url else { throw ExtensionRepoError.badURL(string) }
        return url
    }

    /// Fingerprints are compared ignoring case, colons and whitespace.
    static func normalize(_ fingerprint: String) -> String {
        fingerprint
            .lowercased()
            .filter { $0.isHexDigit }
    }
}
