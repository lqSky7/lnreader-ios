import CryptoKit
import Foundation
import WebKit

enum TTSBookIdentity {
    static func make(pluginId: String, novelPath: String) -> String {
        SHA256.hash(data: Data((pluginId + "\u{0}" + novelPath).utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func html(blocks: [String]) -> String {
        blocks.map { text in "<p>" + text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;") + "</p>" }.joined(separator: "\n")
    }
}

struct TTSChapterChoice: Identifiable, Sendable {
    var id: String { path }
    let path: String
    let title: String
    let position: Int
    init(path: String, title: String, position: Int) { self.path = path; self.title = title; self.position = position }
    init(_ chapter: ChapterDisplay) { self.init(path: chapter.path, title: chapter.name, position: chapter.position) }
}

/// Uses the same DOM normalization as the reader, including UTF-16 source positions.
@MainActor
final class TTSChapterTextExtractor: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<[String], Error>?
    private var webView: WKWebView?
    private var timeout: Task<Void, Never>?
    func extract(_ html: String) async throws -> [String] {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let config = WKWebViewConfiguration()
                config.websiteDataStore = .nonPersistent()
                config.defaultWebpagePreferences.allowsContentJavaScript = false
                let webView = WKWebView(frame: .zero, configuration: config)
                self.webView = webView; webView.navigationDelegate = self
                webView.loadHTMLString(html, baseURL: nil)
                timeout = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(20))
                    if !Task.isCancelled { self?.finish(.failure(TTSError.request("Chapter text extraction timed out."))) }
                }
            }
        } onCancel: { Task { @MainActor [weak self] in self?.finish(.failure(CancellationError())) } }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task {
            do {
                let result = try await webView.evaluateJavaScript(ReaderTTSJavaScript.mapping + "\nwindow.ttsExtractBlocks();")
                guard let blocks = result as? [String], !blocks.isEmpty else { throw TTSError.request("No readable chapter text was found.") }
                finish(.success(blocks))
            } catch { finish(.failure(error)) }
        }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(.failure(error)) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(.failure(error)) }
    private func finish(_ result: Result<[String], Error>) {
        guard let continuation else { return }; self.continuation = nil; timeout?.cancel(); timeout = nil
        webView?.stopLoading(); webView?.navigationDelegate = nil; webView = nil; continuation.resume(with: result)
    }
}
