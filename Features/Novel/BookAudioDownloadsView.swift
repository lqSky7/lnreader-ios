import AVFoundation
import SwiftUI

@MainActor
final class TTSVoicePreviewPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = TTSVoicePreviewPlayer()
    @Published private(set) var voiceId: String?
    private var player: AVAudioPlayer?
    func play(_ record: TTSDownloadRecord) {
        if voiceId == record.rendition.voiceId { stop(); return }
        do {
            if ReaderTTSManager.shared.isSpeaking && !ReaderTTSManager.shared.isPaused { ReaderTTSManager.shared.pause() }
            #if os(iOS)
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
            #endif
            player = try AVAudioPlayer(contentsOf: TTSStorage.audio(record.id)); player?.delegate = self
            guard player?.play() == true else { return }
            voiceId = record.rendition.voiceId
        } catch { TTSOfflineLibrary.shared.errorMessage = error.localizedDescription }
    }
    func stop() { player?.stop(); player = nil; voiceId = nil }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { Task { @MainActor [weak self] in self?.stop() } }
}

struct QwenVoicePicker: View {
    @ObservedObject private var library = TTSOfflineLibrary.shared
    @ObservedObject private var preview = TTSVoicePreviewPlayer.shared
    @Binding var selected: Set<String>
    var body: some View {
        ForEach(library.voices) { voice in
            HStack(spacing: 12) {
                Button {
                    if selected.contains(voice.id) { selected.remove(voice.id) } else { selected.insert(voice.id) }
                } label: {
                    HStack {
                        Image(systemName: selected.contains(voice.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(AppTheme.accent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(voice.name).foregroundStyle(.primary)
                            Text(voice.description).font(.caption).foregroundStyle(.secondary)
                            Text("Native voice: \(voice.nativeLanguage) · English narration").font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }.frame(minHeight: 48)
                }.buttonStyle(.plain)
                if let sample = library.records.first(where: { $0.isPreview && $0.isAvailable && $0.rendition.voiceId == voice.id }) {
                    Button { preview.play(sample) } label: { Image(systemName: preview.voiceId == voice.id ? "stop.fill" : "play.fill").frame(width: 44, height: 44) }
                        .accessibilityLabel("\(preview.voiceId == voice.id ? "Stop" : "Play") downloaded \(voice.name) preview")
                } else {
                    Image(systemName: "arrow.down.circle").foregroundStyle(.tertiary).frame(width: 44, height: 44).accessibilityLabel("Preview is being prepared")
                }
            }
        }
    }
}

struct BookAudioDownloadsView: View {
    @Environment(PluginManager.self) private var pluginManager
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var library = TTSOfflineLibrary.shared
    let bookId: String
    let bookTitle: String
    let pluginId: String
    let novelPath: String
    let chapters: [TTSChapterChoice]
    var coverURL: String? = nil
    var initialChapter: String? = nil
    @State private var selectedVoices: Set<String> = []
    @State private var fromChapter = 1
    @State private var throughChapter = 1
    @State private var preparing = false
    @State private var preparationProgress = ""
    @State private var preparationTask: Task<Void, Never>?
    @State private var error: String?
    @State private var search = ""
    @State private var stateFilter = "All"
    @State private var expandedChapter: String?
    @State private var showVoices = false
    @State private var showRange = false
    @State private var initialized = false
    @State private var deleteTarget: TTSDownloadRecord?
    @State private var deleteIDs: [String] = []
    @State private var voiceFilter = "all"
    @AppStorage("tts.wifiOnly") private var wifiOnly = true

    private var selectedChapters: [TTSChapterChoice] {
        guard !chapters.isEmpty else { return [] }
        let start = min(max(fromChapter - 1, 0), chapters.count - 1)
        let end = min(max(throughChapter - 1, start), chapters.count - 1)
        return Array(chapters[start...end])
    }
    private var currentChoice: TTSChapterChoice? { chapters.first { $0.path == initialChapter } ?? chapters.first }
    private var selectionLabel: String {
        guard let first = selectedChapters.first, let last = selectedChapters.last else { return "No chapters" }
        return first.path == last.path ? "Chapter \(first.position + 1) selected" : "\(first.position + 1)–\(last.position + 1) selected"
    }
    private var bookRecords: [TTSDownloadRecord] { library.downloads(bookId: bookId) }
    private var byteCount: Int64 { bookRecords.filter(\.isAvailable).reduce(0) { $0 + $1.bytesExpected } }
    private var groups: [String: [TTSDownloadRecord]] {
        Dictionary(grouping: bookRecords.filter { voiceFilter == "all" || $0.rendition.voiceId == voiceFilter }, by: { $0.rendition.chapterId })
    }
    private func matches(_ chapter: TTSChapterChoice, records: [TTSDownloadRecord]) -> Bool {
        let searchable = "\(chapter.position + 1) \(chapter.title)"
        guard search.isEmpty || searchable.localizedCaseInsensitiveContains(search) else { return false }
        switch stateFilter {
        case "Downloaded": return records.contains { $0.isAvailable }
        case "Preparing": return records.contains { ["waiting", "downloading"].contains($0.state) }
        case "Issues": return records.contains { $0.error != nil || ["failed", "paused"].contains($0.state) }
        default: return true
        }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    dashboard.listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear).listRowSeparator(.hidden)
                }
                if preparing || error != nil || library.errorMessage != nil || (library.engineState != nil && bookRecords.contains(where: { $0.state == "waiting" })) {
                    Section("Audio preparation") {
                        if let engine = library.engineState, bookRecords.contains(where: { $0.state == "waiting" }) {
                            Label {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(engine.status == "queued" ? "Waiting for Kaggle" : engine.needsAttention ? "Preparation needs attention" : "Preparing audio").font(.subheadline.bold())
                                    Text(["starting", "generating"].contains(engine.status) ? "Your audio is being prepared. Chapter progress updates as each part is ready." : engine.message).font(.caption).foregroundStyle(.secondary)
                                    if let retry = engine.retryAt, let date = ISO8601DateFormatter().date(from: retry) {
                                        Text("Next check: \(date.formatted(date: .omitted, time: .shortened))").font(.caption)
                                    }
                                }
                            } icon: { Image(systemName: engine.needsAttention ? "exclamationmark.triangle.fill" : "clock.arrow.circlepath").foregroundStyle(engine.needsAttention ? Color.orange : AppTheme.accent) }
                        }
                        if let message = error ?? library.errorMessage {
                            Label(message, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.red)
                        }
                        if preparing {
                            HStack { ProgressView(); Text(preparationProgress).font(.subheadline); Spacer(); Button("Stop") { preparationTask?.cancel() } }
                        }
                    }
                }
                Section {
                    let indexed = groups
                    let visible = chapters.filter { matches($0, records: indexed[$0.path] ?? []) }
                    ForEach(visible) { chapter in
                        chapterRow(chapter, records: indexed[chapter.path] ?? [])
                    }
                    if visible.isEmpty { ContentUnavailableView("No chapters", systemImage: "headphones", description: Text("Try another search or filter.")) }
                } header: {
                    HStack {
                        Text("Chapters · \(chapters.count)")
                        Spacer()
                        Menu {
                            Picker("Status", selection: $stateFilter) {
                                ForEach(["All", "Downloaded", "Preparing", "Issues"], id: \.self) { Text($0).tag($0) }
                            }
                            Picker("Voice", selection: $voiceFilter) {
                                Text("All voices").tag("all")
                                ForEach(library.voices) { Text($0.name).tag($0.id) }
                            }
                        } label: { Label(stateFilter, systemImage: "line.3.horizontal.decrease") }
                    }
                }
            }
            .searchable(text: $search, prompt: "Chapter number or title")
            .navigationTitle("Offline audio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Toggle("Wi-Fi downloads only", isOn: $wifiOnly)
                        Picker("Preferred voice", selection: Binding(get: { library.selectedVoice(bookId: bookId, chapterId: "__book_default__") }, set: { library.setBookVoice($0, bookId: bookId) })) {
                            ForEach(library.voices) { Text($0.name).tag($0.id) }
                        }
                        Button("Delete selected range…", role: .destructive) {
                            let paths = Set(selectedChapters.map(\.path))
                            deleteIDs = bookRecords.filter { paths.contains($0.rendition.chapterId) && (voiceFilter == "all" || $0.rendition.voiceId == voiceFilter) }.map(\.id)
                        }.disabled(bookRecords.isEmpty)
                    } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Audio download options")
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: prepareSelected) {
                    Label("Download \(selectedChapters.count == 1 ? "this chapter" : "\(selectedChapters.count) chapters") · \(selectedVoices.count) \(selectedVoices.count == 1 ? "voice" : "voices")", systemImage: "arrow.down.circle.fill")
                        .font(.subheadline.bold()).frame(maxWidth: .infinity).padding(.vertical, 9)
                }.buttonStyle(.borderedProminent).disabled(preparing || selectedVoices.isEmpty || selectedChapters.isEmpty)
                    .padding(.horizontal).padding(.vertical, 8).background(.bar)
            }
            .sheet(isPresented: $showVoices) {
                NavigationStack {
                    List { QwenVoicePicker(selected: $selectedVoices) }
                        .navigationTitle("Choose voices").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showVoices = false } } }
                }
            }
            .sheet(isPresented: $showRange) { rangePicker }
            .task {
                if !initialized {
                    let index = chapters.firstIndex { $0.path == initialChapter } ?? 0
                    fromChapter = index + 1; throughChapter = fromChapter
                    selectedVoices = [library.selectedVoice(bookId: bookId, chapterId: initialChapter ?? chapters.first?.path ?? "")]
                    initialized = true
                }
                await library.refreshVoices(); await library.refresh()
            }
            .refreshable { await library.refreshVoices(); await library.refresh() }
            .confirmationDialog("Delete this voice from this phone?", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })) {
                if let record = deleteTarget { Button("Delete \(voiceName(record))", role: .destructive) { Task { await library.delete(record.id) }; deleteTarget = nil } }
            } message: { Text("Other voices and chapter text remain available.") }
            .confirmationDialog("Delete \(deleteIDs.count) voice downloads from this phone?", isPresented: Binding(get: { !deleteIDs.isEmpty }, set: { if !$0 { deleteIDs = [] } })) {
                Button("Delete selected downloads", role: .destructive) {
                    let ids = deleteIDs; deleteIDs = []
                    Task { for id in ids { await library.delete(id) } }
                }
            } message: { Text("Chapter text stays on this phone. You can prepare the voices again later.") }
        }.tint(AppTheme.accent)
    }
    private var dashboard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                NovelCoverView(url: coverURL, cornerRadius: 6).frame(width: 48, height: 68)
                VStack(alignment: .leading, spacing: 4) {
                    Text(bookTitle).font(.headline).lineLimit(2)
                    Text("\(Set(bookRecords.filter(\.isAvailable).map { $0.rendition.chapterId }).count) chapters offline · \(ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    AudioQuickActionCard(title: "This chapter", subtitle: "Chapter \((currentChoice?.position ?? 0) + 1)", symbol: selectedChapters.count == 1 && selectedChapters.first?.path == currentChoice?.path ? "checkmark.circle.fill" : "book.closed") {
                        fromChapter = (chapters.firstIndex { $0.path == initialChapter } ?? 0) + 1
                        throughChapter = fromChapter
                    }
                    if chapters.count > 1 {
                        AudioQuickActionCard(title: "Next 10", subtitle: "From chapter \((selectedChapters.first?.position ?? 0) + 1)", symbol: "forward.end.fill") { throughChapter = min(chapters.count, fromChapter + 9) }
                        AudioQuickActionCard(title: "Chapter range", subtitle: selectionLabel, symbol: "list.number") { showRange = true }
                    }
                    AudioQuickActionCard(title: "Voices", subtitle: "\(selectedVoices.count) selected · samples", symbol: "waveform") { showVoices = true }
                    AudioQuickActionCard(title: "On this iPhone", subtitle: "Manage saved audio", symbol: "iphone.gen3") { stateFilter = "Downloaded" }
                }.padding(.horizontal, 16)
            }
        }
    }
    private var rangePicker: some View {
        NavigationStack {
            Form {
                Section("Chapter numbers · 1–\(chapters.count)") {
                    HStack { Text("From"); Spacer(); TextField("From", value: $fromChapter, format: .number).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 100) }
                    HStack { Text("Through"); Spacer(); TextField("Through", value: $throughChapter, format: .number).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 100) }
                    Button("All remaining chapters") { throughChapter = chapters.count }
                }
                Text("Select voices separately. You can keep and manage several voices for each chapter.").font(.caption).foregroundStyle(.secondary)
            }.navigationTitle("Choose chapters").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") {
                    fromChapter = min(max(1, fromChapter), max(1, chapters.count))
                    throughChapter = min(max(fromChapter, throughChapter), chapters.count)
                    showRange = false
                } } }
        }.presentationDetents([.medium])
    }
    private func chapterSummary(_ records: [TTSDownloadRecord]) -> String {
        if records.isEmpty { return "No audio downloaded" }
        let ready = records.filter(\.isAvailable).count
        let pending = records.filter { ["waiting", "downloading"].contains($0.state) }.count
        let issues = records.filter { $0.error != nil || ["failed", "paused"].contains($0.state) }.count
        return [ready > 0 ? "\(ready) voices offline" : nil, pending > 0 ? "\(pending) preparing" : nil, issues > 0 ? "\(issues) need attention" : nil].compactMap { $0 }.joined(separator: " · ")
    }
    private func chapterRow(_ chapter: TTSChapterChoice, records: [TTSDownloadRecord]) -> some View {
        let hasIssue = records.contains { $0.error != nil || ["failed", "paused"].contains($0.state) }
        return DisclosureGroup(isExpanded: Binding(get: { expandedChapter == chapter.path }, set: { expandedChapter = $0 ? chapter.path : nil })) {
            Group {
                Button { fromChapter = (chapters.firstIndex { $0.path == chapter.path } ?? 0) + 1; throughChapter = fromChapter; prepareSelected() } label: {
                    Label(records.isEmpty ? "Download selected voices" : "Add selected voices", systemImage: "arrow.down.circle")
                }.disabled(preparing || selectedVoices.isEmpty)
            }
            ForEach(records) { audioRow($0) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: hasIssue ? "exclamationmark.circle" : records.contains(where: \.isAvailable) ? "checkmark.circle.fill" : records.isEmpty ? "headphones" : "clock")
                    .font(.title3).foregroundStyle(hasIssue ? Color.orange : records.contains(where: \.isAvailable) ? AppTheme.accent : .secondary).frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(chapter.title).font(.subheadline).foregroundStyle(.primary).lineLimit(2)
                    Text(chapterSummary(records))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.padding(.vertical, 5)
        }
    }
    @ViewBuilder private func audioRow(_ record: TTSDownloadRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(voiceName(record)).font(.headline)
                    Text(status(record)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if record.isAvailable {
                    Button {
                        library.selectVoice(record.rendition.voiceId, bookId: bookId, chapterId: record.rendition.chapterId)
                        ReaderTTSManager.shared.play(renditionID: record.id)
                    } label: { Image(systemName: "play.fill").frame(width: 44, height: 44) }.accessibilityLabel("Play \(voiceName(record))")
                    Button { library.selectVoice(record.rendition.voiceId, bookId: bookId, chapterId: record.rendition.chapterId) } label: {
                        Image(systemName: library.selectedVoice(bookId: bookId, chapterId: record.rendition.chapterId) == record.rendition.voiceId ? "checkmark.circle.fill" : "circle").frame(width: 44, height: 44)
                    }.accessibilityLabel("Select \(voiceName(record)) for this chapter")
                } else if record.state == "failed" || record.state == "paused" {
                    Button("Retry") { Task { await library.retry(record.id) } }
                } else { Button { library.pause(record.id) } label: { Image(systemName: "pause.fill").frame(width: 44, height: 44) } }
                Button(role: .destructive) { deleteTarget = record } label: { Image(systemName: "trash").frame(width: 44, height: 44) }.accessibilityLabel("Delete \(voiceName(record)) from phone")
            }.buttonStyle(.borderless)
            if record.state == "waiting" || record.state == "downloading" { ProgressView(value: min(max(record.progress, 0), 1)) }
            if let message = record.error { Text(message).font(.caption2).foregroundStyle(.secondary) }
        }
    }
    private func voiceName(_ record: TTSDownloadRecord) -> String { library.voices.first { $0.id == record.rendition.voiceId }?.name ?? record.rendition.voiceId }
    private func status(_ record: TTSDownloadRecord) -> String {
        switch record.state {
        case "downloaded": return "Available offline · " + ByteCountFormatter.string(fromByteCount: record.bytesExpected, countStyle: .file)
        case "waiting": return record.rendition.status == "ready" ? "Ready on server · waiting for transfer" : "\(record.rendition.status.capitalized) · \(record.rendition.completedChunks)/\(record.rendition.totalChunks) parts"
        case "downloading": return "Downloading to this phone"
        default: return record.state.capitalized
        }
    }
    private func prepareSelected() {
        guard !preparing else { return }
        let choices = selectedChapters
        let preferred = library.selectedVoice(bookId: bookId, chapterId: initialChapter ?? choices.first?.path ?? "")
        let voices = selectedVoices.sorted { a, b in a == preferred ? true : b == preferred ? false : a < b }
        preparing = true; error = nil
        preparationTask = Task { @MainActor in
            defer { preparing = false }
            do {
                for (index, chapter) in choices.enumerated() {
                    try Task.checkCancellation()
                    preparationProgress = "Adding \(index + 1) of \(choices.count)…"
                    if let cached = library.localText(bookId: bookId, chapterId: chapter.path) {
                        try await library.prepare(chapter: .init(bookId: bookId, bookTitle: bookTitle, chapterId: chapter.path, title: chapter.title, position: chapter.position, blocks: cached.blocks), voiceIds: voices)
                        continue
                    }
                    let html: String
                    if pluginId == "local" {
                        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("LocalNovels").appendingPathComponent(novelPath.replacingOccurrences(of: "local://", with: ""))
                        let file = folder.appendingPathComponent(chapter.path).standardizedFileURL
                        guard file.path.hasPrefix(folder.standardizedFileURL.path + "/") else { throw TTSError.request("Invalid local chapter path") }
                        html = try String(contentsOf: file, encoding: .utf8)
                    } else {
                        guard let source = pluginManager.plugin(for: pluginId) else { throw TTSError.request("Source plugin is unavailable") }
                        html = try await source.parseChapter(path: chapter.path)
                    }
                    let blocks = try await TTSChapterTextExtractor().extract(html)
                    try await library.prepare(chapter: .init(bookId: bookId, bookTitle: bookTitle, chapterId: chapter.path, title: chapter.title, position: chapter.position, blocks: blocks), voiceIds: voices)
                }
            } catch is CancellationError { }
            catch { self.error = "\(preparationProgress) \(error.localizedDescription) Chapters already added remain queued." }
        }
    }
}



struct AudioQuickActionCard: View {
    let title: String
    let subtitle: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: symbol)
                    .font(.body)
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 32, height: 32)
                    .background(AppTheme.accent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Spacer(minLength: 4)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            .padding(12)
            .frame(width: 154, alignment: .leading)
            .frame(minHeight: 112, alignment: .topLeading)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
