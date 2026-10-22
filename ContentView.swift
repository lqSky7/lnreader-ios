// ContentView.swift
// Root view with Liquid Glass tab bar navigation.

import SwiftData
import SwiftUI

/// The root view containing the main tab navigation.
/// Tab bar automatically adopts Liquid Glass when compiled with Xcode 26.
struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(PluginManager.self) private var pluginManager
    @Environment(LibraryManager.self) private var libraryManager
    @Environment(SyncManager.self) private var syncManager
    @Environment(SourceManager.self) private var sourceManager
    @Environment(\.modelContext) private var modelContext
    @AppStorage("general.autoUpdateOnLaunch") private var autoUpdateOnLaunch = true
    @State private var selectedTab: AppTab = .library
    @State private var readerRouter = ReaderRouter()

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
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                libraryManager.flushProgress(context: modelContext)
                LibraryMaintenance.schedule()
                LibraryMaintenance.scheduleDownloads()
            } else if phase == .active {
                ChapterDownloadManager.shared.resume()
            }
        }
        .environment(readerRouter)
        // The reader is its own window: anything that opens a chapter goes
        // through the router, and this is the single place it is presented.
        .fullScreenCover(
            item: Binding(
                get: { readerRouter.request },
                set: { readerRouter.request = $0 }
            )
        ) { request in
            ChapterReader(
                sourceKey: request.sourceKey,
                entryURL: request.entryURL,
                kind: request.kind,
                chapterURL: request.chapterURL,
                chapterName: request.chapterName
            )
            .environment(readerRouter)
        }
        .task {
            await syncManager.loadSession()
            // v2 source registry mirrors the installed LN plugins, and refreshes
            // whenever one is installed or removed.
            pluginManager.onInstalledSourcesChanged = { sourceManager.sync(with: pluginManager) }
            await pluginManager.restoreInstalledPlugins()
            sourceManager.sync(with: pluginManager)
            // Extensions: ship MangaFire with the binary, then load whatever is
            // installed (bundled or from a repository).
            BundledExtensions.installMissing()
            sourceManager.registerInstalledExtensions()
            ChapterDownloadManager.shared.configure(context: modelContext, sources: sourceManager)
            LibraryMaintenance.schedule()
            // The HTTP stack gets its Cloudflare solver before any source is browsed.
            await HTTPClient.shared.setCloudflareSolver(WebKitCloudflareSolver())
            if autoUpdateOnLaunch {
                // A library update is two requests per book plus a merge pass on
                // the main actor. Starting it inside the launch task means the
                // first scroll of the session competes with it. Give the first
                // frame and the first tap a clear run.
                try? await Task.sleep(for: .seconds(2))
                await libraryManager.updateLibrary(context: modelContext, sourceManager: sourceManager, automatic: true)
            }
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
        .modelContainer(for: [Entry.self, Chapter.self, History.self], inMemory: true)
}
