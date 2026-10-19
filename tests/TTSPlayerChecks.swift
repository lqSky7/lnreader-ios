import AppKit
import AVFoundation
import Foundation

// Only the library/network boundaries are replaced; this runs the real player.
@MainActor final class TTSOfflineLibrary {
    static let shared = TTSOfflineLibrary()
    var fixture: TTSManifest!
    var voices = TTSVoice.presets
    func localText(bookId: String, chapterId: String) -> TTSChapterText? { nil }
    func localManifest(_ id: String) throws -> TTSManifest { fixture }
    func downloads(bookId: String) -> [TTSDownloadRecord] { [] }
    func selectedVoice(bookId: String, chapterId: String) -> String { "qwen-sohee" }
}
@MainActor final class TTSVoicePreviewPlayer { static let shared = TTSVoicePreviewPlayer(); func stop() {} }
@MainActor struct TTSAPIClient {
    static var fixture: TTSStreamingManifest?
    init(backendURL: String) {}
    func stream(_ rendition: TTSRendition) async throws -> TTSStreamingManifest {
        guard let fixture = Self.fixture else { throw TTSError.missingAudio }; return fixture
    }
}
enum TTSStorage {
    static var fixture: URL!
    static var partsRoot: URL!
    static func audio(_ id: String) -> URL { fixture }
    static func streamManifest(_ id: String) -> URL { URL(fileURLWithPath: "/nonexistent/tts-test") }
    static func cacheStream(_ manifest: TTSStreamingManifest) throws {}
    static func loadStreamPart(_ id: String, part: TTSStreamPart, client: TTSAPIClient) async throws -> URL { partsRoot.appendingPathComponent(part.sha256 + "." + part.format) }
}
@main struct PlayerChecks {
    @MainActor static func main() {
        _ = NSApplication.shared
        Task { @MainActor in
            do {
                let folder = URL(fileURLWithPath: CommandLine.arguments[1])
                let manifest = try JSONDecoder().decode(TTSManifest.self, from: Data(contentsOf: folder.appendingPathComponent("manifest.json")))
                TTSOfflineLibrary.shared.fixture = manifest; TTSStorage.fixture = folder.appendingPathComponent("audio.m4a")
                let saved = TTSListeningPosition(renditionId: manifest.id, paragraph: 0, offset: 0, time: 5)
                let key = "tts.listeningPosition." + manifest.bookId
                UserDefaults.standard.set(try JSONEncoder().encode(saved), forKey: key)
                let player = ReaderTTSManager.shared
                player.play(renditionID: manifest.id); player.pause()
                try await wait { !player.isBuffering }
                precondition(abs(player.elapsed - 5) < 0.15, "Initial callbacks must not reset a resumed seek")
                player.seek(to: 8); player.seek(to: 1)
                try await wait { !player.isBuffering }
                try await Task.sleep(for: .milliseconds(200))
                precondition(abs(player.elapsed - 1) < 0.15, "Latest seek wins; old player callbacks must not restore the previous position")
                precondition(player.currentWord == manifest.word(at: player.elapsed))
                player.stop()
                precondition(player.currentWord == nil && player.manifest == nil)
                UserDefaults.standard.removeObject(forKey: key)
                print("PASS: real AVPlayer resumed time, rapid backward seeks, clock-linked words, and stop cleanup")
                if CommandLine.arguments.count > 2 {
                    let streamRoot = URL(fileURLWithPath: CommandLine.arguments[2])
                    let stream = try JSONDecoder().decode(TTSStreamingManifest.self, from: Data(contentsOf: streamRoot.appendingPathComponent("stream.json")))
                    try stream.validate(); precondition(stream.parts.count >= 2)
                    TTSAPIClient.fixture = stream; TTSStorage.partsRoot = streamRoot
                    let row = TTSRendition(id: stream.id, voiceId: stream.voiceId, status: stream.status, bookId: stream.bookId, chapterId: stream.chapterId, bookTitle: stream.bookTitle, title: stream.title, position: stream.position, contentRevision: stream.contentRevision, completedChunks: stream.completedChunks, totalChunks: stream.totalChunks, error: nil, manifestURL: nil)
                    let record = TTSDownloadRecord(id: stream.id, rendition: row, state: "waiting", backendURL: "https://example.invalid")
                    player.playAvailable(record); player.pause()
                    try await wait { player.isSpeaking && !player.isBuffering }
                    let secondTime = stream.parts[1].start + min(0.3, stream.parts[1].audioDuration / 2)
                    player.seek(to: secondTime)
                    try await wait { !player.isBuffering }
                    precondition(abs(player.elapsed - secondTime) < 0.15, "Part-local clocks must map onto the chapter clock")
                    precondition(player.currentWord == stream.word(at: player.elapsed))
                    player.seek(to: 0.3)
                    try await wait { !player.isBuffering }
                    precondition(abs(player.elapsed - 0.3) < 0.15, "Backward seeking must reopen the correct cached part")
                    player.stop()
                    try await Task.sleep(for: .milliseconds(200))
                    precondition(!player.isSpeaking && player.manifest == nil && player.currentWord == nil)
                    print("PASS: live verified FLAC parts play in AVPlayer, cross-part seeks use the chapter clock, backward seeks and stop stay correct")
                }
                exit(0)
            } catch { print("FAIL: \(error)"); exit(1) }
        }
        RunLoop.main.run()
    }
    @MainActor static func wait(_ ready: () -> Bool) async throws {
        for _ in 0..<100 { if ready() { return }; try await Task.sleep(for: .milliseconds(100)) }
        throw TTSError.request("Player did not finish loading or seeking")
    }
}
