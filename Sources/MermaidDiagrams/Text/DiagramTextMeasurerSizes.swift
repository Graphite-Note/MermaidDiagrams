/**
 * File: DiagramTextMeasurerSizes.swift
 * ------------------------------------
 * Layer: Core
 * Description: Measures text at font sizes other than a measurer's own, in the font at that size where the measurer can make
 *              it, as the text is drawn.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// A measurer that can measure in its font at another size. Core Text draws small text wider than its size in proportion
/// (the system font tracks it out: 9.5 % wider at 8 points than 16 points' widths scaled down), so text fitted to a box is
/// measured at the size it is drawn at.
protocol DiagramTextResizableMeasuring: DiagramTextMeasuring {
    /// This measurer's font, of the same face, weight and slant, at `fontSize`.
    func resized(to fontSize: CGFloat) -> Self
}

extension CoreTextDiagramTextMeasurer: DiagramTextResizableMeasuring {
    func resized(to fontSize: CGFloat) -> CoreTextDiagramTextMeasurer {
        CoreTextDiagramTextMeasurer(font: diagramFont.resized(to: fontSize), isBold: isBold, isItalic: isItalic)
    }
}

/// A measurer and the copies of it at the other sizes text is measured at, each made once. A measurer that cannot be resized
/// gives the width at another size in proportion to its own.
struct DiagramTextMeasurerSizes<Measurer: DiagramTextMeasuring> {
    let measurer: Measurer
    private var resized: [CGFloat: Measurer] = [:]

    /// The most sizes kept: a class may set any size, and past this a size is measured without being kept.
    private static var largestKeptSizeCount: Int { 64 }

    init(_ measurer: Measurer) {
        self.measurer = measurer
    }

    /// The width of `text` at `fontSize`.
    mutating func width(of text: String, atFontSize fontSize: CGFloat) -> CGFloat {
        guard measurer.fontSize > 0, fontSize > 0 else { return 0 }
        if fontSize == measurer.fontSize { return measurer.width(of: text) }
        if let known = resized[fontSize] { return known.width(of: text) }
        guard let resizable = measurer as? any DiagramTextResizableMeasuring, fontSize.isFinite,
              let copy = resizable.resized(to: fontSize) as? Measurer else {
            return measurer.width(of: text) * fontSize / measurer.fontSize
        }
        if resized.count < Self.largestKeptSizeCount { resized[fontSize] = copy }
        return copy.width(of: text)
    }

    /// One line of `text` at `fontSize`, its center at the origin.
    mutating func block(of text: String, fontSize: CGFloat) -> DiagramTextBlock {
        DiagramTextBlock(line: text, width: width(of: text, atFontSize: fontSize), fontSize: fontSize)
    }
}
