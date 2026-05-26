// SourceDetailView.swift
// Browse novels from a single installed source with search and pagination.

import SwiftUI

struct SourceDetailView: View {
    let plugin: PluginListItem
    @Environment(PluginManager.self) private var pluginManager

    @State private var novels: [PartialNovel] = []
    @State private var searchText = ""
    @State private var currentPage = 1
    @State private var isLoading = false
    @State private var isSearching = false
    @State private var hasMore = true

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: LayoutConstants.gridItemMinSize), spacing: 12)]
    }

    var body: some View {
        ScrollView {
            if novels.isEmpty && !isLoading {
                EmptyStateView(
                    icon: "books.vertical",
                    title: "No Novels Found",
                    subtitle: isSearching ? "Try a different search term." : "This source may be unavailable."
                )
                .padding(.top, 100)
            }

            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(novels) { novel in
                    NavigationLink {
                        NovelDetailView(partialNovel: novel, pluginId: plugin.id)
                    } label: {
                        BrowseNovelCell(novel: novel)
                    }
                    .buttonStyle(.plain)
                }

                if hasMore && !novels.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                        .task { await loadMore() }
                }
            }
            .padding(.horizontal)
        }
        .navigationTitle(plugin.name)
        .searchable(text: $searchText, prompt: "Search \(plugin.name)")
        .onSubmit(of: .search) {
            Task { await search() }
        }
        .onChange(of: searchText) { _, newValue in
            if newValue.isEmpty {
                isSearching = false
                Task { await loadPopular() }
            }
        }
        .overlay {
            if isLoading && novels.isEmpty {
                LoadingView(message: "Loading novels...")
            }
        }
        .task { await loadPopular() }
    }

    // MARK: - Data Loading

    private func loadPopular() async {
        guard let source = pluginManager.plugin(for: plugin.id) else { return }
        isLoading = true
        currentPage = 1
        hasMore = true

        do {
            novels = try await source.popularNovels(page: 1)
            hasMore = !novels.isEmpty
        } catch {
            print("⚠️ Failed to load popular novels: \(error)")
        }
        isLoading = false
    }

    private func loadMore() async {
        guard let source = pluginManager.plugin(for: plugin.id), hasMore else { return }
        currentPage += 1

        do {
            let nextPage: [PartialNovel]
            if isSearching {
                nextPage = try await source.searchNovels(query: searchText, page: currentPage)
            } else {
                nextPage = try await source.popularNovels(page: currentPage)
            }
            if nextPage.isEmpty {
                hasMore = false
            } else {
                novels.append(contentsOf: nextPage)
            }
        } catch {
            hasMore = false
        }
    }

    private func search() async {
        guard let source = pluginManager.plugin(for: plugin.id) else { return }
        guard !searchText.isEmpty else { return }
        isLoading = true
        isSearching = true
        currentPage = 1

        do {
            novels = try await source.searchNovels(query: searchText, page: 1)
            hasMore = !novels.isEmpty
        } catch {
            print("⚠️ Search failed: \(error)")
        }
        isLoading = false
    }
}

// MARK: - Browse Novel Cell

struct BrowseNovelCell: View {
    let novel: PartialNovel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            NovelCoverView(
                url: novel.cover,
                aspectRatio: LayoutConstants.coverAspectRatio
            )

            Text(novel.name)
                .font(Typography.caption)
                .lineLimit(2)
                .foregroundStyle(.primary)
        }
    }
}
