/**
 * File: C4TextLabel.swift
 * -----------------------
 * Layer: Core
 * Description: The lines Pele's layoutLabel gives a C4 text of nothing but breaks, and the measurers of a C4
 *              diagram's text: names and the title in bold, the rest at thirteen sixteenths of the size, a shape's kind
 *              a point smaller, a relation's technology in italic.
 *
 * Authors: Bahey Shalash
 * Version: 0.5
 * Date: 26/11/2026
 */

import CoreGraphics

/// What Pele's `layoutLabel` gives a text that measures to no line, white space or breaks alone: its lines with
/// nothing on them, which still take their height.
enum C4TextLabel {
    /// One empty line for each part of `label` between breaks, or one for a label of none.
    static func emptyLines(of label: DiagramLabel, measurer: some DiagramTextMeasuring) -> DiagramTextBlock {
        let lines = label.lineCount == 0 ? [""] : label.lines
        return DiagramTextBlock(lines: lines, lineWidths: lines.map { _ in CGFloat(0) }, fontSize: measurer.fontSize,
                                lineHeight: DiagramTextBlock.lineHeight(lineCount: lines.count, measurer: measurer))
    }
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
