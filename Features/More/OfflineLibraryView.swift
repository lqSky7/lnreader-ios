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
                Toggle("Wi-Fi only", isOn: $wifiOnly).onChange(of: wifiOnly) { _, _ in downloads.resume() }
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
                Toggle("Check for new chapters", isOn: $enabled)
                Stepper("Requested interval: \(Int(hours)) hours", value: $hours, in: 1...72, step: 1)
                Toggle("Wi-Fi only", isOn: $wifiOnly)
                Toggle("Only titles with unread chapters", isOn: $unreadOnly)
                Toggle("Skip completed titles", isOn: $skipCompleted)
                Toggle("Download new chapters", isOn: $autoDownload)
                Toggle("Notify about new chapters", isOn: $notify)
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
                Button("Choose .lnbk backup") { importing = true }.disabled(busy)
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
        .confirmationDialog("Merge \(pending?.entries.count ?? 0) titles into your library?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
            Button("Restore backup") {
                guard let snapshot = pending else { return }
                pending = nil
                do { let count = try LibraryBackup.restore(snapshot, container: context.container); message = "Restored \(count) titles." }
                catch { message = "Restore failed: \(error.localizedDescription)" }
            }
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
            let key = importKey.isEmpty ? recoveryKey : importKey
            pending = try await Task.detached {
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= LibraryBackup.limit + 64 else { throw CocoaError(.fileReadTooLarge) }
                return try LibraryBackup.open(Data(contentsOf: url), recoveryKey: key)
            }.value
        } catch { message = "Could not open backup. Check the recovery key and file. \(error.localizedDescription)" }
    }
}
