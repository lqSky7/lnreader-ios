import Foundation
import Observation

// MARK: - Plugin List Item

/// Metadata for a plugin in the remote registry.
struct PluginListItem: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let site: String
    let lang: String
    let version: String
    /// URL of the JavaScript source file.
    let url: String
    let iconUrl: String

    /// Whether this plugin is currently installed locally. Not decoded from JSON.
    var isInstalled: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, name, site, lang, version, url, iconUrl
    }
}

// MARK: - Plugin Manager Errors

enum PluginManagerError: LocalizedError {
    case pluginNotFound(String)
    case downloadFailed(String)
    case alreadyInstalled(String)
    case installationFailed(String)

    var errorDescription: String? {
        switch self {
        case .pluginNotFound(let id):
            "Plugin '\(id)' not found in registry"
        case .downloadFailed(let reason):
            "Failed to download plugin: \(reason)"
        case .alreadyInstalled(let id):
            "Plugin '\(id)' is already installed"
        case .installationFailed(let reason):
            "Plugin installation failed: \(reason)"
        }
    }
}

// MARK: - Plugin Manager

/// Manages the lifecycle of content source plugins: fetching the registry,
/// installing/uninstalling plugins, and providing access to installed sources.
@Observable
@MainActor
final class PluginManager {

    /// All plugins from the remote registry.
    private(set) var plugins: [PluginListItem] = []

    /// Currently installed plugin instances keyed by ID.
    private(set) var installedPlugins: [String: any SourcePlugin] = [:]

    /// Whether the registry is currently being fetched.
    private(set) var isLoading = false

    /// Last error encountered during an operation.
    private(set) var lastError: Error?

    /// Set of plugin IDs currently being installed.
    private(set) var installingPluginIDs: Set<String> = []

    // MARK: - Computed Properties

    /// Unique languages available across all plugins.
    var availableLanguages: [String] {
        Array(Set(plugins.map(\.lang))).sorted()
    }

    /// Plugins that are currently installed.
    var installedPluginsList: [PluginListItem] {
        plugins.filter { installedPlugins[$0.id] != nil }
    }

    /// Plugins that are not currently installed.
    var availablePluginsList: [PluginListItem] {
        plugins.filter { installedPlugins[$0.id] == nil }
    }

    // MARK: - Registry

    /// The hardcoded URL for the plugin registry.
    private static let registryURL =
        "https://raw.githubusercontent.com/LNReader/lnreader-plugins/plugins/v3.0.0/.dist/plugins.min.json"

    /// Fetch the plugin registry from the remote repository.
    func fetchPluginList() async throws {
        isLoading = true
        lastError = nil

        defer { isLoading = false }

        do {
            let items: [PluginListItem] = try await NetworkClient.shared.fetchJSON(
                urlString: Self.registryURL
            )
            plugins = items
            syncInstalledState()
        } catch {
            lastError = error
            throw error
        }
    }

    // MARK: - Installation

    /// Install a plugin by downloading its JavaScript file and creating a JSSourcePlugin.
    func installPlugin(id: String) async throws {
        guard let item = plugins.first(where: { $0.id == id }) else {
            throw PluginManagerError.pluginNotFound(id)
        }

        guard installedPlugins[id] == nil else {
            throw PluginManagerError.alreadyInstalled(id)
        }

        installingPluginIDs.insert(id)
        defer { installingPluginIDs.remove(id) }

        do {
            // Download JS file
            let jsCode = try await NetworkClient.shared.fetchString(urlString: item.url)

            // Save to Documents for offline use
            try savePluginJS(id: id, code: jsCode)

            // Create the plugin instance
            let plugin = try JSSourcePlugin(
                id: item.id,
                name: item.name,
                iconURL: item.iconUrl,
                siteURL: item.site,
                language: item.lang,
                version: item.version,
                jsCode: jsCode
            )

            installedPlugins[id] = plugin
            syncInstalledState()
        } catch {
            lastError = error
            throw PluginManagerError.installationFailed(error.localizedDescription)
        }
    }

    /// Uninstall a plugin, removing it from memory and disk.
    func uninstallPlugin(id: String) {
        installedPlugins.removeValue(forKey: id)
        deletePluginJS(id: id)
        syncInstalledState()
    }

    /// Get an installed plugin by ID.
    func plugin(for id: String) -> (any SourcePlugin)? {
        installedPlugins[id]
    }

    /// Look up the display name for a plugin by ID.
    func pluginName(for id: String) -> String {
        plugins.first(where: { $0.id == id })?.name ?? id
    }

    // MARK: - Persistence

    /// Restore previously installed plugins from saved JS files on disk.
    func restoreInstalledPlugins() async {
        let pluginsDir = Self.pluginsDirectory
        guard FileManager.default.fileExists(atPath: pluginsDir.path()) else { return }

        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(
            at: pluginsDir,
            includingPropertiesForKeys: nil
        ) else { return }

        for file in files where file.pathExtension == "js" {
            let pluginID = file.deletingPathExtension().lastPathComponent

            // Skip if already installed
            guard installedPlugins[pluginID] == nil else { continue }

            // Find registry item for metadata
            guard let item = plugins.first(where: { $0.id == pluginID }) else { continue }

            guard let jsCode = try? String(contentsOf: file, encoding: .utf8) else { continue }

            do {
                let plugin = try JSSourcePlugin(
                    id: item.id,
                    name: item.name,
                    iconURL: item.iconUrl,
                    siteURL: item.site,
                    language: item.lang,
                    version: item.version,
                    jsCode: jsCode
                )
                installedPlugins[pluginID] = plugin
            } catch {
                // Log and skip corrupt plugins
                print("⚠️ Failed to restore plugin '\(pluginID)': \(error)")
            }
        }

        syncInstalledState()
    }

    // MARK: - Private Helpers

    /// Directory where plugin JS files are persisted.
    private static var pluginsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Plugins", isDirectory: true)
    }

    /// Save a plugin's JS code to disk.
    private func savePluginJS(id: String, code: String) throws {
        let dir = Self.pluginsDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent("\(id).js")
        try code.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    /// Delete a plugin's JS file from disk.
    private func deletePluginJS(id: String) {
        let fileURL = Self.pluginsDirectory.appendingPathComponent("\(id).js")
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Update the `isInstalled` flag on registry items to match current state.
    private func syncInstalledState() {
        plugins = plugins.map { item in
            var updated = item
            updated.isInstalled = installedPlugins[item.id] != nil
            return updated
        }
    }
}
