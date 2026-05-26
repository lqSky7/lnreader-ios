import Foundation
import SwiftUI

/// Lightweight HTML parser for converting chapter HTML into displayable content.
///
/// This handles the subset of HTML commonly found in light novel chapter content:
/// paragraphs, line breaks, emphasis, strong, and headings.
enum HTMLParser {

    // MARK: - Plain Text

    /// Strip all HTML tags and decode entities, returning plain text.
    static func stripTags(_ html: String) -> String {
        var result = html

        // Replace block-level elements with newlines before stripping
        let blockTags = ["</p>", "</div>", "</br>", "<br>", "<br/>", "<br />",
                         "</h1>", "</h2>", "</h3>", "</h4>", "</h5>", "</h6>"]
        for tag in blockTags {
            result = result.replacingOccurrences(of: tag, with: "\n", options: .caseInsensitive)
        }

        // Remove all remaining tags
        result = result.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )

        // Decode HTML entities
        result = decodeEntities(result)

        // Collapse multiple newlines
        result = result.replacingOccurrences(
            of: "\n{3,}",
            with: "\n\n",
            options: .regularExpression
        )

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - AttributedString

    /// Convert basic HTML into an `AttributedString` with styling.
    ///
    /// Supports: `<p>`, `<br>`, `<em>`/`<i>`, `<strong>`/`<b>`, `<h1>`–`<h6>`.
    /// Unsupported tags are stripped. Images and links are ignored.
    static func attributedString(from html: String) -> AttributedString {
        // Try the system HTML parser first (it handles most cases well)
        if let nsAttr = try? NSAttributedString(
            data: Data(wrappedHTML(html).utf8),
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
        ) {
            var result = AttributedString(nsAttr)
            // Apply default body font so it doesn't render as Times New Roman
            result.font = .body
            return result
        }

        // Fallback: just use plain text
        return AttributedString(stripTags(html))
    }

    // MARK: - Entity Decoding

    /// Decode common HTML entities.
    static func decodeEntities(_ string: String) -> String {
        let entities: [String: String] = [
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&#39;": "'",
            "&apos;": "'",
            "&nbsp;": " ",
            "&mdash;": "—",
            "&ndash;": "–",
            "&laquo;": "«",
            "&raquo;": "»",
            "&hellip;": "…",
            "&copy;": "©",
            "&reg;": "®",
            "&trade;": "™",
        ]

        var result = string
        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }

        // Decode numeric entities (&#NNN; and &#xHHH;)
        result = decodeNumericEntities(result)

        return result
    }

    // MARK: - Private Helpers

    /// Wrap raw HTML fragment in a minimal document for NSAttributedString parsing.
    private static func wrappedHTML(_ fragment: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
            body {
                font-family: -apple-system, system-ui;
                font-size: 17px;
                line-height: 1.6;
                color: #000;
            }
            h1, h2, h3, h4, h5, h6 {
                font-family: -apple-system, system-ui;
            }
        </style>
        </head>
        <body>\(fragment)</body>
        </html>
        """
    }

    /// Decode numeric HTML entities like `&#8212;` and `&#x2014;`.
    private static func decodeNumericEntities(_ string: String) -> String {
        var result = string

        // Decimal: &#NNN;
        let decimalPattern = /&#(\d+);/
        result = result.replacing(decimalPattern) { match in
            if let code = UInt32(match.1), let scalar = Unicode.Scalar(code) {
                return String(Character(scalar))
            }
            return String(match.0)
        }

        // Hexadecimal: &#xHHH;
        let hexPattern = /&#x([0-9a-fA-F]+);/
        result = result.replacing(hexPattern) { match in
            if let code = UInt32(match.1, radix: 16), let scalar = Unicode.Scalar(code) {
                return String(Character(scalar))
            }
            return String(match.0)
        }

        return result
    }
}
