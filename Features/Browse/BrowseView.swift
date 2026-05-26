// BrowseView.swift
// Main browse screen for discovering and managing source plugins.

import SwiftUI

struct BrowseView: View {
    @Environment(PluginManager.self) private var pluginManager
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

                if !pluginManager.availableLanguages.isEmpty {
                    Section {
                        languageFilterRow
                    }
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
                SourceDetailView(plugin: plugin)
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
            .refreshable { await loadPlugins() }
            .overlay {
                if pluginManager.isLoading && pluginManager.plugins.isEmpty {
                    LoadingView(message: "Fetching sources...")
                }
            }
        }
    }

    // MARK: - Filtering

    private var installedPlugins: [PluginListItem] {
        pluginManager.installedPluginsList.filtered(
            searchText: searchText, language: selectedLanguage
        )
    }

    private var availablePlugins: [PluginListItem] {
        pluginManager.availablePluginsList.filtered(
            searchText: searchText, language: selectedLanguage
        )
    }

    // MARK: - Actions

    private func loadPlugins() async {
        try? await pluginManager.fetchPluginList()
        await pluginManager.restoreInstalledPlugins()
    }

    // MARK: - Language Filter

    private var languageFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
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
            .padding(.vertical, 4)
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
    }

    @ViewBuilder
    private func languageChip(
        _ title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(Typography.small)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    isSelected ? AppTheme.accent.opacity(0.2) : Color.secondary.opacity(0.1),
                    in: .capsule
                )
                .foregroundStyle(isSelected ? AppTheme.accent : .secondary)
        }
        .buttonStyle(.plain)
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
