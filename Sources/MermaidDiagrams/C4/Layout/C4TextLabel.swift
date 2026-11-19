/**
 * File: C4TextLabel.swift
 * -----------------------
 * Layer: Core
 * Description: Measures a C4 text as Pele's layoutLabel does, and the measurers of a C4 diagram's text: names and the
 *              title in bold, the rest at thirteen sixteenths of the size, a shape's kind a point smaller, a relation's
 *              technology in italic.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// A measured text as Pele's `layoutLabel` gives it: nothing for no text or an empty one; else its lines, broken at
/// `<br>`, a line break or a written `\n`, its tags dropped and its entity codes read, each wrapped at spaces past
/// `maximumWidth`. Lines of a text of more than one sit 1.3 times the size apart, rounded, where one line takes 1.5.
enum C4TextLabel {
    static func block(_ text: String?, measurer: some DiagramTextMeasuring, maximumWidth: CGFloat) -> DiagramTextBlock? {
        guard let text, !text.isEmpty else { return nil }
        let written = text.contains("\\n") ? text.replacingOccurrences(of: "\\n", with: "\n") : text
        let decoded = DiagramLabelDecoder.label(from: written, form: .plain)
        let label = DiagramLabel(lines: decoded.lines.map(C4Characters.trimmed))
        let wrapped = DiagramTextBlock(label: label, measurer: measurer, maximumWidth: maximumWidth)
        // Lines with nothing on them still take their height, as Pele lays out each part between breaks.
        let lines = wrapped.lines.isEmpty ? (label.lines.isEmpty ? [""] : label.lines) : wrapped.lines
        let widths = wrapped.lines.isEmpty ? lines.map { _ in CGFloat(0) } : wrapped.lineWidths
        let lineHeight = lines.count > 1 ? (measurer.fontSize * wrappedLineHeightRatio).rounded() : measurer.lineHeight
        return DiagramTextBlock(lines: lines, lineWidths: widths, fontSize: measurer.fontSize, lineHeight: lineHeight)
    }

    /// Pele's `WRAPPED_LINE_HEIGHT`.
    static let wrappedLineHeightRatio: CGFloat = 1.3
}

extension DiagramTextBlock? {
    /// The block's width and height, zero for none.
    var measuredWidth: CGFloat { self?.size.width ?? 0 }
    var measuredHeight: CGFloat { self?.size.height ?? 0 }
}

/// The measurers of a C4 diagram's text, Pele's sizes: the size in bold for names, headings and the title; Pele's
/// `small`, thirteen sixteenths of the size rounded, for technologies, descriptions, types and relations' labels; a point
/// less for a shape's kind; `small` in italic for a relation's technology.
struct C4Measurers<Measurer: DiagramTextMeasuring> {
    let name: Measurer
    let small: Measurer
    let smallest: Measurer
    let italicSmall: Measurer
}

extension C4Measurers where Measurer == CoreTextDiagramTextMeasurer {
    init(typography: DiagramTypography) {
        let small = typography.rowText
        let smallestSize = small.fontSize - 1
        self.init(name: typography.boldNodeText, small: small,
                  smallest: typography.axisText.fontSize == smallestSize ? typography.axisText : small.resized(to: smallestSize),
                  italicSmall: typography.planeMapText.italicRowText)
    }
}
