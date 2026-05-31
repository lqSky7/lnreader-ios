import Combine
import Foundation
import WebKit

@MainActor
final class ReaderContentBridge: ObservableObject {
    weak var webView: WKWebView?
    @Published private(set) var isReady = false
    let paragraphScrollPublisher = PassthroughSubject<Int, Never>()

    func setWebView(_ webView: WKWebView) {
        print("🔊 [ReaderContentBridge] setWebView called, resetting isReady to false")
        self.webView = webView
        self.isReady = false
    }

    func contentDidChange() {
        print("🔊 [ReaderContentBridge] contentDidChange called, resetting isReady to false")
        isReady = false
    }

    private var currentActiveIndex: Int? = nil

    func contentDidFinishLoad() {
        print("🔊 [ReaderContentBridge] contentDidFinishLoad called, setting isReady to true")
        isReady = true
        if let currentActiveIndex {
            setActiveIndex(currentActiveIndex)
        }
    }

    func onParagraphScroll(_ index: Int) {
        paragraphScrollPublisher.send(index)
    }

    func scrollToParagraph(_ index: Int) {
        guard isReady else { return }
        evaluate("window.scrollToParagraph && window.scrollToParagraph(\(index))")
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
        print("🔊 [ReaderContentBridge] evaluateAsync called for script: \(script)")
        guard webView != nil else {
            print("⚠️ [ReaderContentBridge] webView is nil")
            return nil
        }
        
        print("🔊 [ReaderContentBridge] webView exists. Starting Task Group evaluate script…")
        let output = await withTaskGroup(of: Any?.self) { group in
            group.addTask { [weak self] in
                print("🔊 [ReaderContentBridge] Starting evaluation Task…")
                let task = Task { @MainActor [weak self] () -> Any? in
                    guard let webView = self?.webView else { return nil }
                    do {
                        let result = try await webView.evaluateJavaScript(script)
                        print("✅ [ReaderContentBridge] evaluateJavaScript success: \(result != nil)")
                        return result
                    } catch {
                        print("❌ [ReaderContentBridge] evaluateJavaScript error: \(error)")
                        return nil
                    }
                }
                return await task.value
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds timeout
                print("⚠️ [ReaderContentBridge] evaluateJavaScript timed out after 2 seconds!")
                return nil
            }
            let firstResult = await group.next()
            group.cancelAll()
            return firstResult ?? nil
        }
        print("🔊 [ReaderContentBridge] evaluateAsync finished. Result exists: \(output != nil)")
        return output
    }
}
