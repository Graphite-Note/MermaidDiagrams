/**
 * File: TreemapClassStyle.swift
 * -----------------------------
 * Layer: Core
 * Description: Reads the declarations of a treemap's `classDef` as Mermaid's treemap and Pele read them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import Foundation

/// The declarations of a treemap's `classDef`: every comma separates two declarations, as does `;`, unless the comma is
/// escaped (`\,`), as Mermaid's treemap database splits them; each is read as a node's style (`DiagramElementStyle`).
enum TreemapClassStyle {
    /// The style the text sets and how many of its declarations set something this package does not draw (a font size, an
    /// opacity) or are no declaration.
    static func reading(_ styleText: String) -> (style: DiagramElementStyle, unappliedCount: Int) {
        let marker = "\u{0}"
        let separated = styleText.replacingOccurrences(of: "\\,", with: marker).replacingOccurrences(of: ",", with: ";")
            .replacingOccurrences(of: marker, with: ",")
        var style = DiagramElementStyle()
        var unappliedCount = 0
        for declaration in separated.split(separator: ";", omittingEmptySubsequences: true) {
            let read = DiagramElementStyle.reading(String(declaration))
            style = style.overridden(by: read.style)
            if read.hasUnappliedDeclaration { unappliedCount += 1 }
        }
        return (style, unappliedCount)
    }
}
