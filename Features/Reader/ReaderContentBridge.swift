import Combine
import Foundation
import WebKit

struct TTSSourcePosition: Equatable {
    let paragraphIndex: Int
    let offset: Int
}

@MainActor
final class ReaderContentBridge: ObservableObject {
    weak var webView: WKWebView?
    @Published private(set) var isReady = false
    @Published private(set) var isFollowing = true
    let paragraphScrollPublisher = PassthroughSubject<Int, Never>()
    let wordTapPublisher = PassthroughSubject<TTSSourcePosition, Never>()
    private var activeWord: TTSWordTiming?
    private var activeIndex: Int?
    private var speechMode = false

    func setWebView(_ webView: WKWebView) { self.webView = webView; isReady = false }
    func contentDidChange() { isReady = false }
    func contentDidFinishLoad() {
        isReady = true
        setSpeechMode(speechMode)
        if let activeWord { setActiveWord(activeWord) }
        else if let activeIndex { setActiveIndex(activeIndex) }
    }
    func receive(_ name: String, body: Any) -> Bool {
        if name == "ttsWordTap", let value = body as? [String: Any],
           let paragraph = value["paragraphIndex"] as? Int, let offset = value["offset"] as? Int {
            wordTapPublisher.send(.init(paragraphIndex: paragraph, offset: offset)); return true
        }
        if name == "ttsFollowChanged", let following = body as? Bool { isFollowing = following; return true }
        return false
    }
    func onParagraphScroll(_ index: Int) { paragraphScrollPublisher.send(index) }
    func scrollToParagraph(_ index: Int) { evaluate("window.scrollToParagraph && window.scrollToParagraph(\(index))") }
    func prepareTTS() { evaluate("window.prepareTTS && window.prepareTTS()") }
    func fetchTTSBlocks() async -> [String] {
        guard isReady, let webView else { return [] }
        return (try? await webView.evaluateJavaScript("window.getTTSBlocks && window.getTTSBlocks()")) as? [String] ?? []
    }
    func setSpeechMode(_ active: Bool) { speechMode = active; evaluate("window.setTTSSpeechMode && window.setTTSSpeechMode(\(active ? "true" : "false"))") }
    func setActiveWord(_ word: TTSWordTiming?) {
        activeWord = word
        guard isReady, let word, let data = try? JSONEncoder().encode(word), let json = String(data: data, encoding: .utf8) else { return }
        evaluate("window.setTTSActiveWord && window.setTTSActiveWord(\(json))")
    }
    func resumeFollowing() {
        isFollowing = true
        evaluate("window.resumeTTSFollow && window.resumeTTSFollow()")
    }
    func setActiveIndex(_ index: Int?) {
        activeIndex = index
        guard isReady, let index else { return }
        evaluate("window.setTTSActiveIndex && window.setTTSActiveIndex(\(index))")
    }
    func clearActive() {
        activeIndex = nil; activeWord = nil
        evaluate("window.clearTTSActive && window.clearTTSActive()")
    }
    private func evaluate(_ script: String) { guard isReady else { return }; webView?.evaluateJavaScript(script) }
}
