// LibraryView.swift
// Main library screen showing saved novels with search, categories, and sorting.

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var modelContext
    @Environment(PluginManager.self) private var pluginManager
    @Environment(LibraryManager.self) private var libraryManager

    @Query(
        filter: #Predicate<Novel> { $0.inLibrary },
        sort: \Novel.name
    )
    private var novels: [Novel]
    @Query(sort: \Category.sort) private var categories: [Category]

    @Namespace private var bookTransitions
    @State private var lastReorderTarget: PersistentIdentifier?
    @State private var editingOrder: [PersistentIdentifier] = []
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
                        subtitle: "Browse sources to find novels, or import an EPUB or PDF.",
                        actionTitle: "Import book",
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
                                transitionNamespace: bookTransitions,
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
                                transitionNamespace: bookTransitions,
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
                    .onDrop(of: [UTType.text], isTargeted: nil) { _ in
                        guard draggedItem != nil else { return false }
                        draggedItem = nil
                        return true
                    }
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
            .onChange(of: scenePhase) { _, phase in
                if phase != .active && isEditingLibrary {
                    commitLibraryPositions(clearOrder: false)
                    draggedItem = nil
                }
            }
            .onChange(of: draggedItem) { _, item in
                lastReorderTarget = nil
                if item == nil && isEditingLibrary { commitLibraryPositions(clearOrder: false) }
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
                    .bookZoom(from: novel.persistentModelID, in: bookTransitions)
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [UTType(filenameExtension: "epub"), .pdf].compactMap { $0 },
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
                            if url.pathExtension.lowercased() == "pdf" { try LocalBookManager.importPDF(at: url, context: modelContext) }
                            else { try LocalBookManager.importEPUB(at: url, context: modelContext) }
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
        // Precompute per-novel chapter stats ONCE. The old code called
        // `chaptersUnread` / `totalChapters` inside the sort comparator,
        // re-faulting + re-scanning every novel's chapter list O(log n) times.
        var unreadByID: [PersistentIdentifier: Int] = [:]
        var totalByID: [PersistentIdentifier: Int] = [:]
        let needsCounts = (sortOrder == .unread || sortOrder == .totalChapters)
        if needsCounts {
            for novel in novels {
                unreadByID[novel.persistentModelID] = novel.chaptersUnread
                totalByID[novel.persistentModelID] = novel.totalChapters
            }
        }
        let sorted: [Novel]
        switch sortOrder {
        case .custom:
            if isEditingLibrary {
                let ranks = Dictionary(uniqueKeysWithValues: editingOrder.enumerated().map { ($1, $0) })
                return novels.sorted { (ranks[$0.persistentModelID] ?? Int.max) < (ranks[$1.persistentModelID] ?? Int.max) }
            }
            let ordered = novels.sorted {
                if $0.libraryPosition != $1.libraryPosition { return $0.libraryPosition < $1.libraryPosition }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            return sortDirection.isAscending ? ordered : ordered.reversed()
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
            sorted = novels.sorted {
                (totalByID[$0.persistentModelID] ?? $0.totalChapters)
                    > (totalByID[$1.persistentModelID] ?? $1.totalChapters)
            }
        case .unread:
            sorted = novels.sorted {
                (unreadByID[$0.persistentModelID] ?? $0.chaptersUnread)
                    > (unreadByID[$1.persistentModelID] ?? $1.chaptersUnread)
            }
        case .dateAdded:
            sorted = novels.sorted { $0.dateAdded > $1.dateAdded }
        }
        return sortDirection.isAscending ? sorted.reversed() : sorted
    }

    private func startEditing() {
        let order = sortedNovels(novels).map(\.persistentModelID)
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
            editingOrder = order
            lastReorderTarget = nil
            sortOrder = .custom
            sortDirection = .ascending
            isEditingLibrary = true
        }
    }

    private func reorderNovels(dragged: Novel, target: Novel) {
        guard lastReorderTarget != target.persistentModelID,
              dragged.persistentModelID != target.persistentModelID else { return }
        lastReorderTarget = target.persistentModelID
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) {
            editingOrder = LibraryReordering.move(dragged.persistentModelID, to: target.persistentModelID, in: editingOrder)
        }
    }

    private func commitLibraryPositions(clearOrder: Bool = true) {
        let byID = Dictionary(uniqueKeysWithValues: novels.map { ($0.persistentModelID, $0) })
        let current = Set(editingOrder)
        let order = editingOrder + novels.filter { !current.contains($0.persistentModelID) }.map(\.persistentModelID)
        for (index, id) in order.enumerated() { byID[id]?.libraryPosition = index }
        try? modelContext.save()
        if clearOrder { editingOrder = [] }
    }
}
