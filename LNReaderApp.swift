// LNReaderApp.swift
// Main entry point for the LNReader iOS/macOS app.

import SwiftData
import SwiftUI

@main
struct LNReaderApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(TTSAudioAppDelegate.self) private var audioDelegate
    #endif
    @State private var pluginManager = PluginManager()
    @State private var libraryManager = LibraryManager()
    @State private var syncManager = SyncManager()
    @State private var sourceManager = SourceManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(AppTheme.accent)
                .environment(pluginManager)
                .environment(libraryManager)
                .environment(syncManager)
                .environment(sourceManager)
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
