// Run on macOS with scripts/check-tts-contracts.sh
import AppKit
import Foundation
struct ChapterDisplay { let path: String; let name: String; let position: Int }
@main struct Check {
    @MainActor static func main() {
        _ = NSApplication.shared
        Task { @MainActor in
            do {
                let data: [String: Any] = [
                    "schema": 1, "id": String(repeating: "a", count: 64), "bookId": "b", "chapterId": "c", "bookTitle": "Book", "title": "Chapter", "position": 0,
                    "contentRevision": "r", "voiceId": "qwen-ryan", "voiceName": "Ryan", "modelID": "Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice", "modelRevision": "pinned", "pipeline": "test",
                    "duration": 3.0, "sampleRate": 24000, "audioBytes": 10, "audioSHA256": String(repeating: "b", count: 64), "blocks": ["Hello 🌟 world 42."],
                    "words": [
                        ["paragraphIndex": 0, "sourceStart": 0, "sourceEnd": 5, "start": 0.0, "end": 0.4],
                        ["paragraphIndex": 0, "sourceStart": 9, "sourceEnd": 14, "start": 0.5, "end": 1.0],
                        ["paragraphIndex": 0, "sourceStart": 15, "sourceEnd": 17, "start": 1.2, "end": 1.4],
                        ["paragraphIndex": 0, "sourceStart": 15, "sourceEnd": 17, "start": 1.5, "end": 1.8]
                    ]
                ]
                let manifest = try JSONDecoder().decode(TTSManifest.self, from: JSONSerialization.data(withJSONObject: data))
                try manifest.validate()
                precondition(manifest.time(paragraph: 0, offset: 16) == 1.2, "Number expansion must seek to its first spoken word")
                precondition(manifest.word(at: 0.7)?.sourceStart == 9, "Use the media clock with UTF-16 offsets after emoji")
                precondition(manifest.word(at: 1.7)?.sourceStart == 15)
                var corrupt = data
                corrupt["words"] = [["paragraphIndex": 0, "sourceStart": 500, "sourceEnd": 510, "start": 0.0, "end": 1.0]]
                let invalid = try JSONDecoder().decode(TTSManifest.self, from: JSONSerialization.data(withJSONObject: corrupt))
                do { try invalid.validate(); fatalError("Corrupt source offsets must be rejected") } catch TTSError.invalidManifest { }
                let extractor = TTSChapterTextExtractor()
                let blocks = try await extractor.extract("<article><p> Hello <em>🌟 world</em> <a role=\"doc-noteref\" href=\"#fn1\">1</a> 42.</p><p>Second<br>line.</p></article>")
                guard blocks == ["Hello 🌟 world 42.", "Second line."] else { fatalError(String(describing: blocks)) }
                let fallback = try await extractor.extract("<div>Plain <em>chapter</em><br>with breaks.</div>")
                guard fallback == ["Plain chapter with breaks."] else { fatalError(String(describing: fallback)) }
                print("PASS: media-clock word lookup, number expansion seeks, corrupt manifest rejection, real WKWebView UTF-16 extraction, notes, line breaks and plain div fallback")
                exit(0)
            } catch { print("FAIL: \(error)"); exit(1) }
        }
        RunLoop.main.run()
    }
}
