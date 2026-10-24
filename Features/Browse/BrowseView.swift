// BrowseView.swift
// Sources, split by kind: light novels and manga are separate catalogues.
//
// Novels come from the JS plugin registry, manga from installed extension
// bundles, so the two lists have different sections and different empty states.
// A native segmented control in a glass top bar switches between them in place.

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
                .navigationBarTitleDisplayMode(.large)
                .searchable(
                    text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: searchPrompt
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .toolbar { toolbarContent }
                .navigationDestination(for: PluginListItem.self) { plugin in
                    SourceDetailView(
                        sourceKey: SourceKey.make(kind: .novel, id: plugin.id),
                        title: plugin.name
                    )
                }
                .task { await loadPlugins() }
                .overlay {
                    if kind == .novels && pluginManager.isLoading && pluginManager.plugins.isEmpty {
                        LoadingView(message: "Fetching sources...")
                    }
                }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if kind == .novels {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    GlobalSearchView()
                } label: {
                    Image(systemName: "text.magnifyingglass")
                }
                .accessibilityLabel("Search all sources")
            }
            if !pluginManager.availableLanguages.isEmpty {
                ToolbarItem(placement: .topBarTrailing) { languageMenu }
            }
        }
    }

    /// Language filter. A menu rather than a chip row: it is a rarely changed
    /// setting, and the chips pushed the sources down the screen.
    private var languageMenu: some View {
        Menu {
            Picker("Language", selection: $selectedLanguage) {
                Text("All Languages").tag(String?.none)
                ForEach(pluginManager.availableLanguages, id: \.self) { lang in
                    Text(lang).tag(String?.some(lang))
                }
            }
        } label: {
            Image(systemName: selectedLanguage == nil
                ? "line.3.horizontal.decrease"
                : "line.3.horizontal.decrease.circle.fill")
        }
        .accessibilityLabel("Language")
        .accessibilityValue(selectedLanguage ?? "All")
    }

    // MARK: - Kind switcher

    /// Native segmented control: on iOS 26 it renders as glass and morphs the
    /// selection for free. It floats in the top bar so the list scrolls under it.
    private var kindSwitcher: some View {
        Picker("Catalogue", selection: $kindRaw) {
            ForEach(BrowseKind.allCases) { option in
                Text(option.title).tag(option.rawValue)
            }
        }
        .pickerStyle(.segmented)
        .hapticFeedback(.selection, trigger: kindRaw)
    }

    private var searchPrompt: String {
        kind == .novels ? "Search novel sources" : "Search manga sources"
    }

    // MARK: - Content

    /// One list for both catalogues. The switcher is its first row, so it scrolls
    /// away with the content instead of pinning over the navigation bar's search
    /// field, and switching kinds cross-fades rows in place: no second scroll view, no
    /// whole-page transition to lag behind the gesture.
    private var content: some View {
        List {
            Section {
                kindSwitcher
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            if kind == .novels { novelSourcesContent } else { mangaSourcesContent }
        }
        .refreshable { await loadPlugins(forceRefresh: true) }
        // Rows cross-fade in place. Animating the rows, not the list, keeps the
        // scroll view (and the nav bar tracking it) alive, so it stays cheap.
        .animation(AppMotion.tabSwitch(reduceMotion: reduceMotion), value: kindRaw)
        .simultaneousGesture(kindSwipe)
    }

    /// Steps between catalogues on a clearly horizontal swipe. Only reacts when
    /// the drag ends, so vertical scrolling is never touched.
    private var kindSwipe: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                let dx = value.translation.width
                guard abs(dx) > 80, abs(dx) > abs(value.translation.height) * 2 else { return }
                let target: BrowseKind = dx < 0 ? .manga : .novels
                if target != kind { kindRaw = target.rawValue }
            }
    }

    @ViewBuilder
    private var novelSourcesContent: some View {
        if !installedPlugins.isEmpty {
            Section("Installed · \(installedPlugins.count)") {
                ForEach(installedPlugins) { plugin in
                    NavigationLink(value: plugin) {
                        SourceCard(plugin: plugin, isInstalled: true) {}
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            pluginManager.uninstallPlugin(id: plugin.id)
                        } label: {
                            Label("Uninstall", systemImage: "trash")
                        }
                    }
                }
            }
        }

        Section(selectedLanguage.map { "Available · \($0)" } ?? "Available") {
            ForEach(availablePlugins) { plugin in
                SourceCard(plugin: plugin, isInstalled: false) {
                    Task {
                        try? await pluginManager.installPlugin(id: plugin.id)
                    }
                }
            }
        }

        if installedPlugins.isEmpty && availablePlugins.isEmpty && !searchText.isEmpty {
            ContentUnavailableView.search(text: searchText)
                .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private var mangaSourcesContent: some View {
        if mangaSources.isEmpty {
            Section {
                if searchText.isEmpty {
                    ContentUnavailableView(
                        "No manga sources",
                        systemImage: "books.vertical",
                        description: Text("Install an extension bundle to read manga.")
                    )
                } else {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .listRowBackground(Color.clear)
        } else {
            Section("Installed · \(mangaSources.count)") {
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
            SourceIconView(source: source, size: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(source.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(mangaSubtitle(source))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private func mangaSubtitle(_ source: any CatalogSource) -> String {
        var parts: [String] = []
        if !source.lang.isEmpty { parts.append(source.lang.uppercased()) }
        if !source.supportsLatest { parts.append("Popular only") }
        return parts.joined(separator: " · ")
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
