// GeneralSettingsView.swift
// Library defaults, update behavior, and confirmations.

import SwiftUI

struct GeneralSettingsView: View {
    @AppStorage("general.defaultSortOrder") private var defaultSortOrderRaw = SortOrder.lastRead.rawValue
    @AppStorage("general.defaultSortDirection") private var defaultSortDirectionRaw = SortDirection.descending.rawValue
    @AppStorage("general.defaultDisplayMode") private var defaultDisplayModeRaw = DisplayMode.comfortable.rawValue

    @AppStorage("general.autoUpdateOnLaunch") private var autoUpdateOnLaunch = true
    @AppStorage("general.updateOnWifiOnly") private var updateOnWifiOnly = true
    @AppStorage("general.confirmRemove") private var confirmRemove = true
    @AppStorage("general.showUnreadBadges") private var showUnreadBadges = true

    var body: some View {
        Form {
            Section("Defaults") {
                Picker("Sort Order", selection: defaultSortOrder) {
                    ForEach(SortOrder.allCases) { order in
                        Text(order.displayName).tag(order)
                    }
                }

                Picker("Sort Direction", selection: defaultSortDirection) {
                    ForEach(SortDirection.allCases, id: \.self) { direction in
                        Text(direction.rawValue).tag(direction)
                    }
                }

                Picker("Display Mode", selection: defaultDisplayMode) {
                    ForEach(DisplayMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
            }

            Section("Library") {
                Toggle("Show unread badges", isOn: $showUnreadBadges)
                Toggle("Confirm before remove", isOn: $confirmRemove)
            }

            Section("Updates") {
                Toggle("Auto update on launch", isOn: $autoUpdateOnLaunch)
                Toggle("Update on Wi-Fi only", isOn: $updateOnWifiOnly)
            }
        }
        .navigationTitle("General")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var defaultSortOrder: Binding<SortOrder> {
        Binding(
            get: { SortOrder(rawValue: defaultSortOrderRaw) ?? .lastRead },
            set: { defaultSortOrderRaw = $0.rawValue }
        )
    }

    private var defaultSortDirection: Binding<SortDirection> {
        Binding(
            get: { SortDirection(rawValue: defaultSortDirectionRaw) ?? .descending },
            set: { defaultSortDirectionRaw = $0.rawValue }
        )
    }

    private var defaultDisplayMode: Binding<DisplayMode> {
        Binding(
            get: { DisplayMode(rawValue: defaultDisplayModeRaw) ?? .comfortable },
            set: { defaultDisplayModeRaw = $0.rawValue }
        )
    }
}
