/**
 * File: DiagramLabelLineBreaks.swift
 * ----------------------------------
 * Layer: Core
 * Description: Where a label's text breaks into lines as Pele breaks it (<br>, a written \n, a line break), the text
 *              Pele reads without markup, a Markdown string's indentation, and the literal text of journeys and timelines.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

/// The line structure of a label's text, as Pele's text/label.ts and common/fit.ts read it.
enum DiagramLabelLineBreaks {
    /// The text split where Pele's `RE_BREAK` (`<br\s*\/?>|\\n|\n`, in any case) matches: `<br>`, `<br/>`, `<br />`
    /// with any whitespace before the `/`, a backslash and `n` or `N` as written, and a line break.
    static func lines(of scalars: ArraySlice<Unicode.Scalar>) -> [ArraySlice<Unicode.Scalar>] {
        var lines: [ArraySlice<Unicode.Scalar>] = []
        var lineStart = scalars.startIndex
        var index = scalars.startIndex
        while index < scalars.endIndex {
            if let length = breakLength(in: scalars, at: index) {
                lines.append(scalars[lineStart..<index])
                index += length
                lineStart = index
            } else {
                index += 1
            }
        }
        lines.append(scalars[lineStart..<scalars.endIndex])
        return lines
    }

    /// The length of a break at `index`, or nil.
    static func breakLength(in scalars: ArraySlice<Unicode.Scalar>, at index: Int) -> Int? {
        switch scalars[index] {
        case "\n": return 1
        case "\\": return index + 1 < scalars.endIndex && (scalars[index + 1] == "n" || scalars[index + 1] == "N") ? 2 : nil
        case "<": return lineBreakTagLength(in: scalars, at: index)
        default: return nil
        }
    }

    /// The length of `<br\s*\/?>`, in any case, at `index`, or nil.
    static func lineBreakTagLength(in scalars: ArraySlice<Unicode.Scalar>, at index: Int) -> Int? {
        guard index + 3 < scalars.endIndex, scalars[index] == "<", scalars[index + 1] == "b" || scalars[index + 1] == "B",
              scalars[index + 2] == "r" || scalars[index + 2] == "R" else { return nil }
        var end = index + 3
        while end < scalars.endIndex, JavaScriptStringTrimming.isWhitespace(scalars[end]) { end += 1 }
        if end < scalars.endIndex, scalars[end] == "/" { end += 1 }
        guard end < scalars.endIndex, scalars[end] == ">" else { return nil }
        return end + 1 - index
    }

    /// Whether Pele lays the text out as one line as written, trimmed (its `RE_MARKUP` test): no `<`, backslash, line
    /// break, `*` or `_`, no `fa:fa-` icon, no `&`, and no Mermaid code (`#name;`, which Pele hides behind characters it
    /// then tests for).
    static func isUnmarked(_ scalars: [Unicode.Scalar]) -> Bool {
        var hasHash = false
        var hasSemicolon = false
        for scalar in scalars {
            switch scalar {
            case "<", "\\", "\n", "*", "_", "&": return false
            case "#": hasHash = true
            case ";": hasSemicolon = true
            default: break
            }
        }
        if hasHash, hasSemicolon, DiagramLabelEntities.mermaidCodesAsHTML(scalars) != scalars { return false }
        return !DiagramLabelIcons.containsIconName(scalars[...])
    }

    /// Whether the text's bytes hold none of the characters markup needs (`<`, backslash, line break, `*`, `_`, `&`, a
    /// `#` with a `;`, and `:` for an icon name), so that it is unmarked without reading it further.
    static func isUnmarked(_ bytes: String.UTF8View) -> Bool {
        var hasHash = false
        var hasSemicolon = false
        for byte in bytes {
            switch byte {
            case UInt8(ascii: "<"), UInt8(ascii: "\\"), UInt8(ascii: "\n"), UInt8(ascii: "*"), UInt8(ascii: "_"), UInt8(ascii: "&"), UInt8(ascii: ":"):
                return false
            case UInt8(ascii: "#"): hasHash = true
            case UInt8(ascii: ";"): hasSemicolon = true
            default: break
            }
        }
        return !(hasHash && hasSemicolon)
    }

    /// A Markdown string's text as Pele reads it before its lines: carriage returns as line breaks, the indentation all
    /// its lines with text share taken off each line, and the whole trimmed (text/label.ts `dedent`).
    static func markdownSource(_ scalars: [Unicode.Scalar]) -> ArraySlice<Unicode.Scalar> {
        var normalized: [Unicode.Scalar] = []
        normalized.reserveCapacity(scalars.count)
        var index = 0
        while index < scalars.count {
            if scalars[index] == "\r" {
                normalized.append("\n")
                if index + 1 < scalars.count, scalars[index + 1] == "\n" { index += 1 }
            } else {
                normalized.append(scalars[index])
            }
            index += 1
        }
        return JavaScriptStringTrimming.trimmed(dedented(normalized)[...])
    }

    private static func dedented(_ scalars: [Unicode.Scalar]) -> [Unicode.Scalar] {
        let lines = scalars.split(separator: "\n", omittingEmptySubsequences: false)
        let indents = lines.map { line in line.prefix(while: JavaScriptStringTrimming.isWhitespace).count }
        let shared = zip(lines, indents).filter { line, indent in indent < line.count }.map(\.1).min() ?? 0
        guard shared > 0 else { return scalars }
        return Array(zip(lines, indents).map { line, indent in line.dropFirst(min(shared, indent)) }.joined(separator: ["\n"]))
    }

    /// The text of a journey's or timeline's label as Pele's `plainLabel` writes it before laying it out: each `<` that
    /// starts no `<br>` written `&lt;` and each `:fa-` written `&colon;fa-`, so that tags and icon names show as written.
    static func literalText(_ scalars: [Unicode.Scalar]) -> [Unicode.Scalar] {
        guard scalars.contains("<") || scalars.contains(":") else { return scalars }
        var result: [Unicode.Scalar] = []
        result.reserveCapacity(scalars.count)
        let all = scalars[...]
        for index in scalars.indices {
            let scalar = scalars[index]
            if scalar == "<", lineBreakTagLength(in: all, at: index) == nil {
                result.append(contentsOf: "&lt;".unicodeScalars)
            } else if scalar == ":", index + 3 < scalars.count, scalars[index + 1] == "f", scalars[index + 2] == "a", scalars[index + 3] == "-" {
                result.append(contentsOf: "&colon;".unicodeScalars)
            } else {
                result.append(scalar)
            }
        }
        return result
    }
}
