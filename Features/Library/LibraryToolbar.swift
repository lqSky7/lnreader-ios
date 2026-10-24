// LibraryToolbar.swift
// Toolbar with sort, filter, and display mode controls for the library.

import SwiftUI

struct LibraryToolbar: ToolbarContent {
    /// Filters on, or a sort other than the plain default: the button reads as
    /// "something is shaping this list".
    var isCustomised = false
    var onShowOptions: () -> Void = {}
    var onImport: () -> Void

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button(action: onShowOptions) {
                // The accent is plain white in dark mode, so tinting the icon
                // cannot show "on". The filled variant of the symbol does.
                Image(systemName: isCustomised
                      ? "line.3.horizontal.decrease.circle.fill"
                      : "line.3.horizontal.decrease")
            }
            .accessibilityLabel("Filter, sort and display")
            .accessibilityValue(isCustomised ? "Filters on" : "")

            Menu {
                Button(action: onImport) {
                    Label("Import EPUB", systemImage: "square.and.arrow.down")
                }
            } label: {
                Label("More", systemImage: "ellipsis")
            }
        }
    }
}
