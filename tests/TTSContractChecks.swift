// Run on macOS with scripts/check-tts-contracts.sh
import AppKit
import Foundation
import WebKit
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
                var cloned = data
                cloned["modelID"] = "Qwen/Qwen3-TTS-12Hz-1.7B-Base"
                cloned["voiceId"] = "custom-fixture"
                try JSONDecoder().decode(TTSManifest.self, from: JSONSerialization.data(withJSONObject: cloned)).validate()
                precondition(manifest.time(paragraph: 0, offset: 16) == 1.2, "Number expansion must seek to its first spoken word")
                precondition(manifest.word(at: 0.7)?.sourceStart == 9, "Use the media clock with UTF-16 offsets after emoji")
                precondition(manifest.word(at: 1.7)?.sourceStart == 15)
                precondition(manifest.word(at: 0.45) == nil, "Silence between words must clear highlighting")
                precondition(manifest.word(at: 2.5) == nil, "The last word must not stick through chapter trailing silence")
                precondition(manifest.word(at: -1) == nil && manifest.word(at: .nan) == nil)
                var corrupt = data
                corrupt["words"] = [["paragraphIndex": 0, "sourceStart": 500, "sourceEnd": 510, "start": 0.0, "end": 1.0]]
                let invalid = try JSONDecoder().decode(TTSManifest.self, from: JSONSerialization.data(withJSONObject: corrupt))
                do { try invalid.validate(); fatalError("Corrupt source offsets must be rejected") } catch TTSError.invalidManifest { }
                let extractor = TTSChapterTextExtractor()
                let blocks = try await extractor.extract("<article><p> Hello <em>🌟 world</em> <a role=\"doc-noteref\" href=\"#fn1\">1</a> 42.</p><p>Second<br>line.</p></article>")
                guard blocks == ["Hello 🌟 world 42.", "Second line."] else { fatalError(String(describing: blocks)) }
                let citations = try await extractor.extract("<p>Read this sentence.<sup><a href='notes.xhtml#note-10'>10</a></sup></p><p>Another<a epub:type='noteref' href='notes.xhtml#x'>11</a> sentence with 10 books.</p><aside epub:type='footnote'><p>Annotation body.</p></aside>")
                precondition(citations == ["Read this sentence.", "Another sentence with 10 books."], "EPUB references and annotation bodies must be excluded while real quantities stay")
                let fallback = try await extractor.extract("<div>Plain <em>chapter</em><br>with breaks.</div>")
                guard fallback == ["Plain chapter with breaks."] else { fatalError(String(describing: fallback)) }
                try await ReaderInteractionChecks().run()
                print("PASS: media-clock word lookup, number expansion seeks, corrupt manifest rejection, real WKWebView UTF-16 extraction, notes, line breaks and plain div fallback")
                exit(0)
            } catch { print("FAIL: \(error)"); exit(1) }
        }
        RunLoop.main.run()
    }
}

@MainActor final class ReaderInteractionChecks: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    var continuation: CheckedContinuation<Void, Error>?
    var messages: [String] = []
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) { messages.append(message.name) }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { continuation?.resume(); continuation = nil }
    func run() async throws {
        let config = WKWebViewConfiguration()
        for name in ["toggleControls", "ttsWordTap", "ttsFollowChanged"] { config.userContentController.add(self, name: name) }
        defer { config.userContentController.removeAllScriptMessageHandlers() }
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 393, height: 780), configuration: config)
        webView.navigationDelegate = self
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            webView.loadHTMLString("<style>" + ReaderTTSJavaScript.highlightStyle + "</style><p style='margin:40px;font-size:24px'>Read this book.</p>", baseURL: nil)
        }
        _ = try await webView.evaluateJavaScript(ReaderTTSJavaScript.mapping + ReaderTTSJavaScript.interaction + "window.ttsExtractBlocks(); window.setTTSSpeechMode(true); window.setTTSControlsVisible(false);")
        _ = try await webView.evaluateJavaScript("window.setTTSActiveWord({paragraphIndex:0,sourceStart:5,sourceEnd:9,start:0.5,end:0.9});")
        let wordHighlight = try await webView.evaluateJavaScript("({text:CSS.highlights.get('tts-word').values().next().value.toString(),count:CSS.highlights.get('tts-word').size,paragraphBackground:getComputedStyle(document.querySelector('p')).backgroundColor,paragraphShadow:getComputedStyle(document.querySelector('p')).boxShadow})") as! [String: Any]
        precondition(wordHighlight["text"] as? String == "this" && wordHighlight["count"] as? Int == 1, "Only the current word should be highlighted")
        precondition(wordHighlight["paragraphBackground"] as? String == "rgba(0, 0, 0, 0)" && wordHighlight["paragraphShadow"] as? String == "none", "The active paragraph must not have a highlight box")
        _ = try await webView.evaluateJavaScript("window.setTTSActiveWord({paragraphIndex:0,sourceStart:10,sourceEnd:14,start:1,end:1.4});")
        let movedWord = try await webView.evaluateJavaScript("CSS.highlights.get('tts-word').values().next().value.toString()") as? String
        precondition(movedWord == "book", "Advancing narration must replace the previous word highlight")
        print("PASS: exactly one spoken-word highlight, media-clock updates, and no paragraph background in real WKWebView")
        let bridge = ReaderContentBridge()
        bridge.setWebView(webView); bridge.contentDidFinishLoad(); bridge.setSpeechMode(true)
        bridge.setActiveWord(.init(paragraphIndex: 0, sourceStart: 5, sourceEnd: 9, start: 0.5, end: 0.9))
        bridge.setActiveWord(nil); bridge.resumeFollowing(); bridge.setControlsVisible(true)
        let cleared = try await webView.evaluateJavaScript("!CSS.highlights.has('tts-word') && window.__ttsWord === null && !document.querySelector('.tts-active')") as? Bool
        precondition(cleared == true, "Clearing a timed gap must remove native and JS saved highlights; follow/focus cannot restore it")
        bridge.setActiveWord(.init(paragraphIndex: 0, sourceStart: 5, sourceEnd: 9, start: 0.5, end: 0.9))
        bridge.setActiveWord(.init(paragraphIndex: 99, sourceStart: 0, sourceEnd: 4, start: 1, end: 2))
        let invalidCleared = try await webView.evaluateJavaScript("!CSS.highlights.has('tts-word')") as? Bool
        precondition(invalidCleared == true, "An invalid source position must clear an older highlight")
        bridge.setSpeechMode(false)
        bridge.setActiveWord(.init(paragraphIndex: 0, sourceStart: 5, sourceEnd: 9, start: 0.5, end: 0.9))
        let stoppedCleared = try await webView.evaluateJavaScript("!CSS.highlights.has('tts-word') && window.__ttsWord === null") as? Bool
        precondition(stoppedCleared == true, "Late word updates after stopping must not paint highlights")
        bridge.setSpeechMode(true); bridge.setControlsVisible(false)
        print("PASS: bridge clears silence, invalid mappings and stop; follow/focus cannot resurrect highlights")
        let hidden = try await webView.evaluateJavaScript("window.__ttsSpeechMode && !window.__ttsControlsVisible && document.body.style.getPropertyValue('--tts-bottom') === '32px'") as? Bool
        precondition(hidden == true, "Focused listening must retain speech mode and remove control insets")
        let tap = "var p=document.querySelector('p'); p.dispatchEvent(new PointerEvent('pointerdown',{isPrimary:true,clientX:55,clientY:55,bubbles:true})); p.dispatchEvent(new PointerEvent('pointerup',{isPrimary:true,clientX:55,clientY:55,bubbles:true}));"
        _ = try await webView.evaluateJavaScript(tap)
        try await Task.sleep(for: .milliseconds(400))
        precondition(messages.filter { $0 == "toggleControls" }.count == 1, "A listening single tap must toggle focus")
        _ = try await webView.evaluateJavaScript(tap + tap + "var r=document.createRange(); r.setStart(p.firstChild,0); r.setEnd(p.firstChild,4); var rect=r.getBoundingClientRect(); p.dispatchEvent(new MouseEvent('dblclick',{clientX:rect.x+rect.width/2,clientY:rect.y+rect.height/2,bubbles:true,cancelable:true}));")
        try await Task.sleep(for: .milliseconds(400))
        precondition(messages.filter { $0 == "toggleControls" }.count == 1, "Double tap seeking must not toggle focus")
        precondition(messages.filter { $0 == "ttsWordTap" }.count == 1, "Double tap must still seek the tapped word")
        _ = try await webView.evaluateJavaScript("window.ttsSetFollowing(false); window.setTTSControlsVisible(true);")
        let restored = try await webView.evaluateJavaScript("window.__ttsControlsVisible && !window.__ttsFollowing && document.body.style.getPropertyValue('--tts-bottom') === '260px'") as? Bool
        precondition(restored == true, "Showing controls must preserve a manually detached reading position")
        print("PASS: listening focus toggle, control insets, double-tap word seek, and detached follow state in real WKWebView")
    }
}
