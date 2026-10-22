// ExtensionStore.swift - Installed bundles on disk.
//
// Extensions are files, not database rows: a bundle plus a small JSON manifest.
// That keeps install/uninstall atomic and lets the source registry be rebuilt at
// launch by scanning one directory.

import Foundation

/// A bundle installed on this device.
struct InstalledExtension: Codable, Hashable, Sendable {
    let pkg: String
    let name: String
    let lang: String
    let versionId: Int
    let iconURL: String?
    /// Asset-catalog name for bundled icons.
    var iconAsset: String? = nil
    let kind: ContentKind
    /// Repository this came from, for update checks. `nil` for bundled ones.
    let repoBaseURL: String?
    let installedAt: Date
}

/// Reads and writes the extensions directory.
///
/// Layout:
/// ```
/// Application Support/Extensions/
///   <pkg>.js        the bundle
///   <pkg>.json      InstalledExtension
/// ```
enum ExtensionStore {

    static var directory: URL {
        URL.applicationSupportDirectory.appending(path: "Extensions", directoryHint: .isDirectory)
    }

    static func bundleURL(for pkg: String) -> URL {
        directory.appending(path: "\(pkg).js")
    }

    static func manifestURL(for pkg: String) -> URL {
        directory.appending(path: "\(pkg).json")
    }

    // MARK: - Reading

    static func installed() -> [InstalledExtension] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )) ?? []

        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(InstalledExtension.self, from: data)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func bundle(for pkg: String) -> String? {
        try? String(contentsOf: bundleURL(for: pkg), encoding: .utf8)
    }

    static func isInstalled(_ pkg: String) -> Bool {
        FileManager.default.fileExists(atPath: bundleURL(for: pkg).path)
    }

    // MARK: - Writing

    /// Write a bundle and its manifest, replacing any previous version.
    @discardableResult
    static func install(_ extensionInfo: InstalledExtension, bundle: String) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let jsURL = bundleURL(for: extensionInfo.pkg)
        try bundle.write(to: jsURL, atomically: true, encoding: .utf8)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(extensionInfo).write(to: manifestURL(for: extensionInfo.pkg), options: .atomic)

        return jsURL
    }

    static func uninstall(_ pkg: String) {
        try? FileManager.default.removeItem(at: bundleURL(for: pkg))
        try? FileManager.default.removeItem(at: manifestURL(for: pkg))
    }
}
