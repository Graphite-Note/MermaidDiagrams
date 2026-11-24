/**
 * File: CoreTextDiagramTextMeasurer.swift
 * ---------------------------------------
 * Layer: Core
 * Description: Measures a line of text with Core Text in a diagram's font, regular, bold, italic or monospaced, as it is
 *              drawn, printable ASCII from a table of the font's advances, which wrapping continues over the bytes of
 *              the pieces it joins.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.7
 * Date: 23/11/2026
 */

import CoreGraphics
import CoreText
import Foundation

/// Measures text with Core Text, as it is drawn. Printable ASCII, most of a diagram's text, is measured from a table
/// of the font's advances read once per process (`CoreTextFontFaces`); any other text goes through a Core Text line,
/// which finds fallback fonts for scripts and emoji the font lacks, laid out once per font and text. The table leaves
/// out kerning, which the shapes' padding absorbs.
public struct CoreTextDiagramTextMeasurer: DiagramTextMeasuring {
    public let fontSize: CGFloat
    public let lineHeight: CGFloat
    /// The font and the advances of its printable ASCII, behind one reference, so that copying a measurer, as every layout
    /// and every text block does, retains one thing.
    private let face: CoreTextFontFace
    /// The font it was made from, and whether it measures its bold, its italic or the system's monospaced font, so that it
    /// can be made again at another size.
    let diagramFont: DiagramFont
    let isBold: Bool
    let isItalic: Bool
    let isMonospaced: Bool
    /// Line height as a multiple of the font size, Pele's.
    static let lineHeightRatio: CGFloat = 1.5
    private static let firstPrintableASCII = CoreTextFontFaces.firstPrintableASCII
    private static let lastPrintableASCII = CoreTextFontFaces.lastPrintableASCII

    public init(font diagramFont: DiagramFont) {
        self.init(font: diagramFont, isBold: false)
    }

    /// Measures in the bold of `diagramFont` when `isBold`, as a class's name is drawn, in its italic when `isItalic`,
    /// and in the system's monospaced font at its size when `isMonospaced` (a railroad diagram's terminals).
    init(font diagramFont: DiagramFont, isBold: Bool, isItalic: Bool = false, isMonospaced: Bool = false) {
        face = CoreTextFontFaces.shared.face(CoreTextFontFaceKey(postScriptName: diagramFont.postScriptName, size: diagramFont.size, isBold: isBold,
                                                                isItalic: isItalic, isMonospaced: isMonospaced))
        self.diagramFont = diagramFont
        self.isBold = isBold
        self.isItalic = isItalic
        self.isMonospaced = isMonospaced
        fontSize = diagramFont.size
        lineHeight = (diagramFont.size * Self.lineHeightRatio).rounded()
    }

    public func width(of text: String) -> CGFloat {
        var width: CGFloat = 0
        let printableASCIIAdvances = face.printableASCIIAdvances
        for byte in text.utf8 {
            guard byte >= Self.firstPrintableASCII, byte <= Self.lastPrintableASCII else { return lineWidth(of: text) }
            width += printableASCIIAdvances[Int(byte - Self.firstPrintableASCII)]
        }
        return width
    }

    /// The advances `width(of:)` adds up for printable ASCII, to continue a width over more bytes.
    var printableASCIIAdvances: DiagramPrintableASCIIAdvances {
        DiagramPrintableASCIIAdvances(advances: face.printableASCIIAdvances)
    }

    private func lineWidth(of text: String) -> CGFloat {
        CoreTextFontFaces.shared.lineWidth(of: text, in: face)
    }
}

/// The advances of a Core Text font's printable ASCII, space (32) to tilde (126), as `CoreTextDiagramTextMeasurer`
/// adds them up: from the first byte, each byte's advance added to the width before it. A width so added up for a text
/// can be continued over the bytes joined to it, which gives the width of the joined text to the bit; widths added up
/// apart and then added together round differently.
struct DiagramPrintableASCIIAdvances {
    let advances: [CGFloat]

    static func isPrintable(_ byte: UInt8) -> Bool {
        byte >= CoreTextFontFaces.firstPrintableASCII && byte <= CoreTextFontFaces.lastPrintableASCII
    }

    /// `width` with each byte's advance added, in order; every byte is printable.
    func width<Bytes: Sequence<UInt8>>(continuing width: CGFloat, over bytes: Bytes) -> CGFloat {
        var width = width
        for byte in bytes { width += advances[Int(byte - CoreTextFontFaces.firstPrintableASCII)] }
        return width
    }
}
