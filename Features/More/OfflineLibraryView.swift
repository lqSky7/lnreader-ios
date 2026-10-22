import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

struct OfflineLibraryView: View {
    @Query(sort: \Entry.title) private var entries: [Entry]
    @Query(sort: \DownloadItem.order) private var queue: [DownloadItem]
    @State private var selected: PersistentIdentifier?
    @State private var downloads = ChapterDownloadManager.shared
    @AppStorage("downloads.wifiOnly") private var wifiOnly = true
    var body: some View {
        List {
            Section("Download chapters") {
                Picker("Title", selection: $selected) {
                    Text("Choose a library title").tag(nil as PersistentIdentifier?)
                    ForEach(entries.filter { $0.inLibrary && !$0.isLocal }) { entry in
                        Text(entry.displayTitle).tag(Optional(entry.persistentModelID))
                    }
                }
                if let entry = entries.first(where: { $0.persistentModelID == selected }) {
                    Button("Download unread chapters") { downloads.enqueue(entry.chapters.filter { !$0.read }) }
                    Button("Download all chapters") { downloads.enqueue(entry.chapters) }
                }
                Toggle("Wi-Fi only", isOn: $wifiOnly).tint(AppTheme.controlFill).onChange(of: wifiOnly) { _, _ in downloads.resume() }
                Text("Novels save chapter text. Manga saves every page. Add a title to your library before downloading.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Resume queue") { downloads.resume(); LibraryMaintenance.scheduleDownloads() }
                if let message = downloads.message { Text(message).font(.footnote) }
            }
            Section("Queue and offline chapters") {
                if queue.isEmpty { Text("No downloads yet").foregroundStyle(.secondary) }
                ForEach(queue) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.chapter?.entry?.displayTitle ?? "Removed title").font(.caption).foregroundStyle(.secondary)
                        Text(item.chapter?.name ?? "Removed chapter")
                        HStack {
                            Text(item.state.rawValue.capitalized).font(.caption)
                            Spacer()
                            if item.state == .queued || item.state == .downloading {
                                Button("Pause") { downloads.pause(item) }
                            } else if item.state != .completed {
                                Button("Retry") { downloads.retry(item) }
                            }
                        }
                        if item.state == .downloading { ProgressView(value: item.progress) }
                        if let error = item.error { Text(error).font(.caption).foregroundStyle(.secondary) }
                    }
                    .swipeActions { Button("Remove", role: .destructive) { downloads.remove(item) } }
                }
            }
        }
        .navigationTitle("Downloads")
    }
}

struct LibraryUpdateSettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Entry> { $0.inLibrary }) private var entries: [Entry]
    @AppStorage("updates.backgroundEnabled") private var enabled = false
    @AppStorage("updates.intervalHours") private var hours = 6.0
    @AppStorage("general.updateOnWifiOnly") private var wifiOnly = true
    @AppStorage("updates.notify") private var notify = false
    @AppStorage("updates.autoDownloadNew") private var autoDownload = false
    @AppStorage("updates.unreadOnly") private var unreadOnly = false
    @AppStorage("updates.skipCompleted") private var skipCompleted = false
    @AppStorage("updates.schedulingError") private var schedulingError = ""
    var body: some View {
        Form {
            Section("Background refresh") {
                Toggle("Check for new chapters", isOn: $enabled).tint(AppTheme.controlFill)
                Stepper("Requested interval: \(Int(hours)) hours", value: $hours, in: 1...72, step: 1)
                Toggle("Wi-Fi only", isOn: $wifiOnly).tint(AppTheme.controlFill)
                Toggle("Only titles with unread chapters", isOn: $unreadOnly).tint(AppTheme.controlFill)
                Toggle("Skip completed titles", isOn: $skipCompleted).tint(AppTheme.controlFill)
                Toggle("Download new chapters", isOn: $autoDownload).tint(AppTheme.controlFill)
                Toggle("Notify about new chapters", isOn: $notify).tint(AppTheme.controlFill)
                Text("iOS chooses when background work runs. Low Power Mode and Background App Refresh settings can delay it.")
                    .font(.footnote).foregroundStyle(.secondary)
                if !schedulingError.isEmpty { Text(schedulingError).font(.footnote).foregroundStyle(.secondary) }
            }
            Section("Per-title updates") {
                ForEach(entries.filter { !$0.isLocal }) { entry in
                    Picker(entry.displayTitle, selection: Binding(get: { entry.updateStrategy }, set: { entry.updateStrategy = $0; try? context.save() })) {
                        ForEach(UpdateStrategy.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                }
            }
        }
        .navigationTitle("Library updates")
        .onChange(of: enabled) { _, _ in LibraryMaintenance.schedule() }
        .onChange(of: hours) { _, _ in LibraryMaintenance.schedule() }
        .onChange(of: notify) { _, value in
            if value { Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) } }
        }
    }
}

extension UTType {
    static var lnreaderBackup: UTType { UTType(exportedAs: "com.lnreader.backup", conformingTo: .data) }
}
struct LibraryBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.lnreaderBackup] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
struct LibraryBackupView: View {
    @Environment(\.modelContext) private var context
    @State private var recoveryKey = ""
    @State private var importKey = ""
    @State private var document: LibraryBackupDocument?
    @State private var exporting = false
    @State private var importing = false
    @State private var busy = false
    @State private var message: String?
    @State private var pending: LibraryBackup.Snapshot?
    @State private var pendingMihon: MihonBackup.Backup?
    /// Which kind of file the file picker is currently choosing.
    @State private var importsMihon = false
    var body: some View {
        Form {
            Section("Encrypted backup") {
                Text("Includes your library, categories, chapter reading state, history, settings, and imported local books. Downloaded chapter media and audio can be downloaded again.")
                SecureField("Recovery key", text: $recoveryKey).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Copy recovery key") { UIPasteboard.general.string = recoveryKey }
                    .disabled(recoveryKey.isEmpty)
                Text("Keep this key separately from your backup. You need it to restore on another device.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Export .lnbk backup") { export() }.disabled(busy || recoveryKey.isEmpty)
            }
            Section("Restore and merge") {
                SecureField("Recovery key from the backup device", text: $importKey)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Text("Leave blank to use this device’s key. Existing title details and newer reading progress are kept.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Choose .lnbk backup") { importsMihon = false; importing = true }.disabled(busy)
            }
            Section("Import from another app") {
                Text("Restores the manga library, categories, read chapters, history and trackers from a .tachibk backup made by Mihon, Tachiyomi, Yokai or Tachimanga. Titles already here keep their details and the further reading progress.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Choose .tachibk backup") { importsMihon = true; importing = true }.disabled(busy)
            }
            if busy { ProgressView("Working…") }
            if let message { Section { Text(message) } }
        }
        .navigationTitle("Backup & restore")
        .task { do { recoveryKey = try LibraryBackup.key() } catch { message = error.localizedDescription } }
        .fileExporter(isPresented: $exporting, document: document, contentType: .lnreaderBackup,
                      defaultFilename: "lnreader_\(Date().formatted(.iso8601.year().month().day())).lnbk") { result in
            if case .failure(let error) = result { message = error.localizedDescription }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.lnreaderBackup, .data], allowsMultipleSelection: false) { result in
            Task { await read(result) }
        }
        .confirmationDialog(mihonPrompt, isPresented: Binding(get: { pendingMihon != nil }, set: { if !$0 { pendingMihon = nil } }), titleVisibility: .visible) {
            Button("Import backup") {
                guard let backup = pendingMihon else { return }
                pendingMihon = nil
                restoreMihon(backup)
            }
        } message: {
            Text(mihonDetail)
        }
        .confirmationDialog("Merge \(pending?.entries.count ?? 0) titles into your library?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
            Button("Restore backup") {
                guard let snapshot = pending else { return }
                pending = nil
                do { let count = try LibraryBackup.restore(snapshot, container: context.container); message = "Restored \(count) titles." }
                catch { message = "Restore failed: \(error.localizedDescription)" }
            }
        }
    }
    private var mihonPrompt: String { "Import \(pendingMihon?.manga.count ?? 0) titles?" }

    /// Which sources the file uses and whether they are installed.
    private var mihonDetail: String {
        guard let backup = pendingMihon else { return "" }
        let preview = MihonBackup.preview(backup)
        var lines = ["\(preview.matched) titles are from sources built into the app."]
        if !preview.unmatched.isEmpty {
            let names = preview.unmatched.sorted { $0.value > $1.value }
                .map { "\($0.key) (\($0.value))" }.joined(separator: ", ")
            lines.append("These sources are not installed, so their titles will be listed but cannot be opened until you add them: \(names).")
        }
        return lines.joined(separator: "\n\n")
    }

    private func restoreMihon(_ backup: MihonBackup.Backup) {
        busy = true
        let container = context.container
        Task {
            defer { busy = false }
            do {
                let summary = try await Task.detached(priority: .userInitiated) {
                    try MihonBackup.restore(backup, into: container)
                }.value
                LibraryChapterCounts.shared.invalidate()
                var text = "Imported \(summary.added) new titles with \(summary.chapters) chapters"
                if summary.merged > 0 { text += ", merged \(summary.merged) that were already here" }
                if summary.categories > 0 { text += ", added \(summary.categories) categories" }
                message = text + "."
                if !summary.unmatchedSources.isEmpty {
                    let total = summary.unmatchedSources.values.reduce(0, +)
                    message? += " \(total) titles come from sources that are not installed."
                }
            } catch { message = "Import failed: \(error.localizedDescription)" }
        }
    }

    private func export() {
        busy = true
        Task {
            defer { busy = false }
            do {
                let snapshot = try LibraryBackup.snapshot(context: context)
                let key = recoveryKey
                let data = try await Task.detached {
                    try LibraryBackup.seal(JSONEncoder().encode(snapshot), recoveryKey: key)
                }.value
                document = LibraryBackupDocument(data: data); exporting = true
            } catch { message = "Export failed: \(error.localizedDescription)" }
        }
    }
    private func read(_ result: Result<[URL], Error>) async {
        busy = true; defer { busy = false }
        do {
            guard let url = try result.get().first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if importsMihon {
                pendingMihon = try await Task.detached {
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= 256 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
                    return try MihonBackup.decode(Data(contentsOf: url))
                }.value
                return
            }
            let key = importKey.isEmpty ? recoveryKey : importKey
            pending = try await Task.detached {
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= LibraryBackup.limit + 64 else { throw CocoaError(.fileReadTooLarge) }
                return try LibraryBackup.open(Data(contentsOf: url), recoveryKey: key)
            }.value
        } catch {
            message = importsMihon
                ? "Could not read that backup. \(error.localizedDescription)"
                : "Could not open backup. Check the recovery key and file. \(error.localizedDescription)"
        }
    }
}
