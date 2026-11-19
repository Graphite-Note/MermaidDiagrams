/**
 * File: TreemapClassStyle.swift
 * -----------------------------
 * Layer: Core
 * Description: Reads the declarations of a treemap's `classDef` as Mermaid's treemap and Pele read them.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
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
        let separated = styleText.replacingOccurrences(of: "\\,", with: marker).replacingOccurrences(of: ",", with: ";")
            .replacingOccurrences(of: marker, with: ",")
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
            let read = DiagramElementStyle.reading(String(declaration))
            style = style.overridden(by: read.style)
            if read.hasUnappliedDeclaration { unappliedCount += 1 }
        }
        return (style, textStyle, unappliedCount)
    }
}
