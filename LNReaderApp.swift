// LNReaderApp.swift
// Main entry point for the LNReader iOS/macOS app.

import SwiftData
import SwiftUI

@main
struct LNReaderApp: App {
    @State private var pluginManager = PluginManager()
    @State private var libraryManager = LibraryManager()
    @State private var syncManager = SyncManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(pluginManager)
                .environment(libraryManager)
                .environment(syncManager)
                .preferredColorScheme(.dark)
        }
        .modelContainer(for: [
            Novel.self,
            Chapter.self,
            Category.self,
            Repository.self,
            ReadingHistory.self,
            UserProfile.self,
        ])
        #if os(macOS)
        .defaultSize(width: 1000, height: 700)
        #endif
    }
}
