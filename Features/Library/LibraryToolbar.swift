// LibraryToolbar.swift
// Toolbar with sort, filter, and display mode controls for the library.

import SwiftUI

struct LibraryToolbar: ToolbarContent {
    @Binding var sort: LibrarySort
    @Binding var displayMode: DisplayMode
    var hasDisplayOverride = false
    var onResetDisplay: () -> Void = {}
    /// Whether this category has its own sort rather than the global default.
    var hasSortOverride = false
    var scopeName = "All"
    var onResetSort: () -> Void = {}
    var activeFilterCount = 0
    var onShowFilters: () -> Void = {}
    var onImport: () -> Void

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button(action: onImport) {
                Label("Import EPUB", systemImage: "square.and.arrow.down")
            }

            Button(action: onShowFilters) {
                Label("Filter", systemImage: activeFilterCount > 0
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle")
            }

            Menu {
                Section("Display \(scopeName)") {
                    Picker("Display", selection: $displayMode) {
                        ForEach(DisplayMode.allCases) { mode in
                            Label(mode.displayName, systemImage: mode.iconName).tag(mode)
                        }
                    }
                }
                if hasDisplayOverride {
                    Button("Use default display", systemImage: "arrow.uturn.backward", action: onResetDisplay)
                }
            } label: {
                Label("Display", systemImage: displayMode.iconName)
            }

            Menu {
                Section("Sort \(scopeName)") {
                    ForEach(SortOrder.allCases) { order in
                        Button {
                            sort.select(order)
                        } label: {
                            HStack {
                                Text(order.displayName)
                                if sort.order == order {
                                    Image(systemName: sort.direction.isAscending
                                        ? "chevron.up" : "chevron.down")
                                }
                            }
                        }
                    }
                }
                if hasSortOverride {
                    Button("Use default sort", systemImage: "arrow.uturn.backward", action: onResetSort)
                }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
        }
    }
}
