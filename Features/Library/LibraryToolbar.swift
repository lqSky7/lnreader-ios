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
                // The filled symbol's glyph is a cut-out, which the toolbar
                // renders as a plain white disc; tint the outline instead.
                Label("Filter, sort and display", systemImage: "line.3.horizontal.decrease.circle")
                    .foregroundStyle(isCustomised ? Color.accentColor : Color.primary)
            }

            Menu {
                Button(action: onImport) {
                    Label("Import EPUB", systemImage: "square.and.arrow.down")
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
        }
    }
}
