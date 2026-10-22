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

    /// The v2 store.
    ///
    /// Opened once at launch. A failure here means the store on disk does not
    /// match `SchemaV1`, which is a programming error rather than a user error,
    /// so it fails loudly instead of silently starting with an empty library.
    private static let modelContainer: ModelContainer = {
        do {
            return try ModelContainerFactory.makeV2()
        } catch {
            fatalError("Could not open the LNReader-v2 store: \(error)")
        }
    }()

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
        .modelContainer(Self.modelContainer)
        #if os(macOS)
        .defaultSize(width: 1000, height: 700)
        #endif
    }
}
