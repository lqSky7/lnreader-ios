// BrowseView.swift
// Main browse screen for discovering and managing source plugins.

import SwiftUI

struct BrowseView: View {
    @Environment(PluginManager.self) private var pluginManager
    @Environment(SourceManager.self) private var sourceManager
    @State private var searchText = ""
    @State private var selectedLanguage: String?

    var body: some View {
        NavigationStack {
            List {
                if !installedPlugins.isEmpty {
                    Section("Installed Sources") {
                        ForEach(installedPlugins) { plugin in
                            NavigationLink(value: plugin) {
                                SourceCard(plugin: plugin, isInstalled: true) {
                                    pluginManager.uninstallPlugin(id: plugin.id)
                                }
                            }
                        }
                    }
                }

                if !extensionSources.isEmpty {
                    Section("Extensions") {
                        ForEach(extensionSources, id: \.key) { source in
                            NavigationLink {
                                SourceDetailView(sourceKey: source.key, title: source.name)
                            } label: {
                                HStack(spacing: 12) {
                                    SourceIconView(source: source, size: 30)
                                    Text(source.name)
                                }
                            }
                        }
                    }
                }

                if !pluginManager.availableLanguages.isEmpty {
                    Section("Language") {
                        languageFilterRow
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                Section("Available Sources") {
                    ForEach(availablePlugins) { plugin in
                        SourceCard(plugin: plugin, isInstalled: false) {
                            Task {
                                try? await pluginManager.installPlugin(id: plugin.id)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Browse")
            .searchable(text: $searchText, prompt: "Search sources")
            .navigationDestination(for: PluginListItem.self) { plugin in
                SourceDetailView(
                    sourceKey: SourceKey.make(kind: .novel, id: plugin.id),
                    title: plugin.name
                )
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        GlobalSearchView()
                    } label: {
                        Label("Global Search", systemImage: "magnifyingglass")
                    }
                }
            }
            .task { await loadPlugins() }
            .refreshable { await loadPlugins(forceRefresh: true) }
            .overlay {
                if pluginManager.isLoading && pluginManager.plugins.isEmpty {
                    LoadingView(message: "Fetching sources...")
                }
            }
        }
    }

    // MARK: - Filtering

    /// Everything that is not a JS novel plugin or a local import: bundled
    /// sources and installed extension bundles.
    private var extensionSources: [any CatalogSource] {
        sourceManager.allSources.filter { source in
            !SourceKey.isLN(source.key) && source.key != SourceKey.local
        }
    }

    private var installedPlugins: [PluginListItem] {
        pluginManager.installedPluginsList.filtered(
            searchText: searchText, language: nil
        )
    }

    private var availablePlugins: [PluginListItem] {
        pluginManager.availablePluginsList.filtered(
            searchText: searchText, language: selectedLanguage
        )
    }

    // MARK: - Actions

    private func loadPlugins(forceRefresh: Bool = false) async {
        try? await pluginManager.fetchPluginList(forceRefresh: forceRefresh)
        await pluginManager.restoreInstalledPlugins()
    }

    // MARK: - Language Filter

    private var languageFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer {
                HStack(spacing: 8) {
                    languageChip("All", isSelected: selectedLanguage == nil) {
                        selectedLanguage = nil
                    }
                    ForEach(pluginManager.availableLanguages, id: \.self) { lang in
                        languageChip(lang, isSelected: selectedLanguage == lang) {
                            selectedLanguage = lang
                        }
                    }
                }
            }
            .padding(.top, 2)
            .padding(.bottom, 2)
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: -8, trailing: 16))
    }

    @ViewBuilder
    private func languageChip(
        _ title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}

// MARK: - Array Filtering Helper

extension Array where Element == PluginListItem {
    func filtered(searchText: String, language: String?) -> [PluginListItem] {
        var result = self
        if let language {
            result = result.filter { $0.lang == language }
        }
        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
            }
        }
        return result
    }
}
