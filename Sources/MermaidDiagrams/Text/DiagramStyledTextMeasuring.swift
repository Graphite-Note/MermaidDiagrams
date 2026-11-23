/**
 * File: DiagramStyledTextMeasuring.swift
 * --------------------------------------
 * Layer: Core
 * Description: Measures a piece of text in its emphasis added to a measurer's own (its bold, italic or monospaced font),
 *              each such font made once for the text being measured.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import CoreGraphics

/// A measurer that can measure in its font with an emphasis added: bold, italic, monospaced or several.
protocol DiagramTextStyleVariantMeasuring: DiagramTextMeasuring {
    /// This measurer's font and size with `style` added to its own emphasis.
    func adding(_ style: DiagramTextStyle) -> Self
}

extension CoreTextDiagramTextMeasurer: DiagramTextStyleVariantMeasuring {
    func adding(_ style: DiagramTextStyle) -> CoreTextDiagramTextMeasurer {
        CoreTextDiagramTextMeasurer(font: diagramFont, isBold: isBold || style.contains(.bold), isItalic: isItalic || style.contains(.italic),
                                    isMonospaced: isMonospaced || style.contains(.monospaced))
    }
}

/// A measurer and its fonts with emphasis added, each made the first time a piece in that emphasis is measured, as Pele
/// measures a span in its style (text/measurer.ts). A measurer that cannot add emphasis measures every piece in its own
/// font.
struct DiagramStyledMeasuring<Measurer: DiagramTextMeasuring> {
    let measurer: Measurer
    private var variants: [DiagramTextStyle: Measurer] = [:]

    init(_ measurer: Measurer) {
        self.measurer = measurer
    }

    /// The width of `text` in `style` added to the measurer's own.
    mutating func width(of text: String, style: DiagramTextStyle) -> CGFloat {
        guard !style.isEmpty else { return measurer.width(of: text) }
        if let variant = variants[style] { return variant.width(of: text) }
        guard let variantMaking = measurer as? any DiagramTextStyleVariantMeasuring, let variant = variantMaking.adding(style) as? Measurer else {
            return measurer.width(of: text)
        }
        variants[style] = variant
        return variant.width(of: text)
    }
}
