// TTSSettingsView.swift
// TTS Configuration page (offline models, voices, HuggingFace connection).

import SwiftUI

struct TTSSettingsView: View {
    @StateObject private var modelManager = TTSModelManager()

    @AppStorage("tts.useRemote") private var useRemote: Bool = false
    @AppStorage("tts.remoteURL") private var remoteURL: String = "https://sky788-tts.hf.space"
    @AppStorage("tts.voice") private var ttsVoiceId: String = "af_heart"

    var body: some View {
        Form {
            Section("TTS Mode") {
                Toggle("Use Remote TTS (Hugging Face)", isOn: $useRemote)
                    .tint(AppTheme.accent)
                
                if useRemote {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Server URL")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading, 8)
                        
                        HStack(spacing: 8) {
                            Image(systemName: "link")
                                .foregroundStyle(.secondary)
                                .font(Typography.caption)

                            TextField("https://your-space.hf.space", text: $remoteURL)
                                .font(Typography.body)
                                .textFieldStyle(.plain)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)

                            if !remoteURL.isEmpty {
                                Button {
                                    withAnimation { remoteURL = "" }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .glassEffect(.regular, in: .rect(cornerRadius: 20))
                        .contentShape(.rect(cornerRadius: 20))
                    }
                    .padding(.vertical, 4)
                }
            }
            
            Section("Local TTS Model") {
                modelStatusRow
            }
            
            Section("Voice Selection") {
                Picker("Voice", selection: $ttsVoiceId) {
                    ForEach(voiceOptions, id: \.self) { option in
                        Text(voiceLabel(for: option))
                            .tag(option)
                    }
                }
                .pickerStyle(.navigationLink)
            }
        }
        .navigationTitle("TTS Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            modelManager.cancelDownload()
        }
    }

    // MARK: - Model Status Row

    @ViewBuilder
    private var modelStatusRow: some View {
        switch modelManager.state {
        case .notDownloaded:
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Model Download Required")
                        .font(.body)
                        .fontWeight(.semibold)
                    Text("~330 MB download needed for offline speech")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Download") {
                    modelManager.downloadModel()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
                .controlSize(.small)
            }

        case .downloading(let progress, let status):
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(status)
                        .font(.body)
                        .foregroundColor(.primary)
                    Spacer()
                    Text("\(Int(progress * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                }
                ProgressView(value: progress)
                    .tint(AppTheme.accent)
                HStack {
                    Spacer()
                    Button("Cancel") {
                        modelManager.cancelDownload()
                    }
                    .font(.caption)
                    .foregroundColor(.red)
                }
            }

        case .downloaded:
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Offline Model Downloaded")
                        .font(.body)
                        .fontWeight(.semibold)
                    Text("Ready for offline text-to-speech")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(role: .destructive) {
                    modelManager.deleteModel()
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

        case .loading:
            HStack(spacing: 12) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading local model…")
                    .font(.body)
                    .foregroundColor(.secondary)
            }

        case .ready:
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Model Ready and Loaded")
                        .font(.body)
                        .fontWeight(.semibold)
                    Text("Model files cached and loaded in memory")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(role: .destructive) {
                    modelManager.deleteModel()
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

        case .error(let message):
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text("Download failed")
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundColor(.red)
                }
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                Button("Retry") {
                    modelManager.dismissError()
                    modelManager.downloadModel()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
                .controlSize(.small)
            }
        }
    }

    // MARK: - Voice Helpers

    private func voiceLabel(for voice: String) -> String {
        let name = voiceName(for: voice)
        let language = voiceLanguage(for: voice)
        let gender = voiceGender(for: voice)
        return "\(name) • \(language) \(gender)"
    }

    private func voiceName(for voice: String) -> String {
        let parts = voice.split(separator: "_", maxSplits: 1)
        guard parts.count == 2 else { return voice }
        return parts[1].replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func voiceLanguage(for voice: String) -> String {
        guard let prefix = voice.first else { return "??" }
        switch prefix {
        case "a": return "EN-US"
        case "b": return "EN-UK"
        case "e": return "ES"
        case "f": return "FR"
        case "h": return "HI"
        case "i": return "IT"
        case "j": return "JA"
        case "k": return "KO"
        case "p": return "PT-BR"
        case "z": return "ZH"
        default: return "??"
        }
    }

    private func voiceGender(for voice: String) -> String {
        let chars = Array(voice)
        guard chars.count > 1 else { return "" }
        return chars[1] == "f" ? "F" : "M"
    }

    private var voiceOptions: [String] {
        [
            "af_heart", "af_alloy", "af_aoede", "af_bella", "af_jessica", "af_kore",
            "af_nicole", "af_nova", "af_river", "af_sarah", "af_sky",
            "am_adam", "am_echo", "am_eric", "am_fenrir", "am_liam", "am_michael",
            "am_onyx", "am_puck", "am_santa",
            "bf_alice", "bf_emma", "bf_isabella", "bf_lily",
            "bm_daniel", "bm_fable", "bm_george", "bm_lewis",
            "ef_dora", "em_alex", "em_santa",
            "ff_siwis",
            "hf_alpha", "hf_beta", "hm_omega", "hm_psi",
            "if_sara", "im_nicola",
            "jf_alpha", "jf_gongitsune", "jf_nezumi", "jf_tebukuro", "jm_kumo",
            "kf_somi",
            "pf_dora", "pm_alex", "pm_santa",
            "zf_xiaobei", "zf_xiaoni", "zf_xiaoxiao", "zf_xiaoyi",
            "zm_yunjian", "zm_yunxi", "zm_yunxia", "zm_yunyang"
        ]
    }
}
