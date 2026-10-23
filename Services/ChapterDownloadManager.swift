import CryptoKit
import Foundation
import SwiftData
import UIKit

@Observable @MainActor
final class ChapterDownloadManager {
    static let shared = ChapterDownloadManager()
    private var context: ModelContext?
    private var sources: SourceManager?
    private var worker: Task<Void, Never>?
    private var networkTask: Task<Void, Never>?
    private var active: PersistentIdentifier?
    private var backgroundID: UIBackgroundTaskIdentifier = .invalid
    var isRunning = false
    var message: String?

    func configure(context: ModelContext, sources: SourceManager) {
        guard self.context == nil else { resume(); return }
        self.context = context; self.sources = sources
        networkTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: Notification.Name("LNReaderNetworkChanged")) {
                self?.resume()
            }
        }
        do {
            for item in try context.fetch(FetchDescriptor<DownloadItem>()) {
                guard let chapter = item.chapter, let entry = chapter.entry else { context.delete(item); continue }
                if item.state == .downloading { item.state = .queued }
                if item.state == .completed,
                   OfflineChapters.manifest(sourceKey: entry.sourceKey, entryURL: entry.url, chapterURL: chapter.url) == nil {
                    item.state = .failed; item.error = "Offline files are missing. Retry this download."
                }
            }
            try context.save()
            resume()
        } catch { message = error.localizedDescription }
    }
    func enqueue(_ chapters: [Chapter], userInitiated: Bool = true) {
        guard let context else { return }
        do {
            var order = (try context.fetch(FetchDescriptor<DownloadItem>())).map(\.order).max() ?? 0
            for incoming in chapters.sorted(by: { $0.chapterNumber == $1.chapterNumber ? $0.sourceOrder < $1.sourceOrder : $0.chapterNumber < $1.chapterNumber }) {
                guard let chapter = context.model(for: incoming.persistentModelID) as? Chapter,
                      chapter.entry?.isLocal == false else { continue }
                if let item = chapter.downloadItem {
                    if item.state == .completed || item.state == .downloading { continue }
                    item.state = .queued; item.error = nil
                } else {
                    order += 1
                    let item = DownloadItem(chapter: chapter, order: order)
                    context.insert(item); chapter.downloadItem = item
                }
            }
            try context.save()
            let wasRunning = isRunning
            resume()
            if userInitiated && !wasRunning { LibraryMaintenance.continueDownloads() }
            else { LibraryMaintenance.scheduleDownloads() }
        } catch { message = error.localizedDescription }
    }
    func pause(_ item: DownloadItem) {
        item.state = .paused
        if active == item.persistentModelID {
            let stopping = worker
            stopping?.cancel()
            Task { [weak self] in await stopping?.value; self?.resume() }
        }
        persist()
    }
    func retry(_ item: DownloadItem) {
        item.state = .queued; item.error = nil; persist(); resume()
    }
    func remove(_ item: DownloadItem) {
        guard let context else { return }
        if active == item.persistentModelID {
            item.state = .paused; worker?.cancel()
            persist()
            let stopping = worker
            Task { [weak self] in
                await stopping?.value
                self?.remove(item)
                self?.resume()
            }
            return
        }
        do {
            if let chapter = item.chapter, let entry = chapter.entry {
                let folder = OfflineChapters.folder(sourceKey: entry.sourceKey, entryURL: entry.url, chapterURL: chapter.url)
                if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
                chapter.downloadItem = nil
            }
            context.delete(item); try context.save()
        } catch { message = error.localizedDescription }
    }
    func resume() {
        if let stopping = worker, stopping.isCancelled {
            Task { [weak self] in await stopping.value; self?.resume() }
            return
        }
        guard worker == nil, let context, let sources else { return }
        isRunning = true
        worker = Task {
            backgroundID = UIApplication.shared.beginBackgroundTask(withName: "Chapter downloads") {
                Task { @MainActor in ChapterDownloadManager.shared.worker?.cancel() }
            }
            defer {
                active = nil; isRunning = false; worker = nil
                if backgroundID != .invalid { UIApplication.shared.endBackgroundTask(backgroundID); backgroundID = .invalid }
            }
            do {
                while !Task.isCancelled {
                    guard NetworkMonitor.shared.isConnected() else { message = "Waiting for a network connection."; break }
                    if UserDefaults.standard.object(forKey: "downloads.wifiOnly") as? Bool ?? true,
                       !NetworkMonitor.shared.isOnWiFi() { message = "Waiting for Wi-Fi. Tap Resume when connected."; break }
                    message = nil
                    let items = try context.fetch(FetchDescriptor<DownloadItem>(sortBy: [SortDescriptor(\.order)]))
                    guard let item = items.first(where: { $0.state == .queued }), let chapter = item.chapter,
                          let entry = chapter.entry else { break }
                    active = item.persistentModelID; item.state = .downloading; item.error = nil
                    try context.save()
                    do {
                        try await download(chapter, entry: entry, item: item, sources: sources)
                        try Task.checkCancellation()
                        guard item.modelContext != nil else { continue }
                        item.state = .completed; item.progress = 1
                    } catch {
                        guard item.modelContext != nil else { continue }
                        if Task.isCancelled { if item.state == .downloading { item.state = .queued } }
                        else { item.state = .failed; item.error = error.localizedDescription }
                    }
                    try context.save(); active = nil
                }
            } catch { message = error.localizedDescription }
        }
    }
    func stop() async { worker?.cancel(); await worker?.value }
    private func persist() { do { try context?.save() } catch { message = error.localizedDescription } }
    private func download(_ chapter: Chapter, entry: Entry, item: DownloadItem, sources: SourceManager) async throws {
        var root = OfflineChapters.root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true; try root.setResourceValues(values)
        let folder = OfflineChapters.folder(sourceKey: entry.sourceKey, entryURL: entry.url, chapterURL: chapter.url)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Removing the old manifest prevents partial replacements being advertised as complete.
        try? FileManager.default.removeItem(at: folder.appendingPathComponent("manifest.json"))
        let sourceChapter = SourceChapter(url: chapter.url, name: chapter.name)
        var files: [String] = []
        if entry.kind == .novel {
            guard let source = sources.novelSource(forKey: entry.sourceKey) else { throw CocoaError(.fileNoSuchFile) }
            try checkSpace(at: root)
            let html = try await source.chapterHTML(sourceChapter)
            try Task.checkCancellation()
            guard !html.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
            try Data(html.utf8).write(to: folder.appendingPathComponent("chapter.html"), options: .atomic)
            files = ["chapter.html"]
        } else {
            guard let source = sources.mangaSource(forKey: entry.sourceKey) else { throw CocoaError(.fileNoSuchFile) }
            let pages = try await source.pages(sourceChapter)
            guard !pages.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
            let loader = PageLoader()
            for (index, page) in pages.enumerated() {
                try Task.checkCancellation(); try checkSpace(at: root)
                // Resolve lazy image URLs and preserve source-specific request headers.
                let request = try await source.imageRequest(page)
                guard let url = request.url else { throw CocoaError(.fileReadCorruptFile) }
                let imagePage = SourcePage(index: index, url: url.absoluteString, headers: request.allHTTPHeaderFields ?? [:])
                let data = try await loader.image(for: imagePage, sourceKey: entry.sourceKey)
                guard item.modelContext != nil else { throw CancellationError() }
                guard UIImage(data: data) != nil else { throw CocoaError(.fileReadCorruptFile) }
                let name = String(format: "%06d.page", index)
                try data.write(to: folder.appendingPathComponent(name), options: .atomic)
                files.append(name); item.progress = Double(index + 1) / Double(pages.count); persist()
            }
        }
        try Task.checkCancellation()
        let manifest = OfflineChapters.Manifest(sourceKey: entry.sourceKey, entryURL: entry.url, chapterURL: chapter.url, kind: entry.kind, files: files)
        try JSONEncoder().encode(manifest).write(to: folder.appendingPathComponent("manifest.json"), options: .atomic)
    }
    private func checkSpace(at url: URL) throws {
        let free = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage ?? 0
        guard free > 200 * 1024 * 1024 else { throw CocoaError(.fileWriteOutOfSpace) }
    }
}
