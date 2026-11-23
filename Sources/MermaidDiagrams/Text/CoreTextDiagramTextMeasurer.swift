/**
 * File: CoreTextDiagramTextMeasurer.swift
 * ---------------------------------------
 * Layer: Core
 * Description: Measures a line of text with Core Text in a diagram's font, regular, bold, italic or monospaced, as it is
 *              drawn, printable ASCII from a table of the font's advances.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.4
 * Date: 23/11/2026
 */

import CoreGraphics
import CoreText
import Foundation

/// Measures text with Core Text, as it is drawn. Printable ASCII, most of a diagram's text, is measured from a table
/// of the font's advances read once per process (`CoreTextFontFaces`); any other text goes through a Core Text line, which finds fallback fonts for
/// scripts and emoji the font lacks. The table leaves out kerning, which the shapes' padding absorbs.
public struct CoreTextDiagramTextMeasurer: DiagramTextMeasuring {
    public let fontSize: CGFloat
    public let lineHeight: CGFloat
    private let font: CTFont
    /// The font it was made from, and whether it measures its bold, its italic or the system's monospaced font, so that it
    /// can be made again at another size.
    let diagramFont: DiagramFont
    let isBold: Bool
    let isItalic: Bool
    let isMonospaced: Bool
    /// Advances of the characters from space (32) to tilde (126).
    private let printableASCIIAdvances: [CGFloat]

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
        let face = CoreTextFontFaces.shared.face(CoreTextFontFaceKey(postScriptName: diagramFont.postScriptName, size: diagramFont.size, isBold: isBold,
                                                                     isItalic: isItalic, isMonospaced: isMonospaced))
        font = face.font
        self.diagramFont = diagramFont
        self.isBold = isBold
        self.isItalic = isItalic
        self.isMonospaced = isMonospaced
        fontSize = diagramFont.size
        lineHeight = (diagramFont.size * Self.lineHeightRatio).rounded()
        printableASCIIAdvances = face.printableASCIIAdvances
    }

    public func width(of text: String) -> CGFloat {
        var width: CGFloat = 0
        for byte in text.utf8 {
            guard byte >= Self.firstPrintableASCII, byte <= Self.lastPrintableASCII else { return lineWidth(of: text) }
            width += printableASCIIAdvances[Int(byte - Self.firstPrintableASCII)]
        }
        return width
    }

    private func lineWidth(of text: String) -> CGFloat {
        let attributes = [kCTFontAttributeName as NSAttributedString.Key: font]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }
}
