import BackgroundTasks
import Foundation
import SwiftData
import UserNotifications

@MainActor enum LibraryMaintenance {
    static let refreshID = "com.lnreader.library.refresh"
    static let downloadID = "com.lnreader.chapter.downloads"
    static let continuedID = "com.lnreader.chapter.continued.*"
    static var container: ModelContainer?
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshID, using: .main) { task in
            Task { @MainActor in handle(task, downloadsOnly: false) }
        }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: downloadID, using: .main) { task in
            Task { @MainActor in handle(task, downloadsOnly: true) }
        }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: continuedID, using: .main) { task in
            Task { @MainActor in handle(task, downloadsOnly: true) }
        }
    }
    static func continueDownloads() {
        let request = BGContinuedProcessingTaskRequest(identifier: "com.lnreader.chapter.continued.\(UUID().uuidString)",
                                                       title: "Downloading chapters", subtitle: "Saving your reading offline")
        request.strategy = .fail
        do { try BGTaskScheduler.shared.submit(request) }
        catch { scheduleDownloads() }
    }
    static func schedule() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: refreshID)
        guard UserDefaults.standard.bool(forKey: "updates.backgroundEnabled") else {
            UserDefaults.standard.removeObject(forKey: "updates.scheduleBase")
            return
        }
        let hours = max(1, UserDefaults.standard.object(forKey: "updates.intervalHours") as? Double ?? 6)
        let request = BGAppRefreshTaskRequest(identifier: refreshID)
        let base = UserDefaults.standard.object(forKey: "updates.lastBackgroundRun") as? Date
            ?? UserDefaults.standard.object(forKey: "updates.scheduleBase") as? Date ?? Date()
        UserDefaults.standard.set(base, forKey: "updates.scheduleBase")
        request.earliestBeginDate = max(Date(timeIntervalSinceNow: 900), base.addingTimeInterval(hours * 3600))
        do {
            try BGTaskScheduler.shared.submit(request)
            UserDefaults.standard.removeObject(forKey: "updates.schedulingError")
        }
        catch { UserDefaults.standard.set(error.localizedDescription, forKey: "updates.schedulingError") }
    }
    static func scheduleDownloads() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: downloadID)
        if let container {
            let items = (try? ModelContext(container).fetch(FetchDescriptor<DownloadItem>())) ?? []
            guard items.contains(where: { $0.state == .queued || $0.state == .downloading }) else {
                BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: downloadID)
                return
            }
        }
        let request = BGProcessingTaskRequest(identifier: downloadID)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        do { try BGTaskScheduler.shared.submit(request) }
        catch { UserDefaults.standard.set(error.localizedDescription, forKey: "downloads.schedulingError") }
    }
    private static func handle(_ task: BGTask, downloadsOnly: Bool) {
        let work = Task { @MainActor in
            defer {
                task.expirationHandler = nil
                if !downloadsOnly { schedule() }
            }
            guard let container else { task.setTaskCompleted(success: false); return }
            if !downloadsOnly, !UserDefaults.standard.bool(forKey: "updates.backgroundEnabled") {
                task.setTaskCompleted(success: true); return
            }
            await HTTPClient.shared.setCloudflareSolver(WebKitCloudflareSolver())
            let sources = SourceManager()
            sources.registerNativeSources()
            let context = ModelContext(container)
            let started = Date()
            if !downloadsOnly {
                let manager = LibraryManager()
                // `updateLibrary` runs in its own task, so an expiring background
                // task has to ask it to stop rather than rely on cancellation.
                await withTaskCancellationHandler {
                    await manager.updateLibrary(context: context, sourceManager: sources, automatic: true)
                } onCancel: {
                    Task { @MainActor in manager.cancelUpdate() }
                }
                guard !Task.isCancelled else { task.setTaskCompleted(success: false); return }
                let chapters = (try? context.fetch(FetchDescriptor<Chapter>())) ?? []
                let added = chapters.filter { ($0.dateFetch ?? .distantPast) >= started && $0.entry?.inLibrary == true }
                if UserDefaults.standard.bool(forKey: "updates.notify"), !added.isEmpty {
                    let content = UNMutableNotificationContent()
                    content.title = "New chapters"
                    content.body = "\(added.count) new chapters are ready in Updates."
                    try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
                }
                if UserDefaults.standard.bool(forKey: "updates.autoDownloadNew") {
                    ChapterDownloadManager.shared.configure(context: context, sources: sources)
                    ChapterDownloadManager.shared.enqueue(added, userInitiated: false)
                }
                UserDefaults.standard.set(Date(), forKey: "updates.lastBackgroundRun")
            }
            guard !Task.isCancelled else { task.setTaskCompleted(success: false); return }
            ChapterDownloadManager.shared.configure(context: context, sources: sources)
            ChapterDownloadManager.shared.resume()
            // Keep the BGProcessing assertion while the durable queue runs.
            while ChapterDownloadManager.shared.isRunning && !Task.isCancelled {
                if let continued = task as? BGContinuedProcessingTask {
                    let items = (try? context.fetch(FetchDescriptor<DownloadItem>())) ?? []
                    continued.progress.totalUnitCount = Int64(max(items.count, 1) * 1000)
                    continued.progress.completedUnitCount = Int64(items.reduce(0.0) { $0 + ($1.state == .completed ? 1 : $1.progress) } * 1000)
                }
                try? await Task.sleep(for: .seconds(1))
            }
            if Task.isCancelled { await ChapterDownloadManager.shared.stop() }
            task.setTaskCompleted(success: !Task.isCancelled)
        }
        task.expirationHandler = { work.cancel() }
    }
}
