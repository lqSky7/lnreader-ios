// GeneralSettingsView.swift
// Library defaults and confirmations.

import SwiftUI

struct GeneralSettingsView: View {
    @AppStorage("general.defaultSortOrder") private var defaultSortOrderRaw = SortOrder.lastRead.rawValue
    @AppStorage("general.defaultSortDirection") private var defaultSortDirectionRaw = SortDirection.descending.rawValue
    @AppStorage("general.defaultDisplayMode") private var defaultDisplayModeRaw = DisplayMode.comfortable.rawValue

    @AppStorage("general.confirmRemove") private var confirmRemove = true
    @AppStorage("general.showUnreadBadges") private var showUnreadBadges = true
    @AppStorage("general.showDownloadBadges") private var showDownloadBadges = false
    @AppStorage("general.showLanguageBadges") private var showLanguageBadges = false
    @AppStorage("general.showNewBadges") private var showNewBadges = false

    var body: some View {
        Form {
            Section("Defaults") {
                Picker("Sort order", selection: defaultSortOrder) {
                    ForEach(SortOrder.allCases) { order in
                        Text(order.displayName).tag(order)
                    }
                }

                Picker("Sort direction", selection: defaultSortDirection) {
                    ForEach(SortDirection.allCases, id: \.self) { direction in
                        Text(direction.rawValue).tag(direction)
                    }
                }

                Picker("Display mode", selection: defaultDisplayMode) {
                    ForEach(DisplayMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
            }

            Section {
                Toggle("Unread count", isOn: $showUnreadBadges)
                Toggle("New chapters", isOn: $showNewBadges)
                Toggle("Downloaded count", isOn: $showDownloadBadges)
                Toggle("Source language", isOn: $showLanguageBadges)
            } header: {
                Text("Library badges")
            } footer: {
                Text("New counts unread chapters found by a refresh, until you clear Updates.")
            }

            Section("Library") {
                Toggle("Confirm before remove", isOn: $confirmRemove)
            }
        }
        .settingsScreen("General")
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
