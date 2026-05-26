// GlobalSearchView.swift
// Search across all installed source plugins concurrently.

import SwiftUI

struct GlobalSearchView: View {
    @Environment(PluginManager.self) private var pluginManager
    @State private var searchText = ""
    @State private var results: [SourceSearchResult] = []
    @State private var isSearching = false

    var body: some View {
        ScrollView {
            if results.isEmpty && !isSearching {
                EmptyStateView(
                    icon: "magnifyingglass",
                    title: "Global Search",
                    subtitle: "Search across all installed sources at once."
                )
                .padding(.top, 100)
            }

            LazyVStack(alignment: .leading, spacing: 24) {
                ForEach(results) { result in
                    if !result.novels.isEmpty {
                        SourceResultSection(result: result)
                    }
                }
            }
            .padding(.horizontal)

            if isSearching {
                LoadingView(message: "Searching \(pluginManager.installedPlugins.count) sources...")
                    .padding()
            }
        }
        .navigationTitle("Global Search")
        .searchable(text: $searchText, prompt: "Search all sources")
        .onSubmit(of: .search) {
            Task { await performSearch() }
        }
    }

    // MARK: - Search

    private func performSearch() async {
        guard !searchText.isEmpty else { return }
        isSearching = true
        results = []

        let query = searchText
        let plugins = pluginManager.installedPlugins

        await withTaskGroup(of: SourceSearchResult?.self) { group in
            for (id, plugin) in plugins {
                group.addTask {
                    do {
                        let novels = try await plugin.searchNovels(query: query, page: 1)
                        return SourceSearchResult(
                            pluginId: id,
                            pluginName: plugin.name,
                            novels: novels
                        )
                    } catch {
                        return nil
                    }
                }
            }

            for await result in group {
                if let result, !result.novels.isEmpty {
                    results.append(result)
                }
            }
        }

        results.sort { $0.novels.count > $1.novels.count }
        isSearching = false
    }
}

// MARK: - Result Models

struct SourceSearchResult: Identifiable {
    let id = UUID()
    let pluginId: String
    let pluginName: String
    let novels: [PartialNovel]
}

// MARK: - Result Section

struct SourceResultSection: View {
    let result: SourceSearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(result.pluginName)
                .font(Typography.title)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(result.novels.prefix(10)) { novel in
                        NavigationLink {
                            NovelDetailView(
                                partialNovel: novel,
                                pluginId: result.pluginId
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                NovelCoverView(
                                    url: novel.cover,
                                    aspectRatio: LayoutConstants.coverAspectRatio
                                )
                                .frame(width: 120)

                                Text(novel.name)
                                    .font(Typography.small)
                                    .lineLimit(2)
                                    .frame(width: 120, alignment: .leading)
                                    .foregroundStyle(.primary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
