/**
 * File: C4IndentedLines.swift
 * ---------------------------
 * Layer: Core
 * Description: Mermaid's `replace(/\n\s+/g, '\n')` of a C4 diagram's accessibility description: the white space after
 *              each line break taken out, the text kept as its range when it holds no line feed.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

enum C4IndentedLines {
    /// `text` with the white space after each line break, line breaks included, taken out: the same range when it holds
    /// no line feed, else the collapsed text in the diagram's derived bytes.
    static func collapsed(_ text: C4Text, in diagram: inout C4Diagram) -> C4Text {
        let holdsLineFeed = diagram.withBytes(of: text) { bytes in bytes.contains(MermaidByte.newline) }
        guard holdsLineFeed else { return text }
        return diagram.appendDerived(collapsed(diagram.text(text)).utf8)
    }

    /// Mermaid's `replace(/\n\s+/g, '\n')` on the text's UTF-16 code units.
    static func collapsed(_ text: String) -> String {
        let units = Array(text.utf16)
        var kept: [UInt16] = []
        kept.reserveCapacity(units.count)
        var index = 0
        while index < units.count {
            kept.append(units[index])
            if units[index] == C4Characters.lineFeed, index + 1 < units.count, C4Characters.isSpace(units[index + 1]) {
                index += 1
                while index < units.count, C4Characters.isSpace(units[index]) { index += 1 }
                continue
            }
            index += 1
        }
        return String(decoding: kept, as: UTF16.self)
    }
}
