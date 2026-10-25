// LNReaderApp.swift
// Main entry point for the LNReader iOS/macOS app.

import SwiftData
import SwiftUI

@main
struct LNReaderApp: App {
    init() {
        LibraryMaintenance.container = Self.modelContainer
        let tracking = TrackingManager()
        tracking.configure(container: Self.modelContainer)
        _trackingManager = State(initialValue: tracking)
    }
    @Environment(\.scenePhase) private var scenePhase
    #if os(iOS)
    @UIApplicationDelegateAdaptor(TTSAudioAppDelegate.self) private var audioDelegate
    #endif
    @State private var libraryManager = LibraryManager()
    @State private var syncManager = SyncManager()
    @State private var sourceManager = SourceManager()
    @State private var trackingManager: TrackingManager

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
                .toggleStyle(AppToggleStyle())
                .environment(libraryManager)
                .environment(syncManager)
                .environment(sourceManager)
                .environment(trackingManager)
                .task { libraryManager.tracking = trackingManager }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await trackingManager.flushPending() } }
                }
                .preferredColorScheme(.dark)
        }
        .modelContainer(Self.modelContainer)
        #if os(macOS)
        .defaultSize(width: 1000, height: 700)
        #endif
    }
}
