// SourceDetailView.swift
// Browse one source with search and pagination.
//
// Talks to the v2 source layer: the source key only identifies which source to ask for,
// everything else goes through `CatalogSource`.

import SwiftUI

struct SourceDetailView: View {
    @Namespace private var bookTransitions
    let sourceKey: String
    let title: String
    @Environment(SourceManager.self) private var sourceManager

    @State private var entries: [SourceEntry] = []
    @State private var searchText = ""
    @State private var currentPage = 1
    @State private var isLoading = false
    @State private var isSearching = false
    @State private var hasMore = true

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: LayoutConstants.gridItemMinSize), spacing: 12)]
    }

    /// `CatalogSource`, not `NovelSource`: browse is identical for both kinds.
    private var source: (any CatalogSource)? {
        sourceManager.source(forKey: sourceKey)
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(entries) { entry in
                    NavigationLink {
                        NovelDetailView(sourceEntry: entry)
                            .bookZoom(from: entry.url, in: bookTransitions)
                    } label: {
                        BrowseEntryCell(entry: entry, transitionNamespace: bookTransitions)
                    }
                    .buttonStyle(.plain)
                }

                if hasMore && !entries.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                        .task { await loadMore() }
                }
            }
            .padding(.horizontal)
        }
        .navigationTitle(title)
        .searchable(text: $searchText, prompt: "Search \(title)")
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
            if isLoading && entries.isEmpty {
                LoadingView(message: "Loading...")
            } else if entries.isEmpty && !isLoading {
                if isSearching {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    ContentUnavailableView(
                        "No Results",
                        systemImage: "books.vertical",
                        description: Text("This source is not installed, or returned nothing.")
                    )
                }
            }
        }
        .task { await loadPopular() }
        .toolbar {
            if let site = CommentSite.site(for: SourceKey.identifier(from: sourceKey)) {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink(destination: NovelFireLoginView(onLoginSuccess: {
                        Task { await loadPopular() }
                    }, site: site)) {
                        Label("Login", systemImage: "person.badge.key")
                    }
                }
            }
        }
    }

    // MARK: - Data Loading

    /// Filters are not surfaced in the UI yet; the protocol takes a state so the
    /// browse redesign can add a filter sheet without touching this call site.
    private var emptyFilters: FilterState { FilterState() }

    private func loadPopular() async {
        guard let source else { return }
        isLoading = true
        currentPage = 1
        hasMore = true

        do {
            let page = try await source.popular(page: 1, filters: emptyFilters)
            entries = page.entries
            hasMore = page.hasNextPage
        } catch {
            print("⚠️ Failed to load popular entries: \(error)")
        }
        isLoading = false
    }

    private func loadMore() async {
        guard let source, hasMore else { return }
        currentPage += 1

        do {
            let page: EntriesPage
            if isSearching {
                page = try await source.search(query: searchText, page: currentPage, filters: emptyFilters)
            } else {
                page = try await source.popular(page: currentPage, filters: emptyFilters)
            }
            if page.entries.isEmpty {
                hasMore = false
            } else {
                entries.append(contentsOf: page.entries)
                hasMore = page.hasNextPage
            }
        } catch {
            hasMore = false
        }
    }

    private func search() async {
        guard let source, !searchText.isEmpty else { return }
        isLoading = true
        isSearching = true
        currentPage = 1

        do {
            let page = try await source.search(query: searchText, page: 1, filters: emptyFilters)
            entries = page.entries
            hasMore = page.hasNextPage
        } catch {
            print("⚠️ Search failed: \(error)")
        }
        isLoading = false
    }
}

// MARK: - Browse Entry Cell

struct BrowseEntryCell: View {
    let entry: SourceEntry
    var transitionNamespace: Namespace.ID? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            NovelCoverView(
                url: entry.thumbnailURL,
                aspectRatio: LayoutConstants.coverAspectRatio
            )
            .bookTransitionSource(entry.url, in: transitionNamespace)

            Text(entry.title)
                .font(Typography.caption)
                .lineLimit(2)
                .foregroundStyle(.primary)
        }
    }
}
