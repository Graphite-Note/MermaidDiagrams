/**
 * File: DiagramLabelDecoder.swift
 * -------------------------------
 * Layer: Core
 * Description: Turns the text written for a node, an edge or a group into the lines drawn.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.5
 * Date: 23/11/2026
 */

import Foundation

/// Turns the text written for a node, an edge or a group into the plain lines that are drawn, as Pele's label layout
/// does (text/label.ts `layoutLines`): `<br>`, a written `\n` and line breaks end lines, other HTML tags are dropped
/// (`DiagramLabelMarkup`), Mermaid's entity codes (`#quot;`, `#9829;`) and HTML's (`&lt;`) become
/// their characters, a Markdown string loses its emphasis markers, and each line loses the spaces at its ends, as Pele's
/// `layoutLines` trims each part (text/label.ts); spaces inside a line stay as written, as Pele draws them.
enum DiagramLabelDecoder {
    /// How the text was written: plain or quoted, or as a Markdown string (`"`…`"`).
    enum Form {
        case plain
        case markdown
        /// Text in which only `<br>` is markup: other tags stay as written, as a timeline's do.
        case literal
    }

    static func label(from rawText: String, form: Form) -> DiagramLabel {
        // Most text is one plain line: nothing to break, drop, decode or trim.
        if form != .markdown, isOnePlainLine(rawText) { return DiagramLabel(lines: [rawText]) }
        var lines: [String] = []
        // Pele trims the whole text first, then each of its lines.
        for writtenLine in lineBreakSeparated(trimmingSpaces(rawText)) {
            // Pele trims each part before its tags, emphasis and entities are read, so `&nbsp;` at an end stays.
            var line = trimmingSpaces(writtenLine)
            if form != .literal { line = DiagramLabelMarkup.withoutTags(line) }
            if form == .markdown { line = DiagramLabelMarkup.withoutEmphasisMarkers(line) }
            lines.append(decodingEntities(line))
        }
        return DiagramLabel(lines: lines)
    }

    /// Whether the text has no tag, entity code, line break or tab, and no space at either end or next to another, so
    /// that decoding it would leave it as it is.
    private static func isOnePlainLine(_ text: String) -> Bool {
        var followsSpace = true
        for byte in text.utf8 {
            switch byte {
            case UInt8(ascii: "<"), UInt8(ascii: "&"), UInt8(ascii: "#"), UInt8(ascii: "\n"), UInt8(ascii: "\r"), UInt8(ascii: "\t"),
                 UInt8(ascii: "\\"): return false
            case UInt8(ascii: " "):
                if followsSpace { return false }
                followsSpace = true
            default: followsSpace = false
            }
        }
        return !followsSpace || text.isEmpty
    }

    /// The text split where Pele's `RE_BREAK` (`/<br\s*\/?>|\\n|\n/gi`, text/label.ts) splits it: at `<br>`, `<br/>`,
    /// `<br />` (in any case), at a written `\n` (a backslash and an `n`) and at line breaks.
    private static func lineBreakSeparated(_ text: String) -> [String] {
        var lines: [String] = []
        var current = ""
        var scalars = Substring(text).unicodeScalars[...]
        while let scalar = scalars.first {
            if scalar == "\n" {
                lines.append(current)
                current = ""
                scalars = scalars.dropFirst()
            } else if scalar == "\\", scalars.dropFirst().first == "n" {
                lines.append(current)
                current = ""
                scalars = scalars.dropFirst(2)
            } else if scalar == "<", let length = lineBreakTagLength(in: scalars) {
                lines.append(current)
                current = ""
                scalars = scalars.dropFirst(length)
            } else {
                current.unicodeScalars.append(scalar)
                scalars = scalars.dropFirst()
            }
        }
        lines.append(current)
        return lines
    }

    /// The length of a `<br>` tag at the start of `scalars`, or nil when it is not one: `<br`, in any case, any white
    /// space, an optional `/` and `>` (`<br>`, `<br/>`, `<br  />`). `<brand>` and `<br class="x">` are other tags, which
    /// are dropped without breaking the line, as Pele's `inline` drops them.
    private static func lineBreakTagLength(in scalars: Substring.UnicodeScalarView.SubSequence) -> Int? {
        let nameLength = 3
        guard String(String.UnicodeScalarView(scalars.prefix(nameLength))).lowercased() == "<br" else { return nil }
        var rest = scalars.dropFirst(nameLength)
        while let next = rest.first, next.properties.isWhitespace { rest = rest.dropFirst() }
        if rest.first == "/" { rest = rest.dropFirst() }
        guard rest.first == ">" else { return nil }
        return scalars.distance(from: scalars.startIndex, to: rest.startIndex) + 1
    }

    private static func trimmingSpaces(_ line: String) -> String {
        line.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The line with each entity code replaced by its character: `#name;` and `#123;` (Mermaid's), `&name;`, `&#123;`
    /// and `&#x7B;` (HTML's). An unknown name, or a number that is no character, stays as written.
    static func decodingEntities(_ line: String) -> String {
        guard line.contains(";") else { return line }
        var result = String.UnicodeScalarView()
        var scalars = line.unicodeScalars[...]
        while let scalar = scalars.first {
            if scalar == "#" || scalar == "&", let (decoded, length) = entity(at: scalars) {
                result.append(decoded)
                scalars = scalars.dropFirst(length)
                continue
            }
            result.append(scalar)
            scalars = scalars.dropFirst()
        }
        return String(result)
    }

    /// The character an entity code at the start of `scalars` stands for, and the code's length.
    private static func entity(at scalars: Substring.UnicodeScalarView.SubSequence) -> (Unicode.Scalar, Int)? {
        let maximumCodeLength = 12
        guard let semicolon = scalars.prefix(maximumCodeLength).firstIndex(of: ";") else { return nil }
        let body = String(String.UnicodeScalarView(scalars[scalars.index(after: scalars.startIndex)..<semicolon]))
        let length = scalars.distance(from: scalars.startIndex, to: semicolon) + 1
        let decoded: Unicode.Scalar?
        if scalars.first == "&" {
            decoded = body.hasPrefix("#") ? numberedCharacter(body.dropFirst()) : namedEntities[body]
        } else {
            decoded = numberedCharacter(Substring(body)) ?? namedEntities[body]
        }
        return decoded.map { character in (character, length) }
    }

    /// The character a decimal number, or a hexadecimal one after `x`, stands for.
    private static func numberedCharacter(_ digits: Substring) -> Unicode.Scalar? {
        if let first = digits.first, first == "x" || first == "X" {
            return UInt32(digits.dropFirst(), radix: 16).flatMap(Unicode.Scalar.init)
        }
        return UInt32(digits).flatMap(Unicode.Scalar.init)
    }

    /// The named entities diagrams use: Mermaid's examples and the common HTML ones.
    private static let namedEntities: [String: Unicode.Scalar] = [
        "quot": "\"", "amp": "&", "lt": "<", "gt": ">", "apos": "'", "nbsp": "\u{00A0}", "copy": "©", "reg": "®",
        "deg": "°", "hellip": "…", "mdash": "—", "ndash": "–", "times": "×", "divide": "÷", "plusmn": "±",
        "larr": "←", "rarr": "→", "uarr": "↑", "darr": "↓", "harr": "↔", "hearts": "♥", "check": "✓", "infin": "∞",
        "ne": "≠", "le": "≤", "ge": "≥", "middot": "·", "bull": "•", "laquo": "«", "raquo": "»", "euro": "€",
    ]
}
