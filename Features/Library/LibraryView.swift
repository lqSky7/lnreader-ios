// LibraryView.swift
// Main library screen showing saved novels with search, categories, and sorting.

import SwiftData
import SwiftUI

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<Novel> { $0.inLibrary },
        sort: \Novel.name
    )
    private var novels: [Novel]
    @Query(sort: \Category.sort) private var categories: [Category]

    @State private var searchText = ""
    @State private var selectedCategory: Category?
    @State private var sortOrder: SortOrder = .lastRead
    @State private var sortDirection: SortDirection = .descending
    @State private var displayMode: DisplayMode = .comfortable

    var body: some View {
        NavigationStack {
            Group {
                if filteredNovels.isEmpty {
                    EmptyStateView(
                        icon: "books.vertical",
                        title: "Your Library is Empty",
                        subtitle: "Browse sources to find novels and add them to your library."
                    )
                } else {
                    ScrollView {
                        if !categories.isEmpty {
                            CategoryTabView(
                                categories: categories,
                                selectedCategory: $selectedCategory
                            )
                            .padding(.horizontal)
                        }

                        switch displayMode {
                        case .list:
                            LibraryListView(novels: filteredNovels)
                        default:
                            LibraryGridView(
                                novels: filteredNovels,
                                displayMode: displayMode
                            )
                        }
                    }
                }
            }
            .navigationTitle("Library")
            .searchable(text: $searchText, prompt: "Search library")
            .toolbar {
                LibraryToolbar(
                    sortOrder: $sortOrder,
                    sortDirection: $sortDirection,
                    displayMode: $displayMode
                )
            }
        }
    }

    // MARK: - Filtering & Sorting

    private var filteredNovels: [Novel] {
        var result = novels

        if let category = selectedCategory {
            result = result.filter { $0.categories.contains(category) }
        }

        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
            }
        }

        return sortedNovels(result)
    }

    private func sortedNovels(_ novels: [Novel]) -> [Novel] {
        let sorted: [Novel]
        switch sortOrder {
        case .alphabetical:
            sorted = novels.sorted {
                $0.name.localizedCompare($1.name) == .orderedAscending
            }
        case .lastRead:
            sorted = novels.sorted {
                ($0.lastReadAt ?? .distantPast) > ($1.lastReadAt ?? .distantPast)
            }
        case .lastUpdated:
            sorted = novels.sorted {
                ($0.lastUpdatedAt ?? .distantPast) > ($1.lastUpdatedAt ?? .distantPast)
            }
        case .totalChapters:
            sorted = novels.sorted { $0.totalChapters > $1.totalChapters }
        case .unread:
            sorted = novels.sorted { $0.chaptersUnread > $1.chaptersUnread }
        case .dateAdded:
            sorted = novels.sorted { $0.dateAdded > $1.dateAdded }
        }
        return sortDirection.isAscending ? sorted.reversed() : sorted
    }
}
