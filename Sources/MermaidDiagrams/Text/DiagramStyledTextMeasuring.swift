/**
 * File: DiagramStyledTextMeasuring.swift
 * --------------------------------------
 * Layer: Core
 * Description: Measures a piece of text in its emphasis added to a measurer's own (its bold, italic or monospaced font),
 *              each such font made once for the text being measured, and the advances Core Text's measurer adds up.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 24/11/2026
 */

import CoreGraphics

/// A measurer that can measure in its font with an emphasis added: bold, italic, monospaced or several.
protocol DiagramTextStyleVariantMeasuring: DiagramTextMeasuring {
    /// This measurer's font and size with `style` added to its own emphasis.
    func adding(_ style: DiagramTextStyle) -> Self
}

extension CoreTextDiagramTextMeasurer: DiagramTextStyleVariantMeasuring {
    func adding(_ style: DiagramTextStyle) -> CoreTextDiagramTextMeasurer {
        CoreTextDiagramTextMeasurer(face: face.adding(style))
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

    /// The advances the measurer of `style` adds up for printable ASCII (`DiagramFontAdvances`): Core Text's
    /// measurer's; nil for any other measurer, whose widths are only of whole texts.
    mutating func printableASCIIAdvances(of style: DiagramTextStyle) -> DiagramFontAdvances? {
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

/// A measurer and its fonts with emphasis added, measuring UTF-8 bytes: Core Text's measurer finds each emphasis's face
/// once, in a list of eight indexed by the emphasis, and measures the bytes as they are; any other measurer measures the
/// String the bytes make, in its variant (`DiagramStyledMeasuring`). Either way a width is the measurer's width of that
/// text.
struct DiagramStyledByteMeasuring<Measurer: DiagramTextMeasuring> {
    private var measuring: DiagramStyledMeasuring<Measurer>
    /// The faces of the eight emphases, Core Text's measurer's, each found the first time it is asked for.
    private var faces: InlineArray<8, DiagramFontFace>
    private var foundFaces: UInt8 = 0
    private let isCoreText: Bool

    init(_ measurer: Measurer) {
        measuring = DiagramStyledMeasuring(measurer)
        let face = (measurer as? CoreTextDiagramTextMeasurer)?.face
        isCoreText = face != nil
        faces = InlineArray(repeating: face ?? DiagramFontFace(index: .unregistered, name: DiagramFontFaceName(family: 0, size: 0, style: [])))
        foundFaces = 1
    }

    var measurer: Measurer { measuring.measurer }

    /// The width of `bytes` in `style` added to the measurer's own.
    @inline(__always)
    mutating func width(of bytes: UnsafeBufferPointer<UInt8>, style: DiagramTextStyle) -> CGFloat {
        if isCoreText { return face(style).width(ofUTF8: bytes) }
        return measuring.width(of: String(decoding: bytes, as: UTF8.self), style: style)
    }

    /// The advances the measurer of `style` adds up for printable ASCII: Core Text's measurer's, unless its face is past
    /// the registry's room; nil for any other measurer, whose widths are only of whole texts.
    @inline(__always)
    mutating func advances(of style: DiagramTextStyle) -> DiagramFontAdvances? {
        isCoreText ? face(style).advances : nil
    }

    @inline(__always)
    private mutating func face(_ style: DiagramTextStyle) -> DiagramFontFace {
        let index = Int(style.rawValue & 7)
        if foundFaces & (1 << index) == 0 {
            faces[index] = faces[0].adding(style)
            foundFaces |= 1 << index
        }
        return faces[index]
    }
}
