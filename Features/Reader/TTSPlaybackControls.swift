import Foundation
import SwiftUI

struct TTSPlaybackControls: View {
    let isPlaying: Bool
    let isBuffering: Bool
    let elapsed: Double
    let duration: Double
    let rate: Double
    let voiceId: String
    let voiceName: String
    let isFollowing: Bool
    let sleepTimerLabel: String
    let playbackStatus: String?
    let onSettings: () -> Void
    let onPlayPause: () -> Void
    let onSkipBack: () -> Void
    let onSkipForward: () -> Void
    let onRate: () -> Void
    let onVoice: () -> Void
    let onBookmark: () -> Void
    let onSleep: () -> Void
    let onFollow: () -> Void
    let onSeek: (Double) -> Void
    let onScrub: (Double?) -> Void

    @State private var scrubValue: Double = 0.0
    @State private var isScrubbing: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            if !isFollowing {
                followBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            Spacer()

            bottomControlsPanel
        }
        .animation(.easeInOut(duration: 0.25), value: isFollowing)
    }

    private var followBanner: some View {
        Button(action: onFollow) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                Text("Back to current")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .foregroundStyle(AppTheme.accent)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .glassEffect()
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back to current reading position")
        .padding(.top, 72)
    }

    private var bottomControlsPanel: some View {
        VStack(spacing: 8) {
            if let playbackStatus { Text(playbackStatus).font(.caption).foregroundStyle(.secondary).lineLimit(2).frame(maxWidth: .infinity) }
            scrubberSection
            transportRow
            secondaryRow
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: .rect(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
        .frame(maxWidth: 500)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
    }

    private var scrubberSection: some View {
        VStack(spacing: 4) {
            Slider(
                value: scrubberBinding,
                in: 0...safeRangeUpper,
                onEditingChanged: handleScrubEditing
            )
            .tint(AppTheme.accent)
            .disabled(safeDuration <= 0)
            .accessibilityLabel("Playback progress")
            .accessibilityValue("\(formatTime(displayedTime)) of \(formatTime(safeDuration))")

            HStack {
                Text(formatTime(displayedTime))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)

                Spacer()

                Text("-" + formatTime(max(0, safeDuration - displayedTime)))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var transportRow: some View {
        HStack(spacing: 0) {
            Button(action: onSleep) {
                VStack(spacing: 2) {
                    Image(systemName: (sleepTimerLabel.isEmpty || sleepTimerLabel == "Off") ? "moon.zzz" : "moon.zzz.fill")
                        .font(.system(size: 18))
                    if !(sleepTimerLabel.isEmpty || sleepTimerLabel == "Off") {
                        Text(sleepTimerLabel)
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                    }
                }
                .foregroundStyle((sleepTimerLabel.isEmpty || sleepTimerLabel == "Off") ? .primary : AppTheme.accent)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel((sleepTimerLabel.isEmpty || sleepTimerLabel == "Off") ? "Sleep timer" : "Sleep timer: \(sleepTimerLabel)")

            Button(action: onSkipBack) {
                Image(systemName: "gobackward.15")
                    .font(.system(size: 22))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Rewind 15 seconds")

            Button(action: onPlayPause) {
                ZStack {
                    Circle()
                        .fill(AppTheme.accent)
                        .frame(width: 54, height: 54)

                    if isBuffering {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    } else {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                            .offset(x: isPlaying ? 0 : 2)
                    }
                }
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isBuffering ? "Buffering" : (isPlaying ? "Pause" : "Play"))

            Button(action: onSkipForward) {
                Image(systemName: "goforward.30")
                    .font(.system(size: 22))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Fast forward 30 seconds")

            Button(action: onRate) {
                Text(formatRate(rate))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Playback speed \(formatRate(rate))")
        }
    }

    private var secondaryRow: some View {
        ZStack {
            HStack {
                Button(action: onSettings) {
                    Image(systemName: "textformat.size")
                        .font(.system(size: 18))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Reader settings")

                Spacer()

                Button(action: onBookmark) {
                    Image(systemName: "bookmark")
                        .font(.system(size: 18))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Bookmark")
            }

            Button(action: onVoice) {
                TTSVoiceChip(voiceId: voiceId, name: voiceName)
                    .frame(minHeight: 44)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Voice: \(voiceName)")
            .padding(.horizontal, 52)
        }
    }

    private var safeDuration: Double {
        guard duration.isFinite && !duration.isNaN && duration > 0 else { return 0 }
        return duration
    }

    private var safeRangeUpper: Double {
        safeDuration > 0 ? safeDuration : 1.0
    }

    private var clampedElapsed: Double {
        guard elapsed.isFinite && !elapsed.isNaN && elapsed >= 0 else { return 0 }
        return safeDuration > 0 ? min(elapsed, safeDuration) : 0
    }

    private var displayedTime: Double {
        isScrubbing ? scrubValue : clampedElapsed
    }

    private var scrubberBinding: Binding<Double> {
        Binding(
            get: { displayedTime },
            set: { scrubValue = $0; if isScrubbing { onScrub($0) } }
        )
    }

    private func handleScrubEditing(_ isEditing: Bool) {
        if isEditing {
            isScrubbing = true
            scrubValue = clampedElapsed
            onScrub(scrubValue)
        } else {
            isScrubbing = false
            let clampedTarget = min(max(scrubValue, 0), safeDuration)
            onSeek(clampedTarget)
            onScrub(nil)
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && !seconds.isNaN && seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let remainingSeconds = total % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        } else {
            return String(format: "%d:%02d", minutes, remainingSeconds)
        }
    }

    private func formatRate(_ value: Double) -> String {
        let text = String(format: "%g", value)
        return "\(text)x"
    }
}


/// A voice keeps its color across chapters, offline playback, and app launches.
struct TTSVoiceChip: View {
    let voiceId: String
    let name: String
    private let colors: [Color]

    init(voiceId: String, name: String) {
        self.voiceId = voiceId
        self.name = name
        let presets = ["qwen-ryan", "qwen-aiden", "qwen-vivian", "qwen-serena", "qwen-uncle-fu", "qwen-dylan", "qwen-eric", "qwen-anna", "qwen-sohee"]
        let defaults = UserDefaults.standard
        let key = "tts.voice-gradient-hues"
        var assigned = defaults.dictionary(forKey: key) as? [String: Double] ?? [:]
        let hue: Double
        if let preset = presets.firstIndex(of: voiceId) {
            hue = Double(preset) / 12
        } else if let saved = assigned[voiceId], saved.isFinite, (0..<1).contains(saved) {
            hue = saved
        } else {
            let used = Array(assigned.values) + presets.indices.map { Double($0) / 12 }
            func separation(_ candidate: Double) -> Double {
                used.map { min(abs(candidate - $0), 1 - abs(candidate - $0)) }.min() ?? 1
            }
            // Pick a random unused color with room from existing voices. This
            // continues to work beyond a small fixed palette of custom voices.
            hue = (0..<64).map { _ in Double.random(in: 0..<1) }.max { separation($0) < separation($1) } ?? 0.75
            assigned[voiceId] = hue
            defaults.set(assigned, forKey: key)
        }
        colors = [Color(hue: hue, saturation: 0.72, brightness: 0.53), Color(hue: (hue + 0.10).truncatingRemainder(dividingBy: 1), saturation: 0.68, brightness: 0.64)]
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "waveform").font(.caption.weight(.semibold))
            Text(name).font(.subheadline.weight(.semibold)).lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 0.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Voice: \(name)")
    }
}
