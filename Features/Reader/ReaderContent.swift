// ReaderContent.swift
// WKWebView-based HTML rendering with configurable reader styles.

import SwiftUI
import WebKit

#if os(iOS)
    struct ReaderContent: UIViewRepresentable {
        let htmlContent: String
        let fontSize: Double
        let lineHeight: Double
        let fontFamily: String
        let horizontalPadding: Double
        let backgroundColorHex: String
        let textColorHex: String
        let bridge: ReaderContentBridge
        let baseURL: URL?
        var onTap: (() -> Void)? = nil
        var onParagraphTap: ((Int) -> Void)? = nil

        class Coordinator: NSObject, UIGestureRecognizerDelegate, WKNavigationDelegate, WKScriptMessageHandler {
            var onTap: (() -> Void)?
            var onParagraphTap: ((Int) -> Void)?
            weak var bridge: ReaderContentBridge?
            
            var loadedHtmlContent: String?
            var loadedFontSize: Double?
            var loadedLineHeight: Double?
            var loadedFontFamily: String?
            var loadedHorizontalPadding: Double?
            var loadedBackgroundColorHex: String?
            var loadedTextColorHex: String?

            init(onTap: (() -> Void)?, bridge: ReaderContentBridge?) {
                self.onTap = onTap
                self.bridge = bridge
            }

            @objc func handleTap(_ gesture: UITapGestureRecognizer) {
                guard let webView = gesture.view as? WKWebView else { return }
                webView.evaluateJavaScript("window.getSelection().toString()") { [weak self] (result, error) in
                    guard let self = self else { return }
                    if let selection = result as? String, !selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        return
                    }
                    DispatchQueue.main.async {
                        if gesture.state == .ended {
                            self.onTap?()
                        }
                    }
                }
            }

            func gestureRecognizer(
                _ gestureRecognizer: UIGestureRecognizer,
                shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
            ) -> Bool {
                return true
            }

            func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
                bridge?.contentDidFinishLoad()
            }

            func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
                if message.name == "tapParagraph",
                   let body = message.body as? String,
                   let index = Int(body) {
                    DispatchQueue.main.async { [weak self] in
                        self?.onParagraphTap?(index)
                    }
                }
            }
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(onTap: onTap, bridge: bridge)
        }

        func makeUIView(context: Context) -> WKWebView {
            let config = WKWebViewConfiguration()
            let userContentController = WKUserContentController()
            let helper = ScriptMessageHandlerHelper(delegate: context.coordinator)
            userContentController.add(helper, name: "tapParagraph")
            config.userContentController = userContentController

            let webView = WKWebView(frame: .zero, configuration: config)
            webView.isOpaque = false
            webView.backgroundColor = .clear
            webView.scrollView.backgroundColor = .clear
            webView.scrollView.showsHorizontalScrollIndicator = false
            webView.scrollView.contentInsetAdjustmentBehavior = .never
            webView.navigationDelegate = context.coordinator
            bridge.setWebView(webView)

            let tapGesture = UITapGestureRecognizer(
                target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
            tapGesture.delegate = context.coordinator
            webView.addGestureRecognizer(tapGesture)

            return webView
        }

        func updateUIView(_ webView: WKWebView, context: Context) {
            context.coordinator.onTap = onTap
            context.coordinator.onParagraphTap = onParagraphTap
            context.coordinator.bridge = bridge
            
            let contentChanged = context.coordinator.loadedHtmlContent != htmlContent
            let styleChanged = context.coordinator.loadedFontSize != fontSize ||
                               context.coordinator.loadedLineHeight != lineHeight ||
                               context.coordinator.loadedFontFamily != fontFamily ||
                               context.coordinator.loadedHorizontalPadding != horizontalPadding ||
                               context.coordinator.loadedBackgroundColorHex != backgroundColorHex ||
                               context.coordinator.loadedTextColorHex != textColorHex
            
            if contentChanged || context.coordinator.loadedHtmlContent == nil {
                bridge.contentDidChange()
                let html = readerHTML(content: htmlContent)
                webView.loadHTMLString(html, baseURL: baseURL)
                
                context.coordinator.loadedHtmlContent = htmlContent
                context.coordinator.loadedFontSize = fontSize
                context.coordinator.loadedLineHeight = lineHeight
                context.coordinator.loadedFontFamily = fontFamily
                context.coordinator.loadedHorizontalPadding = horizontalPadding
                context.coordinator.loadedBackgroundColorHex = backgroundColorHex
                context.coordinator.loadedTextColorHex = textColorHex
            } else if styleChanged {
                let resolvedBg = backgroundColorHex.isEmpty ? "" : backgroundColorHex
                let resolvedText = textColorHex.isEmpty ? "" : textColorHex
                
                let js = """
                document.body.style.fontFamily = "'\(fontFamily)', 'Georgia', serif";
                document.body.style.fontSize = '\(fontSize)px';
                document.body.style.lineHeight = '\(lineHeight)';
                document.body.style.paddingLeft = '\(horizontalPadding)px';
                document.body.style.paddingRight = '\(horizontalPadding)px';
                document.body.style.background = '\(resolvedBg)';
                document.body.style.color = '\(resolvedText)';
                """
                webView.evaluateJavaScript(js)
                
                context.coordinator.loadedFontSize = fontSize
                context.coordinator.loadedLineHeight = lineHeight
                context.coordinator.loadedFontFamily = fontFamily
                context.coordinator.loadedHorizontalPadding = horizontalPadding
                context.coordinator.loadedBackgroundColorHex = backgroundColorHex
                context.coordinator.loadedTextColorHex = textColorHex
            }
        }
    }
#else
    struct ReaderContent: NSViewRepresentable {
        let htmlContent: String
        let fontSize: Double
        let lineHeight: Double
        let fontFamily: String
        let horizontalPadding: Double
        let backgroundColorHex: String
        let textColorHex: String
        let bridge: ReaderContentBridge
        let baseURL: URL?
        var onTap: (() -> Void)? = nil
        var onParagraphTap: ((Int) -> Void)? = nil

        class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
            var loadedHtmlContent: String?
            var loadedFontSize: Double?
            var loadedLineHeight: Double?
            var loadedFontFamily: String?
            var loadedHorizontalPadding: Double?
            var loadedBackgroundColorHex: String?
            var loadedTextColorHex: String?
            weak var bridge: ReaderContentBridge?
            var onParagraphTap: ((Int) -> Void)?

            func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
                bridge?.contentDidFinishLoad()
            }

            func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
                if message.name == "tapParagraph",
                   let body = message.body as? String,
                   let index = Int(body) {
                    DispatchQueue.main.async { [weak self] in
                        self?.onParagraphTap?(index)
                    }
                }
            }
        }

        func makeCoordinator() -> Coordinator {
            let coordinator = Coordinator()
            coordinator.bridge = bridge
            return coordinator
        }

        func makeNSView(context: Context) -> WKWebView {
            let config = WKWebViewConfiguration()
            let userContentController = WKUserContentController()
            let helper = ScriptMessageHandlerHelper(delegate: context.coordinator)
            userContentController.add(helper, name: "tapParagraph")
            config.userContentController = userContentController

            let webView = WKWebView(frame: .zero, configuration: config)
            webView.navigationDelegate = context.coordinator
            bridge.setWebView(webView)
            return webView
        }

        func updateNSView(_ webView: WKWebView, context: Context) {
            context.coordinator.bridge = bridge
            context.coordinator.onParagraphTap = onParagraphTap
            let contentChanged = context.coordinator.loadedHtmlContent != htmlContent
            let styleChanged = context.coordinator.loadedFontSize != fontSize ||
                               context.coordinator.loadedLineHeight != lineHeight ||
                               context.coordinator.loadedFontFamily != fontFamily ||
                               context.coordinator.loadedHorizontalPadding != horizontalPadding ||
                               context.coordinator.loadedBackgroundColorHex != backgroundColorHex ||
                               context.coordinator.loadedTextColorHex != textColorHex
            
            if contentChanged || context.coordinator.loadedHtmlContent == nil {
                bridge.contentDidChange()
                let html = readerHTML(content: htmlContent)
                webView.loadHTMLString(html, baseURL: baseURL)
                
                context.coordinator.loadedHtmlContent = htmlContent
                context.coordinator.loadedFontSize = fontSize
                context.coordinator.loadedLineHeight = lineHeight
                context.coordinator.loadedFontFamily = fontFamily
                context.coordinator.loadedHorizontalPadding = horizontalPadding
                context.coordinator.loadedBackgroundColorHex = backgroundColorHex
                context.coordinator.loadedTextColorHex = textColorHex
            } else if styleChanged {
                let resolvedBg = backgroundColorHex.isEmpty ? "" : backgroundColorHex
                let resolvedText = textColorHex.isEmpty ? "" : textColorHex
                
                let js = """
                document.body.style.fontFamily = "'\(fontFamily)', 'Georgia', serif";
                document.body.style.fontSize = '\(fontSize)px';
                document.body.style.lineHeight = '\(lineHeight)';
                document.body.style.paddingLeft = '\(horizontalPadding)px';
                document.body.style.paddingRight = '\(horizontalPadding)px';
                document.body.style.background = '\(resolvedBg)';
                document.body.style.color = '\(resolvedText)';
                """
                webView.evaluateJavaScript(js)
                
                context.coordinator.loadedFontSize = fontSize
                context.coordinator.loadedLineHeight = lineHeight
                context.coordinator.loadedFontFamily = fontFamily
                context.coordinator.loadedHorizontalPadding = horizontalPadding
                context.coordinator.loadedBackgroundColorHex = backgroundColorHex
                context.coordinator.loadedTextColorHex = textColorHex
            }
        }
    }
#endif

// MARK: - HTML Template

extension ReaderContent {
    func readerHTML(content: String) -> String {
        let resolvedBg = backgroundColorHex.isEmpty ? "transparent" : backgroundColorHex
        let resolvedText = textColorHex.isEmpty ? "#2c2c2e" : textColorHex

        let darkMediaQuery =
            textColorHex.isEmpty
            ? """
            @media (prefers-color-scheme: dark) {
                body { color: #e5e5e7; }
            }
            """ : ""

        return """
            <!DOCTYPE html>
            <html>
            <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <link href="https://fonts.cdnfonts.com/css/open-dyslexic" rel="stylesheet">
            <style>
            :root {
                color-scheme: light dark;
            }
            * { margin: 0; padding: 0; box-sizing: border-box; }
            body {
                font-family: '\(fontFamily)', 'Georgia', serif;
                font-size: \(fontSize)px;
                line-height: \(lineHeight);
                padding: 70px \(horizontalPadding)px 90px;
                color: \(resolvedText);
                background: \(resolvedBg);
                -webkit-font-smoothing: antialiased;
                word-wrap: break-word;
                overflow-wrap: break-word;
                position: relative;
            }
            \(darkMediaQuery)
            p { margin-bottom: 1em; text-align: justify; }
            p:empty { display: none; }
            img { max-width: 100%; height: auto; border-radius: 8px; margin: 1em 0; }
            h1, h2, h3, h4, h5, h6 {
                margin: 1.4em 0 0.6em;
                line-height: 1.3;
            }
            h1 { font-size: 1.5em; }
            h2 { font-size: 1.3em; }
            h3 { font-size: 1.15em; }
            a { color: #d4a574; text-decoration: none; }
            blockquote {
                border-left: 3px solid #d4a574;
                padding-left: 1em;
                margin: 1em 0;
                color: #8e8e93;
            }
            hr { border: none; border-top: 1px solid #3a3a3c; margin: 2em 0; }
            em { font-style: italic; }
            strong { font-weight: bold; }
            .tts-active {
                background: rgba(212, 165, 116, 0.18);
                border-radius: 8px;
                box-shadow: inset 0 0 0 1px rgba(212, 165, 116, 0.28);
                padding: 0.05em 0.1em;
            }
            #tts-dot {
                position: absolute;
                width: 6px;
                height: 6px;
                border-radius: 999px;
                background: #d4a574;
                box-shadow: 0 0 8px rgba(212, 165, 116, 0.8);
                opacity: 0;
                pointer-events: none;
                transition: transform 0.2s ease, opacity 0.2s ease;
            }
            </style>
            </head>
            <body>\(content)
            <div id="tts-dot"></div>
            <script>
            (function() {
                function collectBlocks() {
                    var nodes = Array.from(document.querySelectorAll("p, h1, h2, h3, h4, h5, h6, li"));
                    var texts = [];
                    nodes.forEach(function(node) {
                        var text = node.innerText.replace(/\\s+/g, " ").trim();
                        if (text.length === 0) {
                            node.setAttribute("data-tts-index", "-1");
                            return;
                        }
                        var index = texts.length;
                        node.setAttribute("data-tts-index", String(index));
                        
                        // Paragraph click handler
                        node.onclick = function() {
                            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.tapParagraph) {
                                window.webkit.messageHandlers.tapParagraph.postMessage(String(index));
                            }
                        };
                        
                        texts.push(text);
                    });
                    window.__ttsBlocks = texts;
                }

                function ensureDot() {
                    var dot = document.getElementById("tts-dot");
                    if (!dot) {
                        dot = document.createElement("div");
                        dot.id = "tts-dot";
                        document.body.appendChild(dot);
                    }
                    return dot;
                }

                window.prepareTTS = function() {
                    collectBlocks();
                    ensureDot();
                };

                window.getTTSBlocks = function() {
                    collectBlocks();
                    return window.__ttsBlocks || [];
                };

                window.setTTSActiveIndex = function(index) {
                    collectBlocks();
                    var active = document.querySelector(".tts-active");
                    if (active) {
                        active.classList.remove("tts-active");
                    }
                    var target = document.querySelector('[data-tts-index="' + index + '"]');
                    var dot = ensureDot();
                    if (!target) {
                        if (dot) { dot.style.opacity = 0; }
                        return;
                    }
                    target.classList.add("tts-active");
                    if (dot) {
                        var rect = target.getBoundingClientRect();
                        var x = rect.left + window.scrollX - 10;
                        var y = rect.top + window.scrollY + 8;
                        if (x < 6) { x = 6; }
                        dot.style.transform = "translate(" + x + "px, " + y + "px)";
                        dot.style.opacity = 1;
                    }
                };

                window.clearTTSActive = function() {
                    var active = document.querySelector(".tts-active");
                    if (active) {
                        active.classList.remove("tts-active");
                    }
                    var dot = document.getElementById("tts-dot");
                    if (dot) {
                        dot.style.opacity = 0;
                    }
                };

                document.addEventListener("DOMContentLoaded", function() {
                    window.prepareTTS();
                });
            })();
            </script>
            </body>
            </html>
            """
    }
}

class ScriptMessageHandlerHelper: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?
    
    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}
