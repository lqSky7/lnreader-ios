import Foundation
import SwiftUI

struct TTSPlaybackControls: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
        .animation(AppMotion.gentle(reduceMotion: reduceMotion), value: isFollowing)
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
            .foregroundStyle(.primary)
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
        VStack(spacing: 2) {
            scrubberSection
            transportRow
            secondaryRow
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(alignment: .bottom) {
            LinearGradient(colors: TTSVoicePalette.colors(for: voiceId).map { $0.opacity(0.30) } + [.clear], startPoint: .bottomLeading, endPoint: .topTrailing)
                .mask(LinearGradient(colors: [.clear, .white], startPoint: .top, endPoint: .bottom))
                .clipShape(.rect(cornerRadius: 26))
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
        .frame(maxWidth: 500)
        .padding(.horizontal, 10)
        .padding(.bottom, 2)
        .frame(maxWidth: .infinity)
    }

    private var scrubberSection: some View {
        VStack(spacing: 0) {
            Slider(
                value: scrubberBinding,
                in: 0...safeRangeUpper,
                onEditingChanged: handleScrubEditing
            )
            .disabled(safeDuration <= 0)
            .accessibilityLabel("Playback progress")
            .accessibilityValue("\(formatTime(displayedTime)) of \(formatTime(safeDuration))")

            HStack {
                Text(formatTime(displayedTime))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)
                if let playbackStatus { Text(playbackStatus).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1) }
                Spacer(minLength: 8)

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
                .foregroundStyle((sleepTimerLabel.isEmpty || sleepTimerLabel == "Off") ? .secondary : .primary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel((sleepTimerLabel.isEmpty || sleepTimerLabel == "Off") ? "Sleep timer" : "Sleep timer: \(sleepTimerLabel)")

            Button(action: onSkipBack) {
                Image(systemName: "gobackward.15")
                    .font(.system(size: 20))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Rewind 15 seconds")

            Button(action: onPlayPause) {
                ZStack {
                    Circle()
                        .fill(.white)
                        .frame(width: 44, height: 44)

                    if isBuffering {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.black)
                    } else {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(.black)
                    }
                }
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isBuffering ? "Buffering" : (isPlaying ? "Pause" : "Play"))

            Button(action: onSkipForward) {
                Image(systemName: "goforward.30")
                    .font(.system(size: 20))
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
        colors = TTSVoicePalette.colors(for: voiceId)
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

/// Base hue plus its two split-complementary accents; stable after random assignment.
enum TTSVoicePalette {
    /// Hues between yellow-green and teal read as "green", which looks muddy next
    /// to the rest of the palette. A stored hue outside that band is left alone, so
    /// a voice that already looked right keeps its colour.
    private static func safeHue(_ value: Double) -> Double {
        let hue = value - floor(value)
        guard (0.19...0.47).contains(hue) else { return hue }
        return hue < 0.33 ? 0.13 : 0.58
    }

    static func colors(for voiceId: String) -> [Color] {
        let defaults = UserDefaults.standard, key = "tts.voice-palette.v2"
        var assigned = defaults.dictionary(forKey: key) as? [String: Double] ?? [:]
        let hue: Double
        if let saved = assigned[voiceId], saved.isFinite {
            hue = safeHue(saved)
        } else {
            // Curated hues: warm ambers/roses and cool azures. No greens.
            let curated: [Double] = [0.02, 0.06, 0.10, 0.13, 0.17, 0.56, 0.60, 0.64, 0.68, 0.90, 0.94, 0.97]
            func distance(_ candidate: Double) -> Double {
                assigned.values.map { let d = abs(candidate - safeHue($0)); return min(d, 1 - d) }.min() ?? 1
            }
            hue = curated.max { distance($0) < distance($1) } ?? 0.02
            assigned[voiceId] = hue
            defaults.set(assigned, forKey: key)
        }
        // Analogous partners keep each voice in one colour family, so no gradient
        // ever pairs green with purple.
        return [Color(hue: hue, saturation: 0.60, brightness: 0.54),
                Color(hue: (hue + 0.045).truncatingRemainder(dividingBy: 1), saturation: 0.54, brightness: 0.44),
                Color(hue: (hue - 0.05 + 1).truncatingRemainder(dividingBy: 1), saturation: 0.64, brightness: 0.60)]
    }
}
