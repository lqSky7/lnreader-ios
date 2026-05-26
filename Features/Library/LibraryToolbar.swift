// LibraryToolbar.swift
// Toolbar with sort, filter, and display mode controls for the library.

import SwiftUI

struct LibraryToolbar: ToolbarContent {
    @Binding var sortOrder: SortOrder
    @Binding var sortDirection: SortDirection
    @Binding var displayMode: DisplayMode

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {

            Menu {
                ForEach(DisplayMode.allCases) { mode in
                    Button {
                        displayMode = mode
                    } label: {
                        Label(mode.displayName, systemImage: mode.iconName)
                    }
                }
            } label: {
                Label("Display", systemImage: displayMode.iconName)
            }

            Menu {
                ForEach(SortOrder.allCases) { order in
                    Button {
                        if sortOrder == order {
                            sortDirection.toggle()
                        } else {
                            sortOrder = order
                            sortDirection = .descending
                        }
                    } label: {
                        HStack {
                            Text(order.displayName)
                            if sortOrder == order {
                                Image(systemName: sortDirection.isAscending
                                    ? "chevron.up" : "chevron.down")
                            }
                        }
                    }
                }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
        }
    }
}
