// SourceManager.swift - The registry of installed sources.
//
// Replaces `PluginManager` as the thing the UI talks to. `PluginManager` keeps
// owning install/uninstall of LN plugins for now; this class owns the v2
// `CatalogSource` view of them, and later the Mihon extension repos too.

import Foundation
import Observation

/// Registry of every source the app can browse, of both kinds.
@Observable
@MainActor
final class SourceManager {

    /// Installed sources keyed by `sourceKey`.
    private(set) var sources: [String: any CatalogSource] = [:]

    /// Last failure from a registry or install operation.
    private(set) var lastError: Error?

    /// Set while sources are being (re)loaded from disk.
    private(set) var isLoading = false

    // MARK: Registration

    func register(_ source: any CatalogSource) {
        sources[source.key] = source
    }

    func unregister(key: String) {
        sources.removeValue(forKey: key)
    }

    func replaceAll(with newSources: [any CatalogSource]) {
        sources = Dictionary(uniqueKeysWithValues: newSources.map { ($0.key, $0) })
    }

    // MARK: Lookup

    func source(forKey key: String) -> (any CatalogSource)? {
        sources[key]
    }

    func source(for entry: Entry) -> (any CatalogSource)? {
        sources[entry.sourceKey]
    }

    /// All sources, novels first, then alphabetically inside each kind.
    var allSources: [any CatalogSource] {
        sources.values.sorted { lhs, rhs in
            if lhs.kind != rhs.kind { return lhs.kind == .novel }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    func sources(of kind: ContentKind) -> [any CatalogSource] {
        allSources.filter { $0.kind == kind }
    }

    var novelSources: [any CatalogSource] { sources(of: .novel) }
    var mangaSources: [any CatalogSource] { sources(of: .manga) }

    /// Languages present across installed sources, for the browse filter.
    var availableLanguages: [String] {
        Array(Set(sources.values.map(\.lang))).sorted()
    }

    func novelSource(forKey key: String) -> (any NovelSource)? {
        sources[key] as? any NovelSource
    }

    func mangaSource(forKey key: String) -> (any MangaSource)? {
        sources[key] as? any MangaSource
    }

    // MARK: Extensions

    /// Load every installed extension bundle into the registry.
    ///
    /// Idempotent: an already-registered key is left alone, so calling this
    /// after an install only adds the new one.
    func registerInstalledExtensions() {
        for installed in ExtensionStore.installed() {
            let key = SourceKey.make(kind: installed.kind, id: installed.pkg)
            if sources[key] != nil { continue }

            guard let bundle = ExtensionStore.bundle(for: installed.pkg) else { continue }

            let manifest = ExtensionManifest(
                pkg: installed.pkg,
                name: installed.name,
                lang: installed.lang,
                versionId: installed.versionId,
                iconURL: installed.iconURL,
                bundlePath: "\(installed.pkg).js",
                kind: installed.kind
            )

            do {
                register(try JSBundleMangaSource(manifest: manifest, bundle: bundle))
            } catch {
                // A broken bundle must not stop the others from loading.
                lastError = error
                print("⚠️ Extension \(installed.pkg) failed to load: \(error.localizedDescription)")
            }
        }
    }

    /// Uninstall an extension: remove its files and drop it from the registry.
    func uninstallExtension(pkg: String, kind: ContentKind) {
        ExtensionStore.uninstall(pkg)
        unregister(key: SourceKey.make(kind: kind, id: pkg))
    }

    // MARK: Bridging the v1 plugin layer

    /// Mirror the installed LN plugins into the registry.
    ///
    /// Existing adapters are reused so their parsed-plugin cache survives a
    /// refresh. Called after `PluginManager.restoreInstalledPlugins()` and after
    /// every install/uninstall.
    func sync(with pluginManager: PluginManager) {
        var updated: [String: any CatalogSource] = [:]

        for (pluginID, plugin) in pluginManager.installedPlugins {
            let key = "ln:\(pluginID)"
            if let existing = sources[key] {
                updated[key] = existing
            } else {
                updated[key] = LNPluginSource(plugin: plugin)
            }
        }

        // Sources of other kinds (Mihon, built-in) are owned elsewhere; keep them.
        for (key, source) in sources where source.kind != .novel {
            updated[key] = source
        }

        sources = updated
    }
}
