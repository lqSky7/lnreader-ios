import AVFoundation
import Combine
import Foundation
import MediaPlayer

/// The app-owned player only opens verified local Qwen chapter files.
/// Generation, networking, and download management never happen in this player.
@MainActor
final class ReaderTTSManager: ObservableObject {
    static let shared = ReaderTTSManager()
    @Published private(set) var isSpeaking = false
    @Published private(set) var isPaused = false
    @Published private(set) var currentBlockIndex: Int?
    @Published private(set) var currentWord: TTSWordTiming?
    @Published private(set) var manifest: TTSManifest?
    @Published private(set) var elapsed = 0.0
    @Published private(set) var duration = 0.0
    @Published private(set) var isBuffering = false
    @Published private(set) var rate = 1.0
    @Published private(set) var sleepTimerLabel = "Off"
    @Published var errorMessage: String?
    var totalBlocks: Int { manifest?.blocks.count ?? 0 }

    private let player = AVPlayer()
    private var observer: Any?
    private var itemObservation: NSKeyValueObservation?
    private var notificationTokens: [NSObjectProtocol] = []
    private var sleepDeadline: Date?
    private var sleepAtChapterEnd = false
    private var wasPlayingBeforeInterruption = false
    private var epoch = UUID()
    private var lastPositionSave = Date.distantPast
    private var lastNowPlaying = Date.distantPast

    private init() {
        let saved = UserDefaults.standard.double(forKey: "tts.speed")
        rate = saved > 0 ? min(max(saved, 0.5), 3) : 1
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.05, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor in self?.update(time.seconds) }
        }
        notificationTokens.append(NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] note in
            Task { @MainActor in
                guard let self, let item = note.object as? AVPlayerItem, item === self.player.currentItem else { return }
                self.finishChapter()
            }
        })
        #if os(iOS)
        notificationTokens.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            Task { @MainActor in self?.handleInterruption(note) }
        })
        notificationTokens.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            Task { @MainActor in
                if let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt, reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { self?.pause() }
            }
        })
        #endif
        configureRemoteCommands()
    }

    func play(renditionID: String, paragraph: Int? = nil, offset: Int = 0, resume: Bool = true) {
        do {
            let next = try TTSOfflineLibrary.shared.localManifest(renditionID)
            TTSVoicePreviewPlayer.shared.stop()
            let saved = position(for: next.bookId)
            let start: Double
            if let paragraph { start = next.time(paragraph: paragraph, offset: offset) ?? 0 }
            else if resume, let saved, saved.renditionId == next.id { start = saved.time }
            else { start = 0 }
            epoch = UUID()
            player.pause()
            persistPosition()
            manifest = next; duration = next.duration; elapsed = start
            currentWord = next.word(at: start); currentBlockIndex = currentWord?.paragraphIndex
            errorMessage = nil; isSpeaking = true; isPaused = false; isBuffering = true
            #if os(iOS)
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
            #endif
            let item = AVPlayerItem(url: TTSStorage.audio(next.id))
            itemObservation?.invalidate()
            player.replaceCurrentItem(with: item)
            let activeEpoch = epoch
            itemObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                Task { @MainActor in
                    guard let self, self.epoch == activeEpoch else { return }
                    if item.status == .readyToPlay {
                        self.itemObservation?.invalidate(); self.itemObservation = nil
                        self.player.seek(to: CMTime(seconds: min(self.elapsed, max(0, next.duration - 0.02)), preferredTimescale: 24000), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
                            Task { @MainActor in
                                guard let self, self.epoch == activeEpoch, finished else { return }
                                self.isBuffering = false
                                if !self.isPaused { self.player.playImmediately(atRate: Float(self.rate)) }
                                self.updateNowPlaying()
                            }
                        }
                    } else if item.status == .failed {
                        self.errorMessage = item.error?.localizedDescription ?? "This local audio could not be opened."
                        self.isBuffering = false; self.isPaused = true
                    }
                }
            }
            updateNowPlaying()
        } catch { errorMessage = error.localizedDescription; isBuffering = false }
    }

    func switchVoice(to record: TTSDownloadRecord) {
        guard let source = currentWord, manifest?.bookId == record.rendition.bookId, manifest?.chapterId == record.rendition.chapterId else {
            play(renditionID: record.id); return
        }
        let wasPaused = isPaused
        play(renditionID: record.id, paragraph: source.paragraphIndex, offset: source.sourceStart, resume: false)
        if wasPaused { pause() }
    }
    func seek(paragraph: Int, offset: Int) {
        guard let time = manifest?.time(paragraph: paragraph, offset: offset) else { return }
        seek(to: time)
    }
    func seek(to seconds: Double) {
        guard seconds.isFinite, manifest != nil else { return }
        let target = min(max(0, seconds), max(0, duration - 0.01))
        player.seek(to: CMTime(seconds: target, preferredTimescale: 24000), toleranceBefore: .zero, toleranceAfter: .zero)
        update(target); persistPosition(); updateNowPlaying()
    }
    func skip(_ seconds: Double) { seek(to: elapsed + seconds) }
    func togglePause() { isPaused ? resume() : pause() }
    func pause() { guard isSpeaking else { return }; player.pause(); isPaused = true; persistPosition(); updateNowPlaying() }
    func resume() { guard isSpeaking else { return }; isPaused = false; if !isBuffering { player.playImmediately(atRate: Float(rate)) }; updateNowPlaying() }
    func setRate(_ value: Double) {
        guard value.isFinite else { return }
        rate = min(max(value, 0.5), 3); UserDefaults.standard.set(rate, forKey: "tts.speed")
        if isSpeaking && !isPaused && !isBuffering { player.rate = Float(rate) }
        updateNowPlaying()
    }
    func setSleep(minutes: Int?) {
        sleepAtChapterEnd = false
        sleepDeadline = minutes.map { Date().addingTimeInterval(Double($0 * 60)) }
        sleepTimerLabel = minutes.map { "\($0)m" } ?? "Off"
    }
    func sleepAfterChapter() { sleepDeadline = nil; sleepAtChapterEnd = true; sleepTimerLabel = "Chapter" }
    func stop() {
        persistPosition(); epoch = UUID(); itemObservation?.invalidate(); itemObservation = nil
        player.pause(); player.replaceCurrentItem(with: nil)
        isSpeaking = false; isPaused = false; isBuffering = false; currentWord = nil; currentBlockIndex = nil
        manifest = nil; elapsed = 0; duration = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
    private func update(_ time: Double) {
        guard isSpeaking, time.isFinite else { return }
        elapsed = min(max(0, time), duration)
        let word = manifest?.word(at: elapsed)
        if word != currentWord { currentWord = word; currentBlockIndex = word?.paragraphIndex }
        if let deadline = sleepDeadline, Date() >= deadline { setSleep(minutes: nil); pause() }
        if Date().timeIntervalSince(lastPositionSave) > 3 { persistPosition() }
        if Date().timeIntervalSince(lastNowPlaying) > 1 { updateNowPlaying() }
    }
    private func positionKey(_ bookId: String) -> String { "tts.listeningPosition." + bookId }
    func position(for bookId: String) -> TTSListeningPosition? {
        guard let data = UserDefaults.standard.data(forKey: positionKey(bookId)) else { return nil }
        return try? JSONDecoder().decode(TTSListeningPosition.self, from: data)
    }
    private func persistPosition() {
        guard let manifest, let word = currentWord else { return }
        let value = TTSListeningPosition(renditionId: manifest.id, paragraph: word.paragraphIndex, offset: word.sourceStart, time: elapsed)
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: positionKey(manifest.bookId)) }
        lastPositionSave = Date()
    }
    private func finishChapter() {
        persistPosition()
        if sleepAtChapterEnd { sleepAtChapterEnd = false; sleepTimerLabel = "Off"; pause(); return }
        guard let current = manifest else { return }
        let library = TTSOfflineLibrary.shared
        let following = library.downloads(bookId: current.bookId).filter { $0.isAvailable && $0.rendition.position > current.position }.sorted { $0.rendition.position < $1.rendition.position }
        guard let first = following.first else { pause(); return }
        let selected = library.selectedVoice(bookId: current.bookId, chapterId: first.rendition.chapterId)
        guard let next = following.first(where: { $0.rendition.chapterId == first.rendition.chapterId && $0.rendition.voiceId == selected }),
              next.rendition.position == current.position + 1 else {
            pause(); errorMessage = "The next chapter is not downloaded in its selected voice."; return
        }
        play(renditionID: next.id, resume: false)
    }
    private func updateNowPlaying() {
        guard let manifest else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: manifest.title,
            MPMediaItemPropertyAlbumTitle: manifest.bookTitle,
            MPMediaItemPropertyArtist: manifest.voiceName,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPaused ? 0 : rate,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1
        ]
        lastNowPlaying = Date()
    }
    private func configureRemoteCommands() {
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.resume() }; return .success }
        commands.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.pause() }; return .success }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.togglePause() }; return .success }
        commands.skipBackwardCommand.preferredIntervals = [15]
        commands.skipForwardCommand.preferredIntervals = [30]
        commands.skipBackwardCommand.addTarget { [weak self] _ in Task { @MainActor in self?.skip(-15) }; return .success }
        commands.skipForwardCommand.addTarget { [weak self] _ in Task { @MainActor in self?.skip(30) }; return .success }
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let value = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: value.positionTime) }; return .success
        }
    }
    #if os(iOS)
    private func handleInterruption(_ note: Notification) {
        guard let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt else { return }
        if type == AVAudioSession.InterruptionType.began.rawValue { wasPlayingBeforeInterruption = isSpeaking && !isPaused; pause() }
        else if let options = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt, AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume), wasPlayingBeforeInterruption { resume() }
    }
    #endif
}
