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
            Button(action: onShowFilters) {
                Label("Filter", systemImage: activeFilterCount > 0
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle")
            }

            // Sort, display and import share one menu: the library chrome is
            // used far more than it is configured.
            Menu {
                sortMenu
                displayMenu
                Divider()
                Button(action: onImport) {
                    Label("Import EPUB", systemImage: "square.and.arrow.down")
                }
            } label: {
                Label("View options", systemImage: "ellipsis.circle")
            }
        }
    }

    private var orderBinding: Binding<SortOrder> {
        Binding(
            get: { sort.order },
            set: { if $0 != sort.order { sort.select($0) } }
        )
    }

    private var directionBinding: Binding<SortDirection> {
        Binding(get: { sort.direction }, set: { sort.direction = $0 })
    }

    private var sortMenu: some View {
        Menu {
            Section("Sort \(scopeName)") {
                Picker("Sort by", selection: orderBinding) {
                    ForEach(SortOrder.allCases) { order in
                        Text(order.displayName).tag(order)
                    }
                }
                .pickerStyle(.inline)
            }

            if sort.order != .custom {
                Picker("Direction", selection: directionBinding) {
                    Text(sort.order.directionLabels.ascending).tag(SortDirection.ascending)
                    Text(sort.order.directionLabels.descending).tag(SortDirection.descending)
                }
                .pickerStyle(.inline)
            }

            if sort.order.supportsEmptyLast {
                Toggle("Empty ones last", isOn: $sort.emptyLast)
            }

            if hasSortOverride {
                Button("Use default sort", systemImage: "arrow.uturn.backward", action: onResetSort)
            }
        } label: {
            Label("Sort: \(sort.order.displayName)", systemImage: "arrow.up.arrow.down")
        }
    }

    private var displayMenu: some View {
        Menu {
            Picker("Display", selection: $displayMode) {
                ForEach(DisplayMode.allCases) { mode in
                    Label(mode.displayName, systemImage: mode.iconName).tag(mode)
                }
            }
            .pickerStyle(.inline)
            if hasDisplayOverride {
                Button("Use default display", systemImage: "arrow.uturn.backward", action: onResetDisplay)
            }
        } label: {
            Label("Display: \(displayMode.displayName)", systemImage: displayMode.iconName)
        }
    }
}
