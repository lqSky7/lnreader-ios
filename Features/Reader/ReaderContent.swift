// ReaderContent.swift
// WKWebView-based HTML rendering with configurable reader styles.

import SwiftUI
import WebKit

#if os(iOS)
    struct ReaderContent: UIViewRepresentable, Equatable {
        let htmlContent: String
        let fontSize: Double
        let lineHeight: Double
        let fontFamily: String
        let horizontalPadding: Double
        let verticalPadding: Double
        let backgroundColorHex: String
        let textColorHex: String
        let bionicReading: Bool
        let lineFocusEnabled: Bool
        let lineFocusLines: Int
        let lineFocusDulling: String
        let showControls: Bool
        let bridge: ReaderContentBridge
        let baseURL: URL?
        let characterSpacing: Double
        let wordSpacing: Double
        let grainIntensity: Double
        let commentsHtml: String
        let hasMoreComments: Bool
        var onTap: (() -> Void)? = nil
        var onParagraphTap: ((Int) -> Void)? = nil
        var onLoadMoreComments: (() -> Void)? = nil
        var onLikeComment: ((String) -> Void)? = nil
        var onDislikeComment: ((String) -> Void)? = nil

        class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
            var parent: ReaderContent?
            var onTap: (() -> Void)?
            var onParagraphTap: ((Int) -> Void)?
            weak var bridge: ReaderContentBridge?
            
            var loadedHtmlContent: String?
            var loadedFontSize: Double?
            var loadedLineHeight: Double?
            var loadedFontFamily: String?
            var loadedHorizontalPadding: Double?
            var loadedVerticalPadding: Double?
            var loadedBackgroundColorHex: String?
            var loadedTextColorHex: String?
            var loadedBionicReading: Bool?
            var loadedLineFocusEnabled: Bool?
            var loadedLineFocusLines: Int?
            var loadedLineFocusDulling: String?
            var loadedShowControls: Bool?
            var loadedCharacterSpacing: Double?
            var loadedWordSpacing: Double?
            var loadedGrainIntensity: Double?
            var loadedCommentsHtml: String?
            var loadedHasMoreComments: Bool?

            init(onTap: (() -> Void)?, bridge: ReaderContentBridge?) {
                self.onTap = onTap
                self.bridge = bridge
            }

            func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
                print("🔊 [ReaderContent] didFinish navigation.")
                bridge?.contentDidFinishLoad()
            }

            func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
                if message.name == "tapParagraph",
                   let body = message.body as? String,
                   let index = Int(body) {
                    DispatchQueue.main.async { [weak self] in
                        self?.onParagraphTap?(index)
                    }
                } else if message.name == "scrollParagraph",
                          let body = message.body as? String,
                          let index = Int(body) {
                    DispatchQueue.main.async { [weak self] in
                        self?.bridge?.onParagraphScroll(index)
                    }
                } else if message.name == "jsError",
                          let errorBody = message.body as? String {
                    print("❌ [JavaScript Error] \(errorBody)")
                } else if message.name == "toggleControls" {
                    DispatchQueue.main.async { [weak self] in
                        self?.onTap?()
                    }
                } else if message.name == "loadMoreComments" {
                    DispatchQueue.main.async { [weak self] in
                        self?.parent?.onLoadMoreComments?()
                    }
                } else if message.name == "likeComment",
                          let commentId = message.body as? String {
                    DispatchQueue.main.async { [weak self] in
                        self?.parent?.onLikeComment?(commentId)
                    }
                } else if message.name == "dislikeComment",
                          let commentId = message.body as? String {
                    DispatchQueue.main.async { [weak self] in
                        self?.parent?.onDislikeComment?(commentId)
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
            userContentController.add(helper, name: "scrollParagraph")
            userContentController.add(helper, name: "jsError")
            userContentController.add(helper, name: "toggleControls")
            userContentController.add(helper, name: "loadMoreComments")
            userContentController.add(helper, name: "likeComment")
            userContentController.add(helper, name: "dislikeComment")
            config.userContentController = userContentController

            let webView = WKWebView(frame: .zero, configuration: config)
            let uiColor = UIColor(hex: backgroundColorHex) ?? .systemBackground
            webView.isOpaque = true
            webView.backgroundColor = uiColor
            webView.scrollView.backgroundColor = uiColor
            webView.scrollView.showsHorizontalScrollIndicator = false
            webView.scrollView.contentInsetAdjustmentBehavior = .never
            webView.navigationDelegate = context.coordinator
            bridge.setWebView(webView)

            return webView
        }

        func updateUIView(_ webView: WKWebView, context: Context) {
            context.coordinator.parent = self
            context.coordinator.onTap = onTap
            context.coordinator.onParagraphTap = onParagraphTap
            context.coordinator.bridge = bridge
            
            #if os(iOS)
            let uiColor = UIColor(hex: backgroundColorHex) ?? .systemBackground
            webView.backgroundColor = uiColor
            webView.scrollView.backgroundColor = uiColor
            webView.scrollView.isScrollEnabled = true
            #endif
            
            let contentChanged = context.coordinator.loadedHtmlContent != htmlContent ||
                                 context.coordinator.loadedBionicReading != bionicReading
            let commentsChanged = context.coordinator.loadedCommentsHtml != commentsHtml
            let styleChanged = context.coordinator.loadedFontSize != fontSize ||
                               context.coordinator.loadedLineHeight != lineHeight ||
                               context.coordinator.loadedFontFamily != fontFamily ||
                               context.coordinator.loadedHorizontalPadding != horizontalPadding ||
                               context.coordinator.loadedVerticalPadding != verticalPadding ||
                               context.coordinator.loadedBackgroundColorHex != backgroundColorHex ||
                               context.coordinator.loadedTextColorHex != textColorHex ||
                               context.coordinator.loadedLineFocusEnabled != lineFocusEnabled ||
                               context.coordinator.loadedLineFocusLines != lineFocusLines ||
                               context.coordinator.loadedLineFocusDulling != lineFocusDulling ||
                               context.coordinator.loadedCharacterSpacing != characterSpacing ||
                               context.coordinator.loadedWordSpacing != wordSpacing ||
                               context.coordinator.loadedGrainIntensity != grainIntensity
            
            #if DEBUG
            print("🔊 [ReaderContent] updateUIView. loadedHtmlContentIsNil: \(context.coordinator.loadedHtmlContent == nil), contentChanged: \(contentChanged), styleChanged: \(styleChanged)")
            #endif
            if contentChanged {
                if context.coordinator.loadedHtmlContent != htmlContent {
                    #if DEBUG
                    print("🔊   -> htmlContent changed! (\(context.coordinator.loadedHtmlContent?.count ?? 0) chars -> \(htmlContent.count) chars)")
                    #endif
                }
                if context.coordinator.loadedBionicReading != bionicReading {
                    #if DEBUG
                    print("🔊   -> bionicReading changed! (\(String(describing: context.coordinator.loadedBionicReading)) -> \(bionicReading))")
                    #endif
                }
            }
            if styleChanged {
                #if DEBUG
                if context.coordinator.loadedFontSize != fontSize {
                    print("🔊   -> fontSize changed! (\(String(describing: context.coordinator.loadedFontSize)) -> \(fontSize))")
                }
                if context.coordinator.loadedLineHeight != lineHeight {
                    print("🔊   -> lineHeight changed! (\(String(describing: context.coordinator.loadedLineHeight)) -> \(lineHeight))")
                }
                if context.coordinator.loadedFontFamily != fontFamily {
                    print("🔊   -> fontFamily changed! (\(String(describing: context.coordinator.loadedFontFamily)) -> \(fontFamily))")
                }
                if context.coordinator.loadedHorizontalPadding != horizontalPadding {
                    print("🔊   -> horizontalPadding changed! (\(String(describing: context.coordinator.loadedHorizontalPadding)) -> \(horizontalPadding))")
                }
                if context.coordinator.loadedVerticalPadding != verticalPadding {
                    print("🔊   -> verticalPadding changed! (\(String(describing: context.coordinator.loadedVerticalPadding)) -> \(verticalPadding))")
                }
                if context.coordinator.loadedBackgroundColorHex != backgroundColorHex {
                    print("🔊   -> backgroundColorHex changed! (\(String(describing: context.coordinator.loadedBackgroundColorHex)) -> \(backgroundColorHex))")
                }
                if context.coordinator.loadedTextColorHex != textColorHex {
                    print("🔊   -> textColorHex changed! (\(String(describing: context.coordinator.loadedTextColorHex)) -> \(textColorHex))")
                }
                if context.coordinator.loadedLineFocusEnabled != lineFocusEnabled {
                    print("🔊   -> lineFocusEnabled changed! (\(String(describing: context.coordinator.loadedLineFocusEnabled)) -> \(lineFocusEnabled))")
                }
                if context.coordinator.loadedLineFocusLines != lineFocusLines {
                    print("🔊   -> lineFocusLines changed! (\(String(describing: context.coordinator.loadedLineFocusLines)) -> \(lineFocusLines))")
                }
                if context.coordinator.loadedLineFocusDulling != lineFocusDulling {
                    print("🔊   -> lineFocusDulling changed! (\(String(describing: context.coordinator.loadedLineFocusDulling)) -> \(lineFocusDulling))")
                }
                if context.coordinator.loadedCharacterSpacing != characterSpacing {
                    print("🔊   -> characterSpacing changed! (\(String(describing: context.coordinator.loadedCharacterSpacing)) -> \(characterSpacing))")
                }
                if context.coordinator.loadedWordSpacing != wordSpacing {
                    print("🔊   -> wordSpacing changed! (\(String(describing: context.coordinator.loadedWordSpacing)) -> \(wordSpacing))")
                }
                if context.coordinator.loadedGrainIntensity != grainIntensity {
                    print("🔊   -> grainIntensity changed! (\(String(describing: context.coordinator.loadedGrainIntensity)) -> \(grainIntensity))")
                }
                #endif
            }
            
            if contentChanged || context.coordinator.loadedHtmlContent == nil || (commentsChanged && context.coordinator.loadedCommentsHtml == nil) {
                bridge.contentDidChange()
                let html = readerHTML(content: htmlContent, comments: commentsHtml)
                webView.loadHTMLString(html, baseURL: baseURL)
                
                context.coordinator.loadedHtmlContent = htmlContent
                context.coordinator.loadedCommentsHtml = commentsHtml
                context.coordinator.loadedFontSize = fontSize
                context.coordinator.loadedLineHeight = lineHeight
                context.coordinator.loadedFontFamily = fontFamily
                context.coordinator.loadedHorizontalPadding = horizontalPadding
                context.coordinator.loadedVerticalPadding = verticalPadding
                context.coordinator.loadedBackgroundColorHex = backgroundColorHex
                context.coordinator.loadedTextColorHex = textColorHex
                context.coordinator.loadedBionicReading = bionicReading
                context.coordinator.loadedLineFocusEnabled = lineFocusEnabled
                context.coordinator.loadedLineFocusLines = lineFocusLines
                context.coordinator.loadedLineFocusDulling = lineFocusDulling
                context.coordinator.loadedShowControls = showControls
                context.coordinator.loadedCharacterSpacing = characterSpacing
                context.coordinator.loadedWordSpacing = wordSpacing
                context.coordinator.loadedGrainIntensity = grainIntensity
            } else if commentsChanged {
                context.coordinator.loadedCommentsHtml = commentsHtml
            } else if styleChanged {
                let resolvedBg = backgroundColorHex.isEmpty ? "" : backgroundColorHex
                let resolvedText = textColorHex.isEmpty ? "" : textColorHex
                
                let lineFocusOpacity = resolvedLineFocusOpacity(dulling: lineFocusDulling)
                let lineFocusHeight = resolvedLineFocusHeight(lines: lineFocusLines, fontSize: fontSize, lineHeight: lineHeight)
                let lineFocusDisplay = lineFocusEnabled ? "block" : "none"
                
                let topOffset = 70.0 + verticalPadding
                let bottomOffset = verticalPadding
                
                let js = """
                document.body.style.fontFamily = "'\(fontFamily)', 'Georgia', serif";
                document.body.style.fontSize = '\(fontSize)px';
                document.body.style.lineHeight = '\(lineHeight)';
                document.body.style.letterSpacing = '\(characterSpacing / 100.0)em';
                document.body.style.wordSpacing = '\(wordSpacing / 100.0)em';
                document.body.style.padding = '\(topOffset)px \(horizontalPadding)px \(bottomOffset)px';
                document.body.style.overflow = 'visible';
                document.body.style.height = 'auto';
                document.body.style.background = '\(resolvedBg)';
                document.body.style.color = '\(resolvedText)';
                
                var ruler = document.getElementById("line-focus-ruler");
                if (ruler) {
                    ruler.style.display = '\(lineFocusDisplay)';
                    ruler.style.height = '\(lineFocusHeight)px';
                    ruler.style.boxShadow = '0 0 0 9999px rgba(0, 0, 0, \(lineFocusOpacity))';
                }
                
                var grain = document.getElementById("paper-grain-overlay");
                if (grain) {
                    grain.style.opacity = '\(backgroundColorHex == "#1C1C1E" ? grainIntensity / 100.0 : 0.0)';
                }
                """
                webView.evaluateJavaScript(js)
                
                context.coordinator.loadedFontSize = fontSize
                context.coordinator.loadedLineHeight = lineHeight
                context.coordinator.loadedFontFamily = fontFamily
                context.coordinator.loadedHorizontalPadding = horizontalPadding
                context.coordinator.loadedVerticalPadding = verticalPadding
                context.coordinator.loadedBackgroundColorHex = backgroundColorHex
                context.coordinator.loadedTextColorHex = textColorHex
                context.coordinator.loadedLineFocusEnabled = lineFocusEnabled
                context.coordinator.loadedLineFocusLines = lineFocusLines
                context.coordinator.loadedLineFocusDulling = lineFocusDulling
                context.coordinator.loadedShowControls = showControls
                context.coordinator.loadedCharacterSpacing = characterSpacing
                context.coordinator.loadedWordSpacing = wordSpacing
                context.coordinator.loadedGrainIntensity = grainIntensity
            }
        }

        static func == (lhs: ReaderContent, rhs: ReaderContent) -> Bool {
            lhs.htmlContent == rhs.htmlContent &&
            lhs.fontSize == rhs.fontSize &&
            lhs.lineHeight == rhs.lineHeight &&
            lhs.fontFamily == rhs.fontFamily &&
            lhs.horizontalPadding == rhs.horizontalPadding &&
            lhs.verticalPadding == rhs.verticalPadding &&
            lhs.backgroundColorHex == rhs.backgroundColorHex &&
            lhs.textColorHex == rhs.textColorHex &&
            lhs.bionicReading == rhs.bionicReading &&
            lhs.lineFocusEnabled == rhs.lineFocusEnabled &&
            lhs.lineFocusLines == rhs.lineFocusLines &&
            lhs.lineFocusDulling == rhs.lineFocusDulling &&
            lhs.showControls == rhs.showControls &&
            lhs.bridge === rhs.bridge &&
            lhs.baseURL == rhs.baseURL &&
            lhs.characterSpacing == rhs.characterSpacing &&
            lhs.wordSpacing == rhs.wordSpacing &&
            lhs.grainIntensity == rhs.grainIntensity &&
            lhs.commentsHtml == rhs.commentsHtml &&
            lhs.hasMoreComments == rhs.hasMoreComments
        }
    }
#else
    struct ReaderContent: NSViewRepresentable, Equatable {
        let htmlContent: String
        let fontSize: Double
        let lineHeight: Double
        let fontFamily: String
        let horizontalPadding: Double
        let verticalPadding: Double
        let backgroundColorHex: String
        let textColorHex: String
        let bionicReading: Bool
        let lineFocusEnabled: Bool
        let lineFocusLines: Int
        let lineFocusDulling: String
        let showControls: Bool
        let bridge: ReaderContentBridge
        let baseURL: URL?
        let characterSpacing: Double
        let wordSpacing: Double
        let grainIntensity: Double
        let commentsHtml: String
        let hasMoreComments: Bool
        var onTap: (() -> Void)? = nil
        var onParagraphTap: ((Int) -> Void)? = nil
        var onLoadMoreComments: (() -> Void)? = nil
        var onLikeComment: ((String) -> Void)? = nil
        var onDislikeComment: ((String) -> Void)? = nil

        class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
            var loadedHtmlContent: String?
            var loadedFontSize: Double?
            var loadedLineHeight: Double?
            var loadedFontFamily: String?
            var loadedHorizontalPadding: Double?
            var loadedVerticalPadding: Double?
            var loadedBackgroundColorHex: String?
            var loadedTextColorHex: String?
            var loadedBionicReading: Bool?
            var loadedLineFocusEnabled: Bool?
            var loadedLineFocusLines: Int?
            var loadedLineFocusDulling: String?
            var loadedShowControls: Bool?
            var loadedCharacterSpacing: Double?
            var loadedWordSpacing: Double?
            var loadedGrainIntensity: Double?
            var loadedCommentsHtml: String?
            var loadedHasMoreComments: Bool?
            weak var bridge: ReaderContentBridge?
            var onParagraphTap: ((Int) -> Void)?
            var onTap: (() -> Void)?
            var parent: ReaderContent?

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
                } else if message.name == "scrollParagraph",
                          let body = message.body as? String,
                          let index = Int(body) {
                    DispatchQueue.main.async { [weak self] in
                        self?.bridge?.onParagraphScroll(index)
                    }
                } else if message.name == "toggleControls" {
                    DispatchQueue.main.async { [weak self] in
                        self?.onTap?()
                    }
                } else if message.name == "loadMoreComments" {
                    DispatchQueue.main.async { [weak self] in
                        self?.parent?.onLoadMoreComments?()
                    }
                } else if message.name == "likeComment",
                          let commentId = message.body as? String {
                    DispatchQueue.main.async { [weak self] in
                        self?.parent?.onLikeComment?(commentId)
                    }
                } else if message.name == "dislikeComment",
                          let commentId = message.body as? String {
                    DispatchQueue.main.async { [weak self] in
                        self?.parent?.onDislikeComment?(commentId)
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
            userContentController.add(helper, name: "scrollParagraph")
            userContentController.add(helper, name: "toggleControls")
            userContentController.add(helper, name: "loadMoreComments")
            userContentController.add(helper, name: "likeComment")
            userContentController.add(helper, name: "dislikeComment")
            config.userContentController = userContentController

            let webView = WKWebView(frame: .zero, configuration: config)
            webView.navigationDelegate = context.coordinator
            bridge.setWebView(webView)
            return webView
        }

        func updateNSView(_ webView: WKWebView, context: Context) {
            context.coordinator.parent = self
            context.coordinator.bridge = bridge
            context.coordinator.onParagraphTap = onParagraphTap
            context.coordinator.onTap = onTap
            
            let contentChanged = context.coordinator.loadedHtmlContent != htmlContent ||
                                 context.coordinator.loadedBionicReading != bionicReading
            let commentsChanged = context.coordinator.loadedCommentsHtml != commentsHtml
            let styleChanged = context.coordinator.loadedFontSize != fontSize ||
                               context.coordinator.loadedLineHeight != lineHeight ||
                               context.coordinator.loadedFontFamily != fontFamily ||
                               context.coordinator.loadedHorizontalPadding != horizontalPadding ||
                               context.coordinator.loadedVerticalPadding != verticalPadding ||
                               context.coordinator.loadedBackgroundColorHex != backgroundColorHex ||
                               context.coordinator.loadedTextColorHex != textColorHex ||
                               context.coordinator.loadedLineFocusEnabled != lineFocusEnabled ||
                               context.coordinator.loadedLineFocusLines != lineFocusLines ||
                               context.coordinator.loadedLineFocusDulling != lineFocusDulling ||
                               context.coordinator.loadedCharacterSpacing != characterSpacing ||
                               context.coordinator.loadedWordSpacing != wordSpacing ||
                               context.coordinator.loadedGrainIntensity != grainIntensity
            
            if contentChanged || context.coordinator.loadedHtmlContent == nil || (commentsChanged && context.coordinator.loadedCommentsHtml == nil) {
                bridge.contentDidChange()
                let html = readerHTML(content: htmlContent, comments: commentsHtml)
                webView.loadHTMLString(html, baseURL: baseURL)
                
                context.coordinator.loadedHtmlContent = htmlContent
                context.coordinator.loadedCommentsHtml = commentsHtml
                context.coordinator.loadedFontSize = fontSize
                context.coordinator.loadedLineHeight = lineHeight
                context.coordinator.loadedFontFamily = fontFamily
                context.coordinator.loadedHorizontalPadding = horizontalPadding
                context.coordinator.loadedVerticalPadding = verticalPadding
                context.coordinator.loadedBackgroundColorHex = backgroundColorHex
                context.coordinator.loadedTextColorHex = textColorHex
                context.coordinator.loadedBionicReading = bionicReading
                context.coordinator.loadedLineFocusEnabled = lineFocusEnabled
                context.coordinator.loadedLineFocusLines = lineFocusLines
                context.coordinator.loadedLineFocusDulling = lineFocusDulling
                context.coordinator.loadedShowControls = showControls
                context.coordinator.loadedCharacterSpacing = characterSpacing
                context.coordinator.loadedWordSpacing = wordSpacing
                context.coordinator.loadedGrainIntensity = grainIntensity
            } else if commentsChanged {
                context.coordinator.loadedCommentsHtml = commentsHtml
            } else if styleChanged {
                let resolvedBg = backgroundColorHex.isEmpty ? "" : backgroundColorHex
                let resolvedText = textColorHex.isEmpty ? "" : textColorHex
                
                let lineFocusOpacity = resolvedLineFocusOpacity(dulling: lineFocusDulling)
                let lineFocusHeight = resolvedLineFocusHeight(lines: lineFocusLines, fontSize: fontSize, lineHeight: lineHeight)
                let lineFocusDisplay = lineFocusEnabled ? "block" : "none"
                
                let topOffset = 70.0 + verticalPadding
                let bottomOffset = verticalPadding
                
                let js = """
                document.body.style.fontFamily = "'\(fontFamily)', 'Georgia', serif";
                document.body.style.fontSize = '\(fontSize)px';
                document.body.style.lineHeight = '\(lineHeight)';
                document.body.style.letterSpacing = '\(characterSpacing / 100.0)em';
                document.body.style.wordSpacing = '\(wordSpacing / 100.0)em';
                document.body.style.padding = '\(topOffset)px \(horizontalPadding)px \(bottomOffset)px';
                document.body.style.overflow = 'visible';
                document.body.style.height = 'auto';
                document.body.style.background = '\(resolvedBg)';
                document.body.style.color = '\(resolvedText)';
                
                var ruler = document.getElementById("line-focus-ruler");
                if (ruler) {
                    ruler.style.display = '\(lineFocusDisplay)';
                    ruler.style.height = '\(lineFocusHeight)px';
                    ruler.style.boxShadow = '0 0 0 9999px rgba(0, 0, 0, \(lineFocusOpacity))';
                }
                
                var grain = document.getElementById("paper-grain-overlay");
                if (grain) {
                    grain.style.opacity = '\(backgroundColorHex == "#1C1C1E" ? grainIntensity / 100.0 : 0.0)';
                }
                """
                webView.evaluateJavaScript(js)
                
                context.coordinator.loadedFontSize = fontSize
                context.coordinator.loadedLineHeight = lineHeight
                context.coordinator.loadedFontFamily = fontFamily
                context.coordinator.loadedHorizontalPadding = horizontalPadding
                context.coordinator.loadedVerticalPadding = verticalPadding
                context.coordinator.loadedBackgroundColorHex = backgroundColorHex
                context.coordinator.loadedTextColorHex = textColorHex
                context.coordinator.loadedLineFocusEnabled = lineFocusEnabled
                context.coordinator.loadedLineFocusLines = lineFocusLines
                context.coordinator.loadedLineFocusDulling = lineFocusDulling
                context.coordinator.loadedShowControls = showControls
                context.coordinator.loadedCharacterSpacing = characterSpacing
                context.coordinator.loadedWordSpacing = wordSpacing
                context.coordinator.loadedGrainIntensity = grainIntensity
            }
        }

        static func == (lhs: ReaderContent, rhs: ReaderContent) -> Bool {
            lhs.htmlContent == rhs.htmlContent &&
            lhs.fontSize == rhs.fontSize &&
            lhs.lineHeight == rhs.lineHeight &&
            lhs.fontFamily == rhs.fontFamily &&
            lhs.horizontalPadding == rhs.horizontalPadding &&
            lhs.verticalPadding == rhs.verticalPadding &&
            lhs.backgroundColorHex == rhs.backgroundColorHex &&
            lhs.textColorHex == rhs.textColorHex &&
            lhs.bionicReading == rhs.bionicReading &&
            lhs.lineFocusEnabled == rhs.lineFocusEnabled &&
            lhs.lineFocusLines == rhs.lineFocusLines &&
            lhs.lineFocusDulling == rhs.lineFocusDulling &&
            lhs.showControls == rhs.showControls &&
            lhs.bridge === rhs.bridge &&
            lhs.baseURL == rhs.baseURL &&
            lhs.characterSpacing == rhs.characterSpacing &&
            lhs.wordSpacing == rhs.wordSpacing &&
            lhs.grainIntensity == rhs.grainIntensity &&
            lhs.commentsHtml == rhs.commentsHtml &&
            lhs.hasMoreComments == rhs.hasMoreComments
        }
    }
#endif

// MARK: - HTML Template

extension ReaderContent {
    func readerHTML(content: String, comments: String = "") -> String {
        let resolvedBg = backgroundColorHex.isEmpty ? "transparent" : backgroundColorHex
        let resolvedText = textColorHex.isEmpty ? "#2c2c2e" : textColorHex

        let darkMediaQuery =
            textColorHex.isEmpty
            ? """
            @media (prefers-color-scheme: dark) {
                body { color: #e5e5e7; }
            }
            """ : ""

        let topOffset = 70.0 + verticalPadding
        let bottomOffset = verticalPadding

        var commentsSection = ""
        if !comments.isEmpty {
            commentsSection = """
            <hr class="comments-divider">
            <div id="lnw-comments-section" class="skiptranslate">
                <div class="comments-header">
                    <h3>User Comments</h3>
                </div>
                <div class="comment-wrapper">
                    <ul>
                        \(comments)
                    </ul>
                </div>
                <div class="comments-footer">
                    <button id="lmcomments" class="button \(hasMoreComments ? "" : "d-none")" onclick="loadMoreComments()">Load More Comments</button>
                </div>
            </div>
            """
        }

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
                letter-spacing: \(characterSpacing / 100.0)em;
                word-spacing: \(wordSpacing / 100.0)em;
                padding: \(topOffset)px \(horizontalPadding)px \(bottomOffset)px;
                color: \(resolvedText);
                background: \(resolvedBg);
                -webkit-font-smoothing: antialiased;
                word-wrap: break-word;
                overflow-wrap: break-word;
                position: relative;
                overflow: visible;
                height: auto;
            }
            \(darkMediaQuery)
            p {
                margin-bottom: 1em;
                text-align: justify;
            }
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
            #line-focus-ruler {
                position: fixed;
                top: 50%;
                left: 0;
                width: 100%;
                height: \(resolvedLineFocusHeight(lines: lineFocusLines, fontSize: fontSize, lineHeight: lineHeight))px;
                transform: translateY(-50%);
                background: transparent;
                box-shadow: 0 0 0 9999px rgba(0, 0, 0, \(resolvedLineFocusOpacity(dulling: lineFocusDulling)));
                pointer-events: none;
                z-index: 9999;
                border-top: 1px dashed rgba(212, 165, 116, 0.4);
                border-bottom: 1px dashed rgba(212, 165, 116, 0.4);
                display: \(lineFocusEnabled ? "block" : "none");
            }
            #paper-grain-overlay {
                position: fixed;
                top: 0;
                left: 0;
                width: 100vw;
                height: 100vh;
                pointer-events: none;
                z-index: 99999;
                opacity: \(backgroundColorHex == "#1C1C1E" ? grainIntensity / 100.0 : 0.0);
                background-image: url("data:image/svg+xml,%3Csvg viewBox='0 0 200 200' xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='noiseFilter'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.8' numOctaves='3' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23noiseFilter)'/%3E%3C/svg%3E");
                mix-blend-mode: overlay;
            }

            /* Comments Section CSS */
            hr.comments-divider {
                border: none;
                border-top: 1px solid rgba(128, 128, 128, 0.2);
                margin: 3em 0 2em;
            }
            #lnw-comments-section {
                padding: 0 0 4em;
                font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
                font-size: 15px;
                line-height: 1.5;
            }
            .comments-header h3 {
                font-size: 1.3em;
                font-weight: bold;
                margin-bottom: 1.5em;
                opacity: 0.9;
            }
            .comment-wrapper ul {
                list-style: none;
                padding: 0;
                margin: 0;
            }
            .comment-wrapper li {
                margin-bottom: 1.5em;
                padding-bottom: 1.5em;
                border-bottom: 1px solid rgba(128, 128, 128, 0.1);
            }
            .comment-wrapper li:last-child {
                border-bottom: none;
            }
            .comment-item {
                display: flex;
                flex-direction: column;
                gap: 8px;
            }
            .comment-header {
                display: flex;
                align-items: center;
                gap: 10px;
            }
            .user-avatar {
                width: 32px;
                height: 32px;
                border-radius: 50%;
                overflow: hidden;
                background: rgba(128, 128, 128, 0.1);
            }
            .user-avatar img.avatar {
                width: 100%;
                height: 100%;
                object-fit: cover;
                margin: 0;
                border-radius: 0;
            }
            .user-info {
                display: flex;
                flex-direction: column;
            }
            .head-items {
                display: flex;
                align-items: center;
                gap: 6px;
            }
            .username {
                font-weight: 600;
                color: inherit;
                opacity: 0.95;
                font-size: 14px;
            }
            .tier {
                font-size: 10px;
                background: rgba(128, 128, 128, 0.15);
                padding: 2px 6px;
                border-radius: 4px;
                opacity: 0.7;
                text-transform: uppercase;
                font-weight: bold;
                letter-spacing: 0.5px;
            }
            .post-date {
                font-size: 12px;
                opacity: 0.5;
                margin-left: auto;
            }
            .comment-body {
                padding-left: 0;
            }
            .comment-text {
                font-size: 14.5px;
                opacity: 0.9;
                word-break: break-word;
            }
            .comment-text p {
                margin-bottom: 0.5em;
                text-align: left;
            }
            .comment-text p:last-child {
                margin-bottom: 0;
            }
            .comment-text[data-spoiler="1"] {
                background: rgba(128, 128, 128, 0.1);
                color: transparent !important;
                text-shadow: 0 0 8px rgba(128, 128, 128, 0.8);
                cursor: pointer;
                border-radius: 4px;
                padding: 4px 8px;
                user-select: none;
            }
            .comment-text[data-spoiler="1"] * {
                color: transparent !important;
            }
            .comment-text[data-spoiler="1"]::before {
                content: "Spoiler Warning (Tap to reveal)";
                display: block;
                color: #e53e3e !important;
                font-weight: bold;
                font-size: 12px;
                margin-bottom: 4px;
                text-shadow: none;
            }
            .comment-text[data-spoiler="1"].revealed {
                background: transparent;
                color: inherit !important;
                text-shadow: none;
                user-select: auto;
                padding: 0;
            }
            .comment-text[data-spoiler="1"].revealed * {
                color: inherit !important;
            }
            .comment-text[data-spoiler="1"].revealed::before {
                display: none;
            }
            .toolbar {
                display: flex;
                align-items: center;
                gap: 12px;
                margin-top: 6px;
                font-size: 12px;
                opacity: 0.7;
            }
            .toolbar a.reply, .toolbar button.btn-report, .toolbar .reportComment {
                background: none;
                border: none;
                color: inherit;
                font-family: inherit;
                font-size: inherit;
                cursor: pointer;
                padding: 0;
                display: flex;
                align-items: center;
                gap: 4px;
                text-decoration: none;
            }
            .toolbar .divider {
                width: 1px;
                height: 12px;
                background: rgba(128, 128, 128, 0.2);
            }
            .toolbar .spacer {
                margin-left: auto;
            }
            .usrlike {
                display: flex;
                align-items: center;
                gap: 10px;
            }
            .like-group, .dislike-group {
                display: flex;
                align-items: center;
            }
            .like-button, .dislike-button {
                cursor: pointer;
                display: flex;
                align-items: center;
                gap: 4px;
                padding: 4px 8px;
                border-radius: 4px;
                background: rgba(128, 128, 128, 0.08);
                transition: background 0.2s, color 0.2s;
            }
            .like-button:hover, .dislike-button:hover {
                background: rgba(128, 128, 128, 0.15);
            }
            .like-button.checked {
                color: #3182ce !important;
                background: rgba(49, 130, 206, 0.15);
            }
            .dislike-button.checked {
                color: #e53e3e !important;
                background: rgba(229, 62, 62, 0.15);
            }
            .reply-comments {
                margin-left: 20px;
                padding-left: 14px;
                border-left: 2px solid rgba(128, 128, 128, 0.15);
                margin-top: 1em;
            }
            .parent-link {
                display: inline-flex;
                align-items: center;
                gap: 4px;
                font-size: 11px;
                opacity: 0.6;
                margin-left: 4px;
            }
            .parent-link a {
                color: inherit;
                text-decoration: underline;
            }
            .comments-footer {
                display: flex;
                justify-content: center;
                margin-top: 2em;
            }
            button#lmcomments {
                border: none;
                font-family: inherit;
                font-size: 13px;
                font-weight: bold;
                padding: 10px 24px;
                border-radius: 20px;
                background: rgba(128, 128, 128, 0.1);
                color: inherit;
                cursor: pointer;
                transition: background 0.2s;
            }
            button#lmcomments:hover {
                background: rgba(128, 128, 128, 0.2);
            }
            .d-none {
                display: none !important;
            }
            </style>
            </head>
            <body>
            \(content)
            \(commentsSection)
            <div id="tts-dot"></div>
            <div id="line-focus-ruler"></div>
            <div id="paper-grain-overlay"></div>
            <script>
            window.onerror = function(message, source, lineno, colno, error) {
                var errorStr = message + " at " + source + ":" + lineno + ":" + colno;
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.jsError) {
                    window.webkit.messageHandlers.jsError.postMessage(errorStr);
                }
                return false;
            };
            </script>
            <script>
            window.loadMoreComments = function() {
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.loadMoreComments) {
                    window.webkit.messageHandlers.loadMoreComments.postMessage("");
                }
            }

            window.appendComments = function(newHtml, hasMore) {
                var container = document.querySelector(".comment-wrapper > ul");
                if (container) {
                    container.insertAdjacentHTML('beforeend', newHtml);
                }
                var loadMoreBtn = document.getElementById("lmcomments");
                if (loadMoreBtn) {
                    if (hasMore) {
                        loadMoreBtn.classList.remove("d-none");
                    } else {
                        loadMoreBtn.classList.add("d-none");
                    }
                }
                window.initSpoilers();
            }

            window.initSpoilers = function() {
                var spoilers = document.querySelectorAll('.comment-text[data-spoiler="1"]');
                spoilers.forEach(function(el) {
                    if (!el.classList.contains('has-spoiler-click')) {
                        el.classList.add('has-spoiler-click');
                        el.addEventListener('click', function() {
                            el.classList.add('revealed');
                            el.setAttribute('data-spoiler', '0');
                        });
                    }
                });
            }

            // Hook up like and dislike handlers
            document.addEventListener("click", function(e) {
                var likeBtn = e.target.closest(".like-button");
                if (likeBtn) {
                    var commentId = likeBtn.getAttribute("data-comment-id");
                    if (commentId && window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.likeComment) {
                        window.webkit.messageHandlers.likeComment.postMessage(commentId);
                    }
                    return;
                }
                
                var dislikeBtn = e.target.closest(".dislike-button");
                if (dislikeBtn) {
                    var commentId = dislikeBtn.getAttribute("data-comment-id");
                    if (commentId && window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.dislikeComment) {
                        window.webkit.messageHandlers.dislikeComment.postMessage(commentId);
                    }
                    return;
                }
            });

            window.updateCommentLikes = function(commentId, likes, dislikes, isLikeAction) {
                var commentEl = document.getElementById("lnw-comment-" + commentId);
                if (!commentEl) return;
                
                var likeBtn = commentEl.querySelector(".like-button");
                var dislikeBtn = commentEl.querySelector(".dislike-button");
                
                if (likeBtn) {
                    var countSpan = likeBtn.querySelector("span");
                    if (countSpan) countSpan.innerText = likes;
                    if (isLikeAction) {
                        likeBtn.classList.toggle("checked");
                        if (dislikeBtn) dislikeBtn.classList.remove("checked");
                    }
                }
                if (dislikeBtn) {
                    var countSpan = dislikeBtn.querySelector("span");
                    if (countSpan) countSpan.innerText = dislikes;
                    if (!isLikeAction) {
                        dislikeBtn.classList.toggle("checked");
                        if (likeBtn) likeBtn.classList.remove("checked");
                    }
                }
            }

            // Trigger initial spoiler init
            window.addEventListener("DOMContentLoaded", function() {
                window.initSpoilers();
            });
            window.initSpoilers();
            </script>
            <script>
            \(getTTSJavaScriptSource())
            </script>
            </body>
            </html>
            """
    }

    func getTTSJavaScriptSource() -> String {
        let resolvedBionic = bionicReading ? "true" : "false"
        return """
        window.scrollToParagraph = function(index) {
            var target = document.querySelector('[data-tts-index="' + index + '"]');
            if (!target) return;
            window.__restoreIndex = index;
            target.scrollIntoView({ behavior: 'auto', block: 'center' });
        }

        window.getParagraphs = function() {
            if (!window.__cachedParagraphs) {
                var allNodes = Array.from(document.querySelectorAll("p, h1, h2, h3, h4, h5, h6, li"));
                window.__cachedParagraphs = allNodes.filter(function(node) {
                    return !node.closest("#lnw-comments-section");
                });
            }
            return window.__cachedParagraphs;
        }

        window.collectBlocks = function() {
            if (window.__ttsBlocks) return;
            var nodes = window.getParagraphs();
            var texts = [];
            nodes.forEach(function(node) {
                var text = node.innerText.replace(/\\s+/g, " ").trim();
                if (text.length === 0) {
                    node.setAttribute("data-tts-index", "-1");
                    return;
                }
                var index = texts.length;
                node.setAttribute("data-tts-index", String(index));
                texts.push(text);
            });
            window.__ttsBlocks = texts;
        }

        window.applyBionicToNode = function(startNode) {
            var processNode = function(node) {
                if (node.nodeType === 3) {
                    var text = node.nodeValue;
                    if (!text.trim()) return;
                    
                    var parent = node.parentNode;
                    if (parent && (parent.tagName === 'SCRIPT' || parent.tagName === 'STYLE' || parent.tagName === 'TITLE' || parent.className === 'tts-active' || parent.id === 'tts-dot' || parent.id === 'line-focus-ruler')) {
                        return;
                    }
                    
                    var wordRegex = /(\\p{L}+)/gu;
                    var match;
                    var fragment = document.createDocumentFragment();
                    var lastIndex = 0;
                    var hasWord = false;
                    
                    while ((match = wordRegex.exec(text)) !== null) {
                        hasWord = true;
                        var matchIndex = match.index;
                        var matchWord = match[0];
                        
                        if (matchIndex > lastIndex) {
                            fragment.appendChild(document.createTextNode(text.substring(lastIndex, matchIndex)));
                        }
                        
                        var len = matchWord.length;
                        var boldLen = len <= 3 ? (len === 3 ? 2 : 1) : Math.ceil(len * 0.5);
                        var part1 = matchWord.substring(0, boldLen);
                        var part2 = matchWord.substring(boldLen);
                        
                        var b = document.createElement('strong');
                        b.textContent = part1;
                        fragment.appendChild(b);
                        
                        if (part2.length > 0) {
                            fragment.appendChild(document.createTextNode(part2));
                        }
                        
                        lastIndex = wordRegex.lastIndex;
                    }
                    
                    if (hasWord) {
                        if (lastIndex < text.length) {
                            fragment.appendChild(document.createTextNode(text.substring(lastIndex)));
                        }
                        parent.replaceChild(fragment, node);
                    }
                } else if (node.nodeType === 1) {
                    var tagName = node.tagName.toUpperCase();
                    if (tagName !== 'SCRIPT' && tagName !== 'STYLE' && tagName !== 'TITLE' && node.id !== 'tts-dot' && node.id !== 'line-focus-ruler') {
                        var children = Array.from(node.childNodes);
                        for (var i = 0; i < children.length; i++) {
                            processNode(children[i]);
                        }
                    }
                }
            };
            processNode(startNode);
        }

        window.applyBionicReading = function() {
            window.applyBionicToNode(document.body);
        }

        window.applyLazyBionicReading = function() {
            if (!window.IntersectionObserver) {
                window.applyBionicReading();
                return;
            }
            var paragraphs = window.getParagraphs();
            var observer = new IntersectionObserver(function(entries) {
                entries.forEach(function(entry) {
                    if (entry.isIntersecting) {
                        var node = entry.target;
                        window.applyBionicToNode(node);
                        observer.unobserve(node);
                    }
                });
            }, { rootMargin: "250px" });
            
            paragraphs.forEach(function(p) {
                observer.observe(p);
            });
        }

        window.ensureDot = function() {
            var dot = document.getElementById("tts-dot");
            if (!dot) {
                dot = document.createElement("div");
                dot.id = "tts-dot";
                document.body.appendChild(dot);
            }
            return dot;
        }

        window.prepareTTS = function() {
            if (\(resolvedBionic)) {
                window.applyLazyBionicReading();
            }
            window.collectBlocks();
            window.ensureDot();
        };

        window.getTTSBlocks = function() {
            window.collectBlocks();
            return window.__ttsBlocks || [];
        };

        window.isElementVisible = function(el) {
            var rect = el.getBoundingClientRect();
            return (
                rect.top >= 100 &&
                rect.bottom <= (window.innerHeight || document.documentElement.clientHeight) - 120
            );
        }

        window.setTTSActiveIndex = function(index) {
            window.collectBlocks();
            var active = document.querySelector(".tts-active");
            if (active) {
                active.classList.remove("tts-active");
            }
            var target = document.querySelector('[data-tts-index="' + index + '"]');
            var dot = window.ensureDot();
            if (!target) {
                if (dot) { dot.style.opacity = 0; }
                return;
            }
            target.classList.add("tts-active");
            window.__restoreIndex = index;
            if (!window.isElementVisible(target)) {
                target.scrollIntoView({ behavior: 'smooth', block: 'center' });
            }
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

        window.addEventListener("scroll", function() {
            if (window.__scrollTimeout) {
                clearTimeout(window.__scrollTimeout);
            }
            window.__scrollTimeout = setTimeout(function() {
                var paragraphs = window.getParagraphs();
                var topIndex = -1;
                for (var i = 0; i < paragraphs.length; i++) {
                    var node = paragraphs[i];
                    var rect = node.getBoundingClientRect();
                    if (rect.bottom > 80) {
                        var indexAttr = node.getAttribute("data-tts-index");
                        if (indexAttr) {
                            var index = parseInt(indexAttr);
                            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.scrollParagraph) {
                                window.webkit.messageHandlers.scrollParagraph.postMessage(String(index));
                            }
                            break;
                        }
                    }
                }
                if (topIndex >= 0 && window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.scrollParagraph) {
                    window.webkit.messageHandlers.scrollParagraph.postMessage(String(topIndex));
                }
            }, 300);
        });

        // Gestures management using PointerEvents
        var startX = 0;
        var startY = 0;
        var startTime = 0;

        window.addEventListener("pointerdown", function(e) {
            if (!e.isPrimary) return;
            if (e.target.tagName === 'A' || e.target.closest('a') || e.target.tagName === 'BUTTON') return;
            
            startX = e.clientX;
            startY = e.clientY;
            startTime = Date.now();
        });

        window.addEventListener("pointerup", function(e) {
            if (!e.isPrimary) return;
            if (e.target.tagName === 'A' || e.target.closest('a') || e.target.tagName === 'BUTTON') return;

            var diffX = e.clientX - startX;
            var diffY = e.clientY - startY;
            var elapsed = Date.now() - startTime;

            // Check if there is active selection
            var selection = window.getSelection().toString();
            if (selection && selection.trim().length > 0) {
                return;
            }

            // Tap detection
            if (Math.abs(diffX) < 8 && Math.abs(diffY) < 8 && elapsed < 300) {
                // Scroll mode: tap toggles controls, or triggers tapParagraph if on a paragraph
                var paragraph = e.target.closest('p, h1, h2, h3, h4, h5, h6, li');
                if (paragraph) {
                    var indexAttr = paragraph.getAttribute("data-tts-index");
                    if (indexAttr && indexAttr !== "-1") {
                        var index = parseInt(indexAttr);
                        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.tapParagraph) {
                            window.webkit.messageHandlers.tapParagraph.postMessage(String(index));
                        }
                    }
                }
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.toggleControls) {
                    window.webkit.messageHandlers.toggleControls.postMessage("");
                }
            }
        });

        window.prepareTTS();
        """
    }

    private func resolvedLineFocusOpacity(dulling: String) -> Double {
        switch dulling {
        case "low": return 0.3
        case "high": return 0.75
        default: return 0.5
        }
    }

    private func resolvedLineFocusHeight(lines: Int, fontSize: Double, lineHeight: Double) -> Double {
        return (Double(lines) + 0.5) * lineHeight * fontSize
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

extension UIColor {
    convenience init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0

        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r, g, b, a: CGFloat
        if hexSanitized.count == 6 {
            r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
            g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
            b = CGFloat(rgb & 0x0000FF) / 255.0
            a = 1.0
        } else if hexSanitized.count == 8 {
            r = CGFloat((rgb & 0xFF000000) >> 24) / 255.0
            g = CGFloat((rgb & 0x00FF0000) >> 16) / 255.0
            b = CGFloat((rgb & 0x0000FF00) >> 8) / 255.0
            a = CGFloat(rgb & 0x000000FF) / 255.0
        } else {
            return nil
        }

        self.init(red: r, green: g, blue: b, alpha: a)
    }
}

