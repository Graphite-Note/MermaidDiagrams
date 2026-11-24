/**
 * File: DiagramStyledTextMeasuring.swift
 * --------------------------------------
 * Layer: Core
 * Description: Measures a piece of text in its emphasis added to a measurer's own (its bold, italic or monospaced font),
 *              each such font made once for the text being measured, and the advances Core Text's measurer adds up.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
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
        measurer(for: style).width(of: text)
    }

    /// The advances the measurer of `style` adds up for printable ASCII (`DiagramPrintableASCIIAdvances`): Core Text's
    /// measurer's; nil for any other measurer, whose widths are only of whole texts.
    mutating func printableASCIIAdvances(of style: DiagramTextStyle) -> DiagramPrintableASCIIAdvances? {
        (measurer(for: style) as? CoreTextDiagramTextMeasurer)?.printableASCIIAdvances
    }

    /// The measurer of `style` added to the measurer's own: its variant, made the first time, or the measurer itself
    /// where it cannot add emphasis.
    private mutating func measurer(for style: DiagramTextStyle) -> Measurer {
        guard !style.isEmpty else { return measurer }
        if let variant = variants[style] { return variant }
        guard let variantMaking = measurer as? any DiagramTextStyleVariantMeasuring, let variant = variantMaking.adding(style) as? Measurer else {
            return measurer
        }
        variants[style] = variant
        return variant
    }
}
