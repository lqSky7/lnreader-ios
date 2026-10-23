import SwiftUI

struct TTSSettingsView: View {
    @AppStorage("tts.enabled") private var enabled = true
    @AppStorage("tts.voice") private var defaultVoice = "breeze-warm"
    @ObservedObject private var library = TTSOfflineLibrary.shared
    @State private var selected: Set<String> = []
    @State private var showStorage = false
    var body: some View {
        Form {
            Section { Toggle("Enable narration", isOn: $enabled); NarrationComputePicker() }.tint(AppTheme.controlFill)
            Section {
                NarrationVoicePicker(selected: $selected)
            } header: { Text("Default narrator") }
              footer: { Text("Breeze narration is prepared with your selected provider. These narrators are voice designs made for LNReader. Preview a voice, then download chapters to listen offline.") }
            Section {
                if let engine = library.engineState, engine.needsAttention {
                    Label(engine.message, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.secondary)
                }
                NavigationLink("Manage downloaded audio") {
                    List {
                        ForEach(library.records.filter { !$0.isPreview }) { record in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(record.rendition.bookTitle).font(.headline)
                                    Text(record.rendition.title).font(.caption)
                                    Text("\(library.voices.first { $0.id == record.rendition.voiceId }?.name ?? record.manifest?.voiceName ?? record.rendition.voiceId) · \(record.isAvailable ? "Available offline" : record.state)").font(.caption).foregroundStyle(.secondary)
                                }
                                if let message = record.error { Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange).accessibilityLabel(message) }
                                Spacer()
                                Button(role: .destructive) { Task { await library.delete(record.id) } } label: { Image(systemName: "trash").frame(width: 44, height: 44) }
                            }
                        }
                    }.navigationTitle("Audio storage")
                }
                Text("Audio stays until you delete it. Deleting chapter audio also clears its server preparation and cache. Offline deletions sync when you reconnect.").font(.caption).foregroundStyle(.secondary)
                Button("Refresh voices and download previews") { Task { await library.refreshVoices() } }
                if let error = library.errorMessage { Text(error).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Narration")
        .navigationBarTitleDisplayMode(.large)
        .task { selected = [library.migratedDefaultVoice]; await library.refreshVoices() }
        .onChange(of: selected) { oldValue, newValue in
            if let added = newValue.subtracting(oldValue).first { defaultVoice = added; selected = [added] }
            else if newValue.isEmpty { selected = [defaultVoice] }
        }
    }
}
