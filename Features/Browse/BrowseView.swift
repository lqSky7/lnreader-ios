// BrowseView.swift
// Sources, split by kind: light novels and manga are separate catalogues.
//
// Novels come from the JS plugin registry, manga from installed extension
// bundles, so the two lists have different sections and different empty states.
// A segmented control switches between them in place, which is the native iOS
// pattern for two peer lists.

import SwiftUI

/// Which catalogue the browse screen is showing.
enum BrowseKind: String, CaseIterable, Identifiable {
    case novels
    case manga

    var id: String { rawValue }

    var title: String {
        switch self {
        case .novels: "Light Novels"
        case .manga: "Manga"
        }
    }

    var contentKind: ContentKind {
        switch self {
        case .novels: .novel
        case .manga: .manga
        }
    }
}

struct BrowseView: View {
    @Environment(PluginManager.self) private var pluginManager
    @Environment(SourceManager.self) private var sourceManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage("browse.kind") private var kindRaw = BrowseKind.novels.rawValue
    @State private var searchText = ""
    @State private var selectedLanguage: String?
    @State private var initializedLanguage = false

    private var kind: BrowseKind {
        BrowseKind(rawValue: kindRaw) ?? .novels
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Browse")
                .navigationDestination(for: PluginListItem.self) { plugin in
                    SourceDetailView(
                        sourceKey: SourceKey.make(kind: .novel, id: plugin.id),
                        title: plugin.name
                    )
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if kind == .novels { globalSearchButton }
                }
                .task { await loadPlugins() }
                .refreshable { await loadPlugins(forceRefresh: true) }
                .overlay {
                    if kind == .novels && pluginManager.isLoading && pluginManager.plugins.isEmpty {
                        LoadingView(message: "Fetching sources...")
                    }
                }
        }
    }

    // MARK: - Browse controls

    private var browseControls: some View {
        VStack(spacing: 10) {
            kindSwitcher
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(searchPrompt, text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(Color(uiColor: .systemGray6), in: RoundedRectangle(cornerRadius: 14))
        }
        .frame(maxWidth: .infinity)
    }

    private var kindSwitcher: some View {
        GeometryReader { geometry in
            let segmentWidth = (geometry.size.width - 12) / 2
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white)
                    .frame(width: segmentWidth, height: 36)
                    .offset(x: kind == .novels ? 4 : segmentWidth + 8)
                    .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.78), value: kindRaw)

                HStack(spacing: 4) {
                    ForEach(BrowseKind.allCases) { option in
                        let isSelected = kind == option
                        Button {
                            guard kind != option else { return }
                            kindRaw = option.rawValue
                        } label: {
                            Text(option.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(isSelected ? Color.black : Color.primary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .frame(height: 44)
        .background(Color(uiColor: .systemGray6), in: RoundedRectangle(cornerRadius: 14))
        .sensoryFeedback(.selection, trigger: kindRaw)
    }

    private var globalSearchButton: some View {
        HStack {
            Spacer()
            NavigationLink {
                GlobalSearchView()
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 19, weight: .semibold))
                    .frame(width: 54, height: 54)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .accessibilityLabel("Global Search")
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }

    private var searchPrompt: String {
        kind == .novels ? "Search novel sources" : "Search manga sources"
    }

    // MARK: - Content

    private var content: some View {
        List {
            browseControls
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 12, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            if kind == .novels {
                novelSourcesContent
            } else {
                mangaSourcesContent
            }
        }
    }

    @ViewBuilder
    private var novelSourcesContent: some View {
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

    @ViewBuilder
    private var mangaSourcesContent: some View {
        if mangaSources.isEmpty {
            Section {
                ContentUnavailableView(
                    "No manga sources",
                    systemImage: "books.vertical",
                    description: Text("Install an extension bundle to read manga.")
                )
            }
        } else {
            Section("Installed Extensions") {
                ForEach(mangaSources, id: \.key) { source in
                    NavigationLink {
                        SourceDetailView(sourceKey: source.key, title: source.name)
                    } label: {
                        mangaRow(source)
                    }
                }
            }
        }
    }

    private func mangaRow(_ source: any CatalogSource) -> some View {
        HStack(spacing: 12) {
            SourceIconView(source: source, size: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(source.name)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if !source.lang.isEmpty {
                        Text(source.lang.uppercased())
                    }
                    if !source.supportsLatest {
                        Text("·")
                        Text("Popular only")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Filtering

    private var mangaSources: [any CatalogSource] {
        let all = sourceManager.sources(of: .manga)
        guard !searchText.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
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
        if !initializedLanguage, !pluginManager.plugins.isEmpty {
            selectedLanguage = pluginManager.availableLanguages.first {
                ["en", "english"].contains($0.lowercased())
            }
            initializedLanguage = true
        }
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
            .padding(.top, 2)
            .padding(.bottom, 2)
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: -8, trailing: 0))
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
                .frame(minHeight: 44)
                .foregroundStyle(isSelected ? Color.black : Color.primary)
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.white : Color(uiColor: .systemGray6), in: Capsule())
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
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
