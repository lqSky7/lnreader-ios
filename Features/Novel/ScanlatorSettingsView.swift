// ScanlatorSettingsView.swift - Priority and visibility for scanlators.
//
// One toggle turns the feature on. It reveals the scanlator list: drag to set
// priority (which scanlator wins when two chapters share a number), and switch a
// row off to hide that scanlator's chapters.

import SwiftUI

struct ScanlatorSettingsView: View {

    @Bindable var settings: ScanlatorSettings
    /// Scanlators present in this entry's chapter list.
    let scanlators: [String]

    @Environment(\.dismiss) private var dismiss

    private var rows: [String] {
        settings.orderedScanlators(from: scanlators)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Priority scanlator", isOn: enabledBinding)
                } footer: {
                    Text(settings.isEnabled
                        ? "Chapters with the same number are merged, keeping the scanlator highest in this list. Turn a scanlator off to hide its chapters."
                        : "Merge duplicate chapters by scanlator, and choose which scanlator wins.")
                }

                if settings.isEnabled {
                    Section("Scanlators") {
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
                    }
                }
            }
            .environment(\.editMode, settings.isEnabled ? .constant(.active) : .constant(.inactive))
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
            Image(systemName: "line.3.horizontal")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)

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
        }
    }

    /// Scanlator names arrive as the source spells them ("Official", "unofficial").
    private func displayName(_ name: String) -> String {
        name.prefix(1).uppercased() + name.dropFirst()
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { settings.isEnabled },
            set: { settings.setEnabled($0) }
        )
    }

    private func visibleBinding(_ name: String) -> Binding<Bool> {
        Binding(
            get: { !settings.value.disabled.contains(name) },
            set: { settings.setEnabled(name, $0) }
        )
    }
}
