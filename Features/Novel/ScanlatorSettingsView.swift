// ScanlatorSettingsView.swift - Visibility and priority for scanlators.
//
// Two independent features, deliberately not nested:
//
// - Hiding: switch a scanlator off and its chapters disappear from the list.
//   This works on its own.
// - Priority: merge chapters that share a number, keeping the scanlator highest
//   in the list. Only then does the order matter, so only then can rows be
//   dragged.
//
// The list used to be hidden entirely behind the priority toggle, which made
// "just hide this scanlator" impossible.

import SwiftUI

struct ScanlatorSettingsView: View {

    @Bindable var settings: ScanlatorSettings
    /// Scanlators present in this entry's chapter list.
    let scanlators: [String]

    @Environment(\.dismiss) private var dismiss

    private var rows: [String] {
        settings.orderedScanlators(from: scanlators)
    }

    private var isPriorityOn: Bool { settings.isPriorityEnabled }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Priority scanlator", isOn: priorityBinding)
                        .tint(AppTheme.controlFill)
                } footer: {
                    Text(isPriorityOn
                        ? "Chapters with the same number are merged, keeping the scanlator highest in this list. Drag to reorder."
                        : "Merge duplicate chapters by scanlator, and choose which scanlator wins. Hiding works either way.")
                }

                Section {
                    if rows.isEmpty {
                        Text("No scanlators in this chapter list yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(rows, id: \.self) { name in
                            row(name)
                        }
                        .onMove { source, destination in
                            var order = rows
                            order.move(fromOffsets: source, toOffset: destination)
                            settings.setPriority(order)
                        }
                    }
                } header: {
                    Text("Scanlators")
                } footer: {
                    Text(isPriorityOn
                        ? "Top of the list wins. Switch one off to hide it."
                        : "Switch one off to hide its chapters.")
                }
            }
            // Dragging only means something when priority merging is on, so edit
            // mode follows that toggle — visibility does not.
            .environment(\.editMode, .constant(isPriorityOn ? .active : .inactive))
            .navigationTitle("Scanlators")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func row(_ name: String) -> some View {
        HStack(spacing: 12) {
            if isPriorityOn {
                Image(systemName: "line.3.horizontal")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName(name))
                    .lineLimit(1)
                if settings.value.disabled.contains(name) {
                    Text("Hidden")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            Toggle("Show \(displayName(name))", isOn: visibleBinding(name))
                .labelsHidden()
                .tint(AppTheme.controlFill)
        }
    }

    /// Scanlator names arrive as the source spells them ("Official", "unofficial").
    private func displayName(_ name: String) -> String {
        name.prefix(1).uppercased() + name.dropFirst()
    }

    private var priorityBinding: Binding<Bool> {
        Binding(
            get: { settings.isPriorityEnabled },
            set: { settings.setPriorityEnabled($0) }
        )
    }

    private func visibleBinding(_ name: String) -> Binding<Bool> {
        Binding(
            get: { !settings.value.disabled.contains(name) },
            set: { settings.setVisible(name, $0) }
        )
    }
}
