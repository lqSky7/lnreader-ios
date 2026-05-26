// ContentView.swift
// Root view with Liquid Glass tab bar navigation.

import SwiftData
import SwiftUI

/// The root view containing the main tab navigation.
/// Tab bar automatically adopts Liquid Glass when compiled with Xcode 26.
struct ContentView: View {
    @Environment(PluginManager.self) private var pluginManager
    @State private var selectedTab: AppTab = .library

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab(AppTab.library.title, systemImage: AppTab.library.icon, value: .library) {
                LibraryView()
            }

            Tab(AppTab.updates.title, systemImage: AppTab.updates.icon, value: .updates) {
                UpdatesView()
            }

            Tab(AppTab.history.title, systemImage: AppTab.history.icon, value: .history) {
                HistoryView()
            }

            Tab(AppTab.browse.title, systemImage: AppTab.browse.icon, value: .browse) {
                BrowseView()
            }

            Tab(AppTab.more.title, systemImage: AppTab.more.icon, value: .more) {
                MoreView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .task {
            await pluginManager.restoreInstalledPlugins()
        }
    }
}

// MARK: - Tab Definition

/// All available tabs in the main navigation
enum AppTab: String, CaseIterable, Identifiable {
    case library
    case updates
    case history
    case browse
    case more

    var id: String { rawValue }

    var title: String {
        switch self {
        case .library: "Library"
        case .updates: "Updates"
        case .history: "History"
        case .browse: "Browse"
        case .more: "More"
        }
    }

    var icon: String {
        switch self {
        case .library: "books.vertical.fill"
        case .updates: "bell.badge"
        case .history: "clock.fill"
        case .browse: "safari.fill"
        case .more: "ellipsis.circle.fill"
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Novel.self, Chapter.self], inMemory: true)
}
