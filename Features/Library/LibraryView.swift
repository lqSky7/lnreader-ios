// LibraryView.swift
// Main library screen showing saved novels with search, categories, and sorting.

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var modelContext
    @Environment(SourceManager.self) private var sourceManager
    @Environment(LibraryManager.self) private var libraryManager

    @Query(
        filter: #Predicate<Entry> { $0.inLibrary },
        sort: \Entry.title
    )
    private var novels: [Entry]
    @Query(sort: \Category.order) private var categories: [Category]

    @Namespace private var bookTransitions
    @State private var lastReorderTarget: PersistentIdentifier?
    @State private var editingOrder: [PersistentIdentifier] = []
    @State private var searchText = ""
    @State private var selectedCategory: Category?
    @AppStorage("general.defaultSortOrder") private var sortOrder: SortOrder = .lastRead
    @AppStorage("general.defaultSortDirection") private var sortDirection: SortDirection = .descending
    @AppStorage("general.defaultDisplayMode") private var displayMode: DisplayMode = .comfortable
    @AppStorage("general.confirmRemove") private var confirmRemove = true
    @AppStorage("library.kindFilter") private var kindFilterRaw = LibraryKindFilter.all.rawValue

    @State private var isEditingLibrary = false
    @State private var draggedItem: Entry? = nil
    @State private var novelToDelete: Entry? = nil
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
                        if showsKindPicker {
                            Picker("Content", selection: $kindFilterRaw) {
                                ForEach(LibraryKindFilter.allCases) { option in
                                    Text(option.title).tag(option.rawValue)
                                }
                            }
                            .pickerStyle(.segmented)
                            .padding(.horizontal)
                            .padding(.top, 4)
                        }

                        if !categories.isEmpty {
                            CategoryTabView(
                                categories: categories,
                                selectedCategory: $selectedCategory
                            )
                            .padding(.horizontal)
                        }

                        libraryContent
                    }
                    .immediateScrollTouches()
                    .onDrop(of: [UTType.text], isTargeted: nil) { _ in
                        guard draggedItem != nil else { return false }
                        draggedItem = nil
                        return true
                    }
                    .refreshable {
                        await libraryManager.updateLibrary(context: modelContext, sourceManager: sourceManager)
                    }
                }
            }
            .navigationTitle("Library")
            .searchable(text: $searchText, prompt: "Search library")
            .toolbar {
                if isEditingLibrary {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            withAnimation(AppMotion.gentle(reduceMotion: reduceMotion)) {
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
                    libraryManager.removeFromLibrary(entry: novel, context: modelContext)
                }
            } message: { novel in
                Text("Are you sure you want to remove '\(novel.displayTitle)' from your library?")
            }
            .navigationDestination(for: Entry.self) { novel in
                NovelDetailView(entry: novel)
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

    // MARK: - Content

    /// Split out of `body`: two 15-line cell constructors inline pushed the
    /// view builder past what the type checker will infer in reasonable time.
    @ViewBuilder
    private var libraryContent: some View {
        if displayMode == .list {
            LibraryListView(
                transitionNamespace: bookTransitions,
                novels: filteredNovels,
                isEditing: isEditingLibrary,
                draggedItem: $draggedItem,
                onReorder: handleReorder,
                onDelete: handleDelete,
                onStartEditing: { startEditing() },
                onSelect: handleSelect
            )
        } else {
            LibraryGridView(
                transitionNamespace: bookTransitions,
                novels: filteredNovels,
                displayMode: displayMode,
                isEditing: isEditingLibrary,
                draggedItem: $draggedItem,
                onReorder: handleReorder,
                onDelete: handleDelete,
                onStartEditing: { startEditing() },
                onSelect: handleSelect
            )
        }
    }

    private func handleReorder(_ dragged: Entry, _ target: Entry) {
        reorderNovels(dragged: dragged, target: target)
    }

    private func handleDelete(_ novel: Entry) {
        if confirmRemove {
            novelToDelete = novel
            showDeleteConfirmation = true
        } else {
            libraryManager.removeFromLibrary(entry: novel, context: modelContext)
        }
    }

    private func handleSelect(_ novel: Entry) {
        navigationPath.append(novel)
    }

    // MARK: - Filtering & Sorting

    private var kindFilter: LibraryKindFilter {
        LibraryKindFilter(rawValue: kindFilterRaw) ?? .all
    }

    /// Only offer the split when the library actually holds both kinds.
    private var showsKindPicker: Bool {
        novels.contains { $0.kind == .novel } && novels.contains { $0.kind == .manga }
    }

    private var filteredNovels: [Entry] {
        var result = novels

        switch kindFilter {
        case .all: break
        case .novels: result = result.filter { $0.kind == .novel }
        case .manga: result = result.filter { $0.kind == .manga }
        }

        if let category = selectedCategory {
            result = result.filter { $0.categories.contains(category) }
        }

        if !searchText.isEmpty {
            result = result.filter {
                $0.displayTitle.localizedCaseInsensitiveContains(searchText)
            }
        }

        return sortedNovels(result)
    }

    private func sortedNovels(_ novels: [Entry]) -> [Entry] {
        // Precompute per-novel chapter stats ONCE. The old code called
        // `chaptersUnread` / `totalChapters` inside the sort comparator,
        // re-faulting + re-scanning every novel's chapter list O(log n) times.
        var unreadByID: [PersistentIdentifier: Int] = [:]
        var totalByID: [PersistentIdentifier: Int] = [:]
        let needsCounts = (sortOrder == .unread || sortOrder == .totalChapters)
        if needsCounts {
            for novel in novels {
                unreadByID[novel.persistentModelID] = novel.unreadCount
                totalByID[novel.persistentModelID] = novel.totalChapterCount
            }
        }
        let sorted: [Entry]
        switch sortOrder {
        case .custom:
            if isEditingLibrary {
                let ranks = Dictionary(uniqueKeysWithValues: editingOrder.enumerated().map { ($1, $0) })
                return novels.sorted { (ranks[$0.persistentModelID] ?? Int.max) < (ranks[$1.persistentModelID] ?? Int.max) }
            }
            let ordered = novels.sorted {
                if $0.libraryOrder != $1.libraryOrder { return $0.libraryOrder < $1.libraryOrder }
                return $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending
            }
            return sortDirection.isAscending ? ordered : ordered.reversed()
        case .alphabetical:
            sorted = novels.sorted {
                $0.displayTitle.localizedCompare($1.displayTitle) == .orderedAscending
            }
        case .lastRead:
            sorted = novels.sorted {
                ($0.lastReadAt ?? .distantPast) > ($1.lastReadAt ?? .distantPast)
            }
        case .lastUpdated:
            sorted = novels.sorted {
                ($0.lastUpdate ?? .distantPast) > ($1.lastUpdate ?? .distantPast)
            }
        case .totalChapters:
            sorted = novels.sorted {
                (totalByID[$0.persistentModelID] ?? $0.totalChapterCount)
                    > (totalByID[$1.persistentModelID] ?? $1.totalChapterCount)
            }
        case .unread:
            sorted = novels.sorted {
                (unreadByID[$0.persistentModelID] ?? $0.unreadCount)
                    > (unreadByID[$1.persistentModelID] ?? $1.unreadCount)
            }
        case .dateAdded:
            sorted = novels.sorted { $0.dateAdded > $1.dateAdded }
        }
        return sortDirection.isAscending ? sorted.reversed() : sorted
    }

    private func startEditing() {
        let order = sortedNovels(novels).map(\.persistentModelID)
        withAnimation(AppMotion.gentle(reduceMotion: reduceMotion)) {
            editingOrder = order
            lastReorderTarget = nil
            sortOrder = .custom
            sortDirection = .ascending
            isEditingLibrary = true
        }
    }

    private func reorderNovels(dragged: Entry, target: Entry) {
        guard lastReorderTarget != target.persistentModelID,
              dragged.persistentModelID != target.persistentModelID else { return }
        lastReorderTarget = target.persistentModelID
        withAnimation(AppMotion.gentle(reduceMotion: reduceMotion)) {
            editingOrder = LibraryReordering.move(dragged.persistentModelID, to: target.persistentModelID, in: editingOrder)
        }
    }

    private func commitLibraryPositions(clearOrder: Bool = true) {
        let byID = Dictionary(uniqueKeysWithValues: novels.map { ($0.persistentModelID, $0) })
        let current = Set(editingOrder)
        let order = editingOrder + novels.filter { !current.contains($0.persistentModelID) }.map(\.persistentModelID)
        for (index, id) in order.enumerated() { byID[id]?.libraryOrder = index }
        try? modelContext.save()
        if clearOrder { editingOrder = [] }
    }
}

/// Library split between light novels and manga.
enum LibraryKindFilter: String, CaseIterable, Identifiable {
    case all
    case novels
    case manga

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .novels: "Novels"
        case .manga: "Manga"
        }
    }
}
