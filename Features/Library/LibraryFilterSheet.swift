// LibraryFilterSheet.swift
// Tri-state filter rows for the library: tap cycles off, include, exclude.

import SwiftUI

struct LibraryFilterSheet: View {
    @Binding var filter: LibraryFilter
    let scopeName: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row("Downloaded", systemImage: "arrow.down.circle", state: $filter.downloaded)
                    row("Unread", systemImage: "eye.slash", state: $filter.unread)
                    row("Started", systemImage: "book", state: $filter.started)
                    row("Completed", systemImage: "checkmark.seal", state: $filter.completed)
                    row("Tracked", systemImage: "chart.bar", state: $filter.tracked)
                } footer: {
                    Text("Filters apply to \(scopeName) only. Tap to require, tap again to exclude.")
                }
            }
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") { filter = LibraryFilter() }
                        .disabled(!filter.isActive)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.bold()
                }
            }
        }
    }

    private func row(_ title: String, systemImage: String, state: Binding<TriState>) -> some View {
        Button {
            state.wrappedValue = state.wrappedValue.next
        } label: {
            HStack {
                Label(title, systemImage: systemImage)
                    .foregroundStyle(.primary)
                Spacer()
                switch state.wrappedValue {
                case .off:
                    Image(systemName: "circle").foregroundStyle(.tertiary)
                case .include:
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                case .exclude:
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                }
            }
        }
        .accessibilityValue(state.wrappedValue.rawValue)
    }
}
