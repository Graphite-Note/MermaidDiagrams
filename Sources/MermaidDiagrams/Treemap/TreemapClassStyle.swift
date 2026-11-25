/**
 * File: TreemapClassStyle.swift
 * -----------------------------
 * Layer: Core
 * Description: Reads the declarations of a treemap's `classDef` as Mermaid's treemap and Pele read them.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 25/11/2026
 */

import Foundation

/// The declarations of a treemap's `classDef`: every comma separates two declarations, as does `;`, unless the comma is
/// escaped (`\,`), as Mermaid's treemap database splits them; each is read as a node's style (`DiagramElementStyle`), or
/// as its text's size, weight and slant (`TreemapClassTextStyle`).
enum TreemapClassStyle {
    /// The style the text sets, what it sets of the text, and how many of its declarations set something this package does
    /// not draw (an opacity, a font family) or are no declaration.
    static func reading(_ styleText: String) -> (style: DiagramElementStyle, textStyle: TreemapClassTextStyle, unappliedCount: Int) {
        let marker = "\u{0}"
        // Without a comma or the marker the replacements change nothing.
        let separated = !styleText.utf8.contains(where: { byte in byte == UInt8(ascii: ",") || byte == 0 }) ? styleText
            : styleText.replacingOccurrences(of: "\\,", with: marker).replacingOccurrences(of: ",", with: ";").replacingOccurrences(of: marker, with: ",")
        var style = DiagramElementStyle()
        var textStyle = TreemapClassTextStyle()
        var unappliedCount = 0
        for declaration in separated.split(separator: ";", omittingEmptySubsequences: true) {
            if let colon = declaration.firstIndex(of: ":"),
               let isApplied = textStyle.read(property: declaration[..<colon].trimmingCharacters(in: .whitespaces).lowercased(),
                                              value: String(declaration[declaration.index(after: colon)...])) {
                if !isApplied { unappliedCount += 1 }
                continue
            }
            if let colon = declaration.firstIndex(of: ":"), declaration[..<colon].trimmingCharacters(in: .whitespaces).lowercased() == "fill" {
                textStyle.readFill(value: String(declaration[declaration.index(after: colon)...]))
            }
            let read = DiagramElementStyle.reading(String(declaration))
            style = style.overridden(by: read.style)
            if read.hasUnappliedDeclaration { unappliedCount += 1 }
        }
        return (style, textStyle, unappliedCount)
    }
}
