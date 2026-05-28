import Combine
import Foundation
import WebKit

@MainActor
final class ReaderContentBridge: ObservableObject {
    weak var webView: WKWebView?
    @Published private(set) var isReady = false

    func setWebView(_ webView: WKWebView) {
        self.webView = webView
    }

    func contentDidChange() {
        isReady = false
    }

    private var currentActiveIndex: Int? = nil

    func contentDidFinishLoad() {
        isReady = true
        prepareTTS()
        if let currentActiveIndex {
            setActiveIndex(currentActiveIndex)
        }
    }

    func prepareTTS() {
        evaluate("window.prepareTTS && window.prepareTTS()")
    }

    func fetchTTSBlocks() async -> [String] {
        guard isReady else { return [] }
        let result = await evaluateAsync("window.getTTSBlocks && window.getTTSBlocks()")
        return result as? [String] ?? []
    }

    func setActiveIndex(_ index: Int?) {
        self.currentActiveIndex = index
        guard isReady else { return }
        guard let index else {
            clearActive()
            return
        }
        evaluate("window.setTTSActiveIndex && window.setTTSActiveIndex(\(index))")
    }

    func clearActive() {
        self.currentActiveIndex = nil
        evaluate("window.clearTTSActive && window.clearTTSActive()")
    }

    private func evaluate(_ script: String) {
        webView?.evaluateJavaScript(script)
    }

    private func evaluateAsync(_ script: String) async -> Any? {
        await withCheckedContinuation { continuation in
            webView?.evaluateJavaScript(script) { result, _ in
                continuation.resume(returning: result)
            }
        }
    }
}
