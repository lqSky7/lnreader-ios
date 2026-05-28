// LibraryView.swift
// Main library screen showing saved novels with search, categories, and sorting.

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(PluginManager.self) private var pluginManager
    @Environment(LibraryManager.self) private var libraryManager

    @Query(
        filter: #Predicate<Novel> { $0.inLibrary },
        sort: \Novel.name
    )
    private var novels: [Novel]
    @Query(sort: \Category.sort) private var categories: [Category]

    @State private var searchText = ""
    @State private var selectedCategory: Category?
    @AppStorage("general.defaultSortOrder") private var sortOrder: SortOrder = .lastRead
    @AppStorage("general.defaultSortDirection") private var sortDirection: SortDirection = .descending
    @AppStorage("general.defaultDisplayMode") private var displayMode: DisplayMode = .comfortable
    @AppStorage("general.confirmRemove") private var confirmRemove = true

    @State private var isEditingLibrary = false
    @State private var draggedItem: Novel? = nil
    @State private var novelToDelete: Novel? = nil
    @State private var showDeleteConfirmation = false
    @State private var navigationPath = NavigationPath()
    @State private var showFileImporter = false
    @State private var importError: String?
    @State private var showImportError = false

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if filteredNovels.isEmpty {
                    EmptyStateView(
                        icon: "books.vertical",
                        title: "Your Library is Empty",
                        subtitle: "Browse sources to find novels, or import an EPUB file.",
                        actionTitle: "Import EPUB",
                        action: { showFileImporter = true }
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
                            LibraryListView(
                                novels: filteredNovels,
                                isEditing: isEditingLibrary,
                                draggedItem: $draggedItem,
                                onReorder: { reorderNovels(dragged: $0, target: $1) },
                                onDelete: { novel in
                                    if confirmRemove {
                                        novelToDelete = novel
                                        showDeleteConfirmation = true
                                    } else {
                                        libraryManager.removeFromLibrary(novel: novel, context: modelContext)
                                    }
                                },
                                onStartEditing: { startEditing() },
                                onSelect: { novel in
                                    navigationPath.append(novel)
                                }
                            )
                        default:
                            LibraryGridView(
                                novels: filteredNovels,
                                displayMode: displayMode,
                                isEditing: isEditingLibrary,
                                draggedItem: $draggedItem,
                                onReorder: { reorderNovels(dragged: $0, target: $1) },
                                onDelete: { novel in
                                    if confirmRemove {
                                        novelToDelete = novel
                                        showDeleteConfirmation = true
                                    } else {
                                        libraryManager.removeFromLibrary(novel: novel, context: modelContext)
                                    }
                                },
                                onStartEditing: { startEditing() },
                                onSelect: { novel in
                                    navigationPath.append(novel)
                                }
                            )
                        }
                    }
                    .immediateScrollTouches()
                    .refreshable {
                        await libraryManager.updateLibrary(context: modelContext, pluginManager: pluginManager)
                    }
                }
            }
            .navigationTitle("Library")
            .searchable(text: $searchText, prompt: "Search library")
            .toolbar {
                if isEditingLibrary {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            withAnimation {
                                isEditingLibrary = false
                            }
                        }
                        .bold()
                    }
                } else {
                    LibraryToolbar(
                        sortOrder: $sortOrder,
                        sortDirection: $sortDirection,
                        displayMode: $displayMode,
                        onImport: { showFileImporter = true }
                    )
                }
            }
            .onChange(of: isEditingLibrary) { _, editing in
                if !editing {
                    // Clean up drag state when leaving edit mode to prevent
                    // ghost state from affecting the next edit session.
                    draggedItem = nil
                    // Commit any pending position changes.
                    commitLibraryPositions()
                }
            }
            .alert("Remove from Library?", isPresented: $showDeleteConfirmation, presenting: novelToDelete) { novel in
                Button("Cancel", role: .cancel) {}
                Button("Remove", role: .destructive) {
                    libraryManager.removeFromLibrary(novel: novel, context: modelContext)
                }
            } message: { novel in
                Text("Are you sure you want to remove '\(novel.name)' from your library?")
            }
            .navigationDestination(for: Novel.self) { novel in
                NovelDetailView(novel: novel)
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [UTType(filenameExtension: "epub")].compactMap { $0 },
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    Task {
                        let accessing = url.startAccessingSecurityScopedResource()
                        defer {
                            if accessing {
                                url.stopAccessingSecurityScopedResource()
                            }
                        }
                        do {
                            try LocalBookManager.importEPUB(at: url, context: modelContext)
                        } catch {
                            importError = error.localizedDescription
                            showImportError = true
                        }
                    }
                case .failure(let error):
                    importError = error.localizedDescription
                    showImportError = true
                }
            }
            .alert("Import Error", isPresented: $showImportError, presenting: importError) { _ in
                Button("OK", role: .cancel) {}
            } message: { error in
                Text(error)
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
        case .custom:
            sorted = novels.sorted { $0.libraryPosition < $1.libraryPosition }
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

    private func startEditing() {
        withAnimation {
            isEditingLibrary = true
            if sortOrder != .custom {
                sortOrder = .custom
                sortDirection = .ascending
            }
        }
    }

    private func reorderNovels(dragged: Novel, target: Novel) {
        let visibleList = filteredNovels
        guard let fromIndex = visibleList.firstIndex(of: dragged),
              let toIndex = visibleList.firstIndex(of: target),
              fromIndex != toIndex else { return }

        // Lightweight swap: only update the two novels' positions so the
        // ForEach re-sorts without rebuilding the entire array each frame.
        withAnimation(.easeInOut(duration: 0.2)) {
            let draggedPos = dragged.libraryPosition
            dragged.libraryPosition = target.libraryPosition
            target.libraryPosition = draggedPos
        }
    }

    /// Normalise all library positions to sequential integers after a drag
    /// session ends. This prevents gaps/collisions from accumulating.
    private func commitLibraryPositions() {
        let ordered = filteredNovels.sorted { $0.libraryPosition < $1.libraryPosition }
        for (index, novel) in ordered.enumerated() {
            novel.libraryPosition = index
        }
        try? modelContext.save()
    }
}
