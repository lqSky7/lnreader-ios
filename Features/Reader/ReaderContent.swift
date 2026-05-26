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

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.showsHorizontalScrollIndicator = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let html = readerHTML(content: htmlContent)
        webView.loadHTMLString(html, baseURL: nil)
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

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let html = readerHTML(content: htmlContent)
        webView.loadHTMLString(html, baseURL: nil)
    }
}
#endif

// MARK: - HTML Template

extension ReaderContent {
    func readerHTML(content: String) -> String {
        let resolvedBg = backgroundColorHex.isEmpty ? "transparent" : backgroundColorHex
        let resolvedText = textColorHex.isEmpty ? "#2c2c2e" : textColorHex
        
        let darkMediaQuery = textColorHex.isEmpty ? """
        @media (prefers-color-scheme: dark) {
            body { color: #e5e5e7; }
        }
        """ : ""

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
        <style>
        :root {
            color-scheme: light dark;
        }
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: '\(fontFamily)', 'Georgia', serif;
            font-size: \(fontSize)px;
            line-height: \(lineHeight);
            padding: 20px \(horizontalPadding)px 60px;
            color: \(resolvedText);
            background: \(resolvedBg);
            -webkit-font-smoothing: antialiased;
            word-wrap: break-word;
            overflow-wrap: break-word;
        }
        \(darkMediaQuery)
        p { margin-bottom: 1em; text-align: justify; }
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
        </style>
        </head>
        <body>\(content)</body>
        </html>
        """
    }
}
