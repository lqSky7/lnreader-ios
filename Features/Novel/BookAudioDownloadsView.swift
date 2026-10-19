import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

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
    @State private var showCreateVoice = false
    @State private var deletingVoice: TTSVoice?
    var body: some View {
        ForEach(library.voices) { voice in
            HStack(spacing: 12) {
                Button {
                    if selected.contains(voice.id) { selected.remove(voice.id) } else { selected.insert(voice.id) }
                } label: {
                    HStack {
                        Image(systemName: selected.contains(voice.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(AppTheme.accent)
                        VStack(alignment: .leading, spacing: 3) {
                            TTSVoiceChip(voiceId: voice.id, name: voice.name)
                            Text(voice.description).font(.caption).foregroundStyle(.secondary)
                            Text(voice.isCustom ? "Your voice · English narration" : "Native voice: \(voice.nativeLanguage) · English narration").font(.caption2).foregroundStyle(.secondary)
                            if voice.isCustom, let error = voice.preview?.error { Text(error).font(.caption2).foregroundStyle(.orange) }
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
            .contextMenu {
                if voice.isCustom {
                    Button("Delete voice", systemImage: "trash", role: .destructive) { deletingVoice = voice }
                }
            }
        }
        Button { showCreateVoice = true } label: { Label("Add your own voice", systemImage: "waveform.badge.plus") }
            .sheet(isPresented: $showCreateVoice) {
                CustomVoiceCreationView { voice in selected = [voice.id] }
            }
            .confirmationDialog("Delete \(deletingVoice?.name ?? "voice")?", isPresented: Binding(get: { deletingVoice != nil }, set: { if !$0 { deletingVoice = nil } }), titleVisibility: .visible) {
                Button("Delete voice", role: .destructive) {
                    guard let voice = deletingVoice else { return }
                    Task {
                        do { try await library.deleteCustomVoice(voice); selected.remove(voice.id) }
                        catch { library.errorMessage = error.localizedDescription }
                    }
                    deletingVoice = nil
                }
            } message: { Text("This removes the reference and cancels unfinished preparations in this voice. Downloaded book chapters stay on your phone.") }
        NavigationLink {
            VoiceReferencePassageView()
        } label: {
            Label("Voice recording passage", systemImage: "text.quote")
        }
    }
}

struct QwenComputePicker: View {
    @AppStorage("tts.provider") private var provider = "kaggle"
    @State private var providers: [TTSComputeProvider] = []
    @State private var error: String?
    var body: some View {
        Picker("Prepare audio with", selection: $provider) {
            Text("Kaggle").tag("kaggle")
            Text(providers.first(where: { $0.id == "colab" })?.available == true ? "Google Colab" : "Google Colab · not connected").tag("colab")
        }
        .task {
            while !Task.isCancelled {
                do { providers = try await TTSAPIClient().providers(); error = nil }
                catch { self.error = error.localizedDescription }
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
            }
        }
        .onChange(of: provider) { _, _ in Task { await TTSOfflineLibrary.shared.refresh() } }
        if provider == "colab", providers.first(where: { $0.id == "colab" })?.available != true {
            Text(error ?? "Connect Colab on the server before preparing new audio. Downloaded chapters play with either selection.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct VoiceReferencePassageView: View {
    // Public-domain opening paragraph of Grant Fairbanks' Rainbow Passage.
    // Source: https://www.dialectsarchive.com/the-rainbow-passage
    static let passage = """
    When the sunlight strikes raindrops in the air, they act as a prism and form a rainbow. The rainbow is a division of white light into many beautiful colors. These take the shape of a long round arch, with its path high above, and its two ends apparently beyond the horizon. There is, according to legend, a boiling pot of gold at one end. People look, but no one ever finds it. When a man looks for something beyond his reach, his friends say he is looking for the pot of gold at the end of the rainbow.
    """

    @State private var copied = false

    var body: some View {
        List {
            Section {
                Text("Read at your usual pace, with natural pauses and a mostly neutral tone. Use gentle expression without acting out emotions.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Text(Self.passage)
                    .lineSpacing(6)
                    .textSelection(.enabled)
                    .padding(.vertical, 8)
                Button {
                    UIPasteboard.general.string = Self.passage
                    copied = true
                } label: {
                    Label(copied ? "Passage copied" : "Copy passage", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .accessibilityHint("Copies only the passage text")
            } header: {
                Text("The Rainbow Passage")
            } footer: {
                Text("A public-domain passage for sampling English speech sounds, by Grant Fairbanks.")
            }
            Section {
                Link("Read the original at IDEA", destination: URL(string: "https://www.dialectsarchive.com/the-rainbow-passage")!)
            }
        }
        .navigationTitle("Recording passage")
        .navigationBarTitleDisplayMode(.inline)
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
    @State private var chapterPage = 0
    @AppStorage("tts.provider") private var computeProvider = "kaggle"
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
                if preparing || error != nil || library.errorMessage != nil || library.engineState?.needsAttention == true {
                    Section {
                        if preparing {
                            HStack { ProgressView(); Text(preparationProgress).font(.caption); Spacer(); Button("Stop") { preparationTask?.cancel() } }
                        }
                        if let message = error ?? library.errorMessage ?? (library.engineState?.needsAttention == true ? library.engineState?.message : nil) {
                            Label(message, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange)
                        }
                    }
                }
                Section {
                    let indexed = groups
                    let visible = chapters.filter { matches($0, records: indexed[$0.path] ?? []) }
                    let pageCount = max(1, (visible.count + 99) / 100)
                    let page = min(chapterPage, pageCount - 1)
                    ForEach(Array(visible.dropFirst(page * 100).prefix(100))) { chapter in
                        chapterRow(chapter, records: indexed[chapter.path] ?? [])
                    }
                    if pageCount > 1 {
                        HStack {
                            Button { chapterPage = max(0, page - 1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.disabled(page == 0)
                            Spacer()
                            Text("\(page * 100 + 1)–\(min((page + 1) * 100, visible.count)) of \(visible.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            Spacer()
                            Button { chapterPage = min(pageCount - 1, page + 1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.disabled(page + 1 >= pageCount)
                        }.buttonStyle(.borderless)
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
            .navigationTitle("Audio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Toggle("Wi-Fi downloads only", isOn: $wifiOnly)
                        Picker("Prepare with", selection: $computeProvider) {
                            Text("Kaggle").tag("kaggle")
                            Text("Colab").tag("colab")
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
                let playable = selectedChapters.count == 1 ? primaryRecord(groups[selectedChapters.first?.path ?? ""] ?? []) : nil
                let pending = playable.map { ["waiting", "downloading"].contains($0.state) && !canPlay($0) } == true
                let retry = playable.map { ["failed", "paused"].contains($0.state) && !canPlay($0) } == true
                Button {
                    if let playable, canPlay(playable) { playAudio(playable) }
                    else if let playable, retry { Task { await library.retry(playable.id) } }
                    else { prepareSelected() }
                } label: {
                    Label(playable.map(canPlay) == true ? "Play this chapter" : pending ? "Preparing this chapter…" : retry ? "Retry this chapter" : selectedChapters.count == 1 ? "Download this chapter" : "Download \(selectedChapters.count) chapters", systemImage: playable.map(canPlay) == true ? "play.fill" : pending ? "waveform" : retry ? "arrow.clockwise" : "arrow.down.circle.fill")
                        .font(.subheadline.bold()).frame(maxWidth: .infinity).padding(.vertical, 10)
                }.buttonStyle(.borderedProminent).disabled(preparing || pending || selectedVoices.isEmpty || selectedChapters.isEmpty)
                    .padding(.horizontal).padding(.vertical, 8).background(.bar)
            }
            .sheet(isPresented: $showVoices) {
                NavigationStack {
                    List { Section { QwenComputePicker() }; Section("Narrator") { QwenVoicePicker(selected: $selectedVoices) } }
                        .navigationTitle("Choose voices").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showVoices = false } } }
                }
            }
            .sheet(isPresented: $showRange) { rangePicker }
            .task {
                if !initialized {
                    let index = chapters.firstIndex { $0.path == initialChapter } ?? 0
                    fromChapter = index + 1; throughChapter = fromChapter; chapterPage = index / 100
                    selectedVoices = [library.selectedVoice(bookId: bookId, chapterId: initialChapter ?? chapters.first?.path ?? "")]
                    initialized = true
                }
                await library.refreshVoices()
                while !Task.isCancelled {
                    await library.refresh()
                    do { try await Task.sleep(for: .seconds(3)) } catch { return }
                }
            }
            .refreshable { await library.refreshVoices(); await library.refresh() }
            .onChange(of: search) { _, _ in chapterPage = 0 }
            .onChange(of: stateFilter) { _, _ in chapterPage = 0 }
            .onChange(of: voiceFilter) { _, _ in chapterPage = 0 }
            .confirmationDialog("Delete this chapter audio everywhere?", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })) {
                if let record = deleteTarget { Button("Delete \(voiceName(record))", role: .destructive) { Task { await library.delete(record.id) }; deleteTarget = nil } }
            } message: { Text("Other voices and chapter text remain available.") }
            .confirmationDialog("Delete \(deleteIDs.count) chapter voice downloads everywhere?", isPresented: Binding(get: { !deleteIDs.isEmpty }, set: { if !$0 { deleteIDs = [] } })) {
                Button("Delete selected audio everywhere", role: .destructive) {
                    let ids = deleteIDs; deleteIDs = []
                    Task { await library.deleteMany(ids) }
                }
            } message: { Text("Chapter text stays on this phone. You can prepare the voices again later.") }
        }.tint(AppTheme.accent)
    }
    private var activeVoice: String {
        let preferred = library.selectedVoice(bookId: bookId, chapterId: initialChapter ?? "")
        return selectedVoices.contains(preferred) ? preferred : selectedVoices.sorted().first ?? preferred
    }
    private var dashboard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                NovelCoverView(url: coverURL, cornerRadius: 8).frame(width: 58, height: 82)
                VStack(alignment: .leading, spacing: 5) {
                    Text(bookTitle).font(.headline).lineLimit(2)
                    Text("\(Set(bookRecords.filter(\.isAvailable).map { $0.rendition.chapterId }).count) chapters offline · \(ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file))")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(selectionLabel).font(.caption).foregroundStyle(AppTheme.accent)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 12) {
                Menu {
                    ForEach(library.voices) { voice in
                        Button(voice.name, systemImage: activeVoice == voice.id ? "checkmark" : "waveform") {
                            selectedVoices = [voice.id]; library.setBookVoice(voice.id, bookId: bookId)
                        }
                    }
                    Divider()
                    Button("Samples & custom voices", systemImage: "waveform.badge.plus") { showVoices = true }
                } label: { TTSVoiceChip(voiceId: activeVoice, name: library.voices.first { $0.id == activeVoice }?.name ?? "Narrator") }
                Spacer(minLength: 0)
                Menu {
                    Button("This chapter") { fromChapter = (chapters.firstIndex { $0.path == initialChapter } ?? 0) + 1; throughChapter = fromChapter }
                    Button("Next 10") { throughChapter = min(chapters.count, fromChapter + 9) }
                    Button("Choose range…") { showRange = true }
                } label: { Label(selectedChapters.count == 1 ? "This chapter" : "\(selectedChapters.count) chapters", systemImage: "books.vertical").font(.subheadline.weight(.medium)) }
            }
        }.padding(.horizontal, 16).padding(.vertical, 4)
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
    private func primaryRecord(_ records: [TTSDownloadRecord]) -> TTSDownloadRecord? { records.first { $0.rendition.voiceId == activeVoice } }
    private func canPlay(_ record: TTSDownloadRecord) -> Bool { record.isAvailable || record.rendition.completedChunks > 0 }
    private func playAudio(_ record: TTSDownloadRecord) {
        library.selectVoice(record.rendition.voiceId, bookId: bookId, chapterId: record.rendition.chapterId)
        ReaderTTSManager.shared.playAvailable(record)
        dismiss()
    }
    private func downloadChapter(_ chapter: TTSChapterChoice) {
        fromChapter = (chapters.firstIndex { $0.path == chapter.path } ?? 0) + 1
        throughChapter = fromChapter; prepareSelected()
    }
    private func chapterRow(_ chapter: TTSChapterChoice, records: [TTSDownloadRecord]) -> some View {
        let primary = primaryRecord(records)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(AppTheme.accent.opacity(0.1))
                    Text("\(chapter.position + 1)").font(.caption.monospacedDigit().weight(.semibold)).foregroundStyle(AppTheme.accent)
                }.frame(width: 36, height: 36)
                Button { expandedChapter = expandedChapter == chapter.path ? nil : chapter.path } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(chapter.title).font(.subheadline).foregroundStyle(.primary).lineLimit(2)
                        Text(primary.map { $0.isAvailable ? "\(voiceName($0)) · Offline" : $0.rendition.completedChunks > 0 ? "\(voiceName($0)) · \($0.rendition.completedChunks)/\($0.rendition.totalChunks) parts ready" : status($0) } ?? (records.isEmpty ? "Tap download to prepare audio" : "\(records.count) other voices saved"))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain)
                if let primary, canPlay(primary) {
                    Button { playAudio(primary) } label: { Image(systemName: "play.circle.fill").font(.title).frame(width: 44, height: 44) }.accessibilityLabel("Play \(chapter.title)")
                } else if let primary, ["failed", "paused"].contains(primary.state) {
                    Button { Task { await library.retry(primary.id) } } label: { Image(systemName: "arrow.clockwise.circle").font(.title2).frame(width: 44, height: 44) }.accessibilityLabel("Retry \(chapter.title)")
                } else if primary != nil {
                    ProgressView().frame(width: 44, height: 44)
                } else {
                    Button { downloadChapter(chapter) } label: { Image(systemName: "arrow.down.circle").font(.title2).frame(width: 44, height: 44) }.disabled(preparing).accessibilityLabel("Download \(chapter.title)")
                }
            }.buttonStyle(.borderless)
            if let primary, ["waiting", "downloading"].contains(primary.state) { ProgressView(value: primary.progress).tint(AppTheme.accent) }
            if let primary, primary.state == "failed" || primary.state == "paused" {
                HStack(alignment: .top) {
                    Text(primary.error ?? "Preparation is paused.").font(.caption).foregroundStyle(.orange).lineLimit(2)
                    Spacer()
                    Button("Retry") { Task { await library.retry(primary.id) } }.font(.caption.weight(.semibold)).buttonStyle(.borderless)
                }
            }
            if expandedChapter == chapter.path {
                ForEach(records) { audioRow($0) }
                Button("Download another voice", systemImage: "waveform.badge.plus") { showVoices = true }.font(.caption)
            }
        }.padding(.vertical, 4)
        .swipeActions {
            if let primary {
                Button("Delete", systemImage: "trash", role: .destructive) { deleteTarget = primary }
                if ["failed", "paused"].contains(primary.state) { Button("Retry", systemImage: "arrow.clockwise") { Task { await library.retry(primary.id) } }.tint(AppTheme.accent) }
            }
        }
    }
    @ViewBuilder private func audioRow(_ record: TTSDownloadRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    TTSVoiceChip(voiceId: record.rendition.voiceId, name: voiceName(record))
                    Text(status(record)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if canPlay(record) {
                    Button { playAudio(record) } label: { Image(systemName: "play.fill").frame(width: 44, height: 44) }.accessibilityLabel("Play \(voiceName(record))")
                    Button { library.selectVoice(record.rendition.voiceId, bookId: bookId, chapterId: record.rendition.chapterId) } label: {
                        Image(systemName: library.selectedVoice(bookId: bookId, chapterId: record.rendition.chapterId) == record.rendition.voiceId ? "checkmark.circle.fill" : "circle").frame(width: 44, height: 44)
                    }.accessibilityLabel("Select \(voiceName(record)) for this chapter")
                } else if record.state == "failed" || record.state == "paused" {
                    Button("Retry") { Task { await library.retry(record.id) } }
                } else { Button { library.pause(record.id) } label: { Image(systemName: "pause.fill").frame(width: 44, height: 44) } }
                Button(role: .destructive) { deleteTarget = record } label: { Image(systemName: "trash").frame(width: 44, height: 44) }.accessibilityLabel("Delete \(voiceName(record)) from phone and server")
            }.buttonStyle(.borderless)
            if record.state == "waiting" || record.state == "downloading" { ProgressView(value: min(max(record.progress, 0), 1)) }
            if let message = record.error {
                if record.state == "waiting" {
                    Label("Retrying a part automatically…", systemImage: "arrow.clockwise")
                        .font(.caption).foregroundStyle(.secondary)
                        .accessibilityHint(message)
                } else {
                    Label(message, systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
        }
    }
    private func voiceName(_ record: TTSDownloadRecord) -> String { library.voices.first { $0.id == record.rendition.voiceId }?.name ?? record.manifest?.voiceName ?? record.rendition.voiceId }
    private func status(_ record: TTSDownloadRecord) -> String {
        switch record.state {
        case "downloaded": return "Available offline · " + ByteCountFormatter.string(fromByteCount: record.bytesExpected, countStyle: .file)
        case "waiting":
            if record.rendition.status == "ready" { return "Ready on server · waiting for transfer" }
            let label = record.rendition.status == "loading" ? "Loading Qwen models" : record.rendition.status == "generating" ? "Generating speech" : record.rendition.status == "assembling" ? "Assembling audio" : record.rendition.status.capitalized
            return "\(label) · \(record.rendition.completedChunks)/\(record.rendition.totalChunks) parts"
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

@MainActor
private final class VoiceSampleRecorder: NSObject, ObservableObject, AVAudioPlayerDelegate, AVAudioRecorderDelegate {
    @Published var file: URL?
    @Published var duration = 0.0
    @Published var recording = false
    @Published var requestingPermission = false
    @Published var playing = false
    @Published var error: String?
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var disposed = false
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent("voice-draft-" + UUID().uuidString)

    func record() async {
        guard !disposed && !recording && !requestingPermission else { return }
        requestingPermission = true
        defer { requestingPermission = false }
        guard await AVAudioApplication.requestRecordPermission() else {
            error = "Allow microphone access in iPhone Settings to record a voice sample. You can also import an audio file."
            return
        }
        guard !disposed else { return }
        stopPlayback()
        if ReaderTTSManager.shared.isSpeaking { ReaderTTSManager.shared.pause() }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let path = folder.appendingPathComponent(UUID().uuidString + ".m4a")
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            let next = try AVAudioRecorder(url: path, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 24000, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64000])
            next.delegate = self
            guard next.record(forDuration: 60) else { throw TTSError.request("Could not start recording.") }
            recorder = next; file = path; duration = 0; recording = true; error = nil
            timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.duration = self?.recorder?.currentTime ?? self?.duration ?? 0 }
            }
        } catch { self.error = error.localizedDescription; stopRecording() }
    }
    func stopRecording() {
        if let recorder, recorder.isRecording { duration = recorder.currentTime }
        recorder?.stop(); recorder = nil; timer?.invalidate(); timer = nil; recording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    func importSample(_ url: URL) async {
        stopRecording(); stopPlayback()
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size > 0, size <= 6_000_000 else { throw TTSError.request("Choose an audio file smaller than 6 MB.") }
            let seconds = try await AVURLAsset(url: url).load(.duration).seconds
            guard !disposed else { return }
            guard seconds.isFinite, seconds >= 3, seconds <= 60 else { throw TTSError.request("Choose between 3 and 60 seconds of speech.") }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let copy = folder.appendingPathComponent(UUID().uuidString).appendingPathExtension(url.pathExtension)
            try FileManager.default.copyItem(at: url, to: copy)
            file = copy; duration = seconds; error = nil
        } catch { self.error = error.localizedDescription }
    }
    func togglePlayback() {
        if playing { stopPlayback(); return }
        guard let file else { return }
        do {
            if ReaderTTSManager.shared.isSpeaking { ReaderTTSManager.shared.pause() }
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(contentsOf: file); player?.delegate = self
            playing = player?.play() == true
        } catch { self.error = error.localizedDescription }
    }
    func stopPlayback() { player?.stop(); player = nil; playing = false }
    func cleanUp() { disposed = true; stopRecording(); stopPlayback(); try? FileManager.default.removeItem(at: folder) }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { Task { @MainActor [weak self] in self?.stopPlayback() } }
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.recording, self.recorder === recorder else { return }
            self.stopRecording()
            if flag, let file = self.file { self.duration = (try? await AVURLAsset(url: file).load(.duration).seconds) ?? self.duration }
            else if !flag { self.error = "Recording was interrupted. Record a new sample."; self.file = nil }
        }
    }
}

private struct CustomVoiceCreationView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var sample = VoiceSampleRecorder()
    @State private var name = ""
    @State private var transcript = ""
    @State private var importing = false
    @State private var saving = false
    @State private var error: String?
    let onCreated: (TTSVoice) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section { QwenComputePicker() }
                Section {
                    TextField("Voice name", text: $name).textInputAutocapitalization(.words)
                }
                Section {
                    HStack {
                        Button {
                            if sample.recording { sample.stopRecording() } else { Task { await sample.record() } }
                        } label: { Label(sample.recording ? "Stop recording" : "Record sample", systemImage: sample.recording ? "stop.circle.fill" : "mic.fill") }
                        .buttonStyle(.borderless)
                        .disabled(sample.requestingPermission)
                        Spacer()
                        Text("\(Int(sample.duration))s / 60s").monospacedDigit().foregroundStyle(.secondary)
                    }
                    Button { importing = true } label: { Label("Import audio", systemImage: "square.and.arrow.down") }.disabled(sample.recording)
                    if sample.file != nil && !sample.recording {
                        Button { sample.togglePlayback() } label: { Label(sample.playing ? "Stop sample" : "Listen to sample", systemImage: sample.playing ? "stop.fill" : "play.fill") }
                    }
                } header: { Text("Voice sample") } footer: {
                    Text("Record 3–60 seconds of clear speech without music or other speakers. Speak naturally with a mostly neutral tone. Longer recordings do not guarantee a better clone.")
                }
                Section {
                    NavigationLink { VoiceReferencePassageView() } label: { Label("Read or copy the sample passage", systemImage: "text.quote") }
                    Button("I read the full passage exactly") { transcript = VoiceReferencePassageView.passage }
                        .disabled(sample.recording || sample.file == nil)
                }
                Section {
                    TextEditor(text: $transcript).frame(minHeight: 100).accessibilityLabel("Recording transcript, optional")
                } header: { Text("Transcript · optional") } footer: {
                    Text("Enter exactly what was spoken. Leave blank to transcribe the sample automatically during preparation.")
                }
                if let message = error ?? sample.error { Section { Text(message).foregroundStyle(.red).textSelection(.enabled) } }
                Section {
                    Button {
                        guard let file = sample.file else { return }
                        sample.stopPlayback(); saving = true; error = nil
                        Task {
                            do {
                                let voice = try await TTSOfflineLibrary.shared.addCustomVoice(name: name.trimmingCharacters(in: .whitespacesAndNewlines), sample: file, transcript: transcript.trimmingCharacters(in: .whitespacesAndNewlines))
                                onCreated(voice); dismiss()
                            } catch { self.error = error.localizedDescription }
                            saving = false
                        }
                    } label: {
                        HStack { if saving { ProgressView() }; Text(saving ? "Saving voice…" : "Add voice and prepare preview") }
                    }
                    .disabled(saving || sample.recording || sample.file == nil || sample.duration < 3 || sample.duration > 60 || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 60 || transcript.count > 6000)
                } footer: { Text("Your sample stays on this phone. Chapter audio and the voice preview are prepared remotely, then downloaded for offline listening.") }
            }
            .disabled(saving)
            .navigationTitle("Your voice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.audio]) { result in
                switch result {
                case .success(let url): Task { await sample.importSample(url) }
                case .failure(let error): self.error = error.localizedDescription
                }
            }
            .onChange(of: sample.file) { _, _ in transcript = "" }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in if sample.recording { sample.stopRecording() } }
        }
        .interactiveDismissDisabled(saving || sample.recording || sample.requestingPermission)
        .onDisappear { sample.cleanUp() }
    }
}
