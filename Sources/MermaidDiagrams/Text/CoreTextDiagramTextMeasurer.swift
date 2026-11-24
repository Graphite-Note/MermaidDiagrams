/**
 * File: CoreTextDiagramTextMeasurer.swift
 * ---------------------------------------
 * Layer: Core
 * Description: Measures a line of text with Core Text in a diagram's font, regular, bold, italic or monospaced, as it is
 *              drawn, printable ASCII from a table of the font's advances, from a String or from its UTF-8 bytes; a
 *              value of a few numbers that names its font by its place in the font registry.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.8
 * Date: 24/11/2026
 */

import CoreGraphics
import CoreText
import Foundation

/// Measures text with Core Text, as it is drawn. Printable ASCII, most of a diagram's text, is measured from a table
/// of the font's advances read once per process (`DiagramFontFaceRegistry`); any other text goes through a Core Text
/// line, which finds fallback fonts for scripts and emoji the font lacks, laid out once per font and text
/// (`DiagramLineWidthCache`). The table leaves out kerning, which the shapes' padding absorbs. The measurer names its
/// font by an index, so copying it, as every layout and every text block does, retains nothing.
public struct CoreTextDiagramTextMeasurer: DiagramTextMeasuring, Sendable {
    public let fontSize: CGFloat
    public let lineHeight: CGFloat
    /// The font, its size and its emphasis (bold, italic, the system's monospaced font).
    let face: DiagramFontFace
    /// Line height as a multiple of the font size, Pele's.
    static let lineHeightRatio: CGFloat = 1.5

    public init(font diagramFont: DiagramFont) {
        self.init(font: diagramFont, isBold: false)
    }

    /// Measures in the bold of `diagramFont` when `isBold`, as a class's name is drawn, in its italic when `isItalic`,
    /// and in the system's monospaced font at its size when `isMonospaced` (a railroad diagram's terminals).
    init(font diagramFont: DiagramFont, isBold: Bool, isItalic: Bool = false, isMonospaced: Bool = false) {
        var style: DiagramTextStyle = []
        if isBold { style.insert(.bold) }
        if isItalic { style.insert(.italic) }
        if isMonospaced { style.insert(.monospaced) }
        self.init(face: DiagramFontFaceRegistry.shared.face(postScriptName: diagramFont.postScriptName, size: diagramFont.size, style: style))
    }

    init(face: DiagramFontFace) {
        self.face = face
        fontSize = face.name.size
        lineHeight = (face.name.size * Self.lineHeightRatio).rounded()
    }

    /// The font it was made from, to make it again at another size.
    var diagramFont: DiagramFont {
        DiagramFont(postScriptName: DiagramFontFaceRegistry.shared.postScriptName(ofFamily: face.name.family), size: fontSize)
    }

    var isBold: Bool { face.name.style.contains(.bold) }
    var isItalic: Bool { face.name.style.contains(.italic) }
    var isMonospaced: Bool { face.name.style.contains(.monospaced) }

    public func width(of text: String) -> CGFloat {
        if let width = text.utf8.withContiguousStorageIfAvailable({ bytes in face.width(ofUTF8: bytes) }) { return width }
        return Array(text.utf8).withUnsafeBufferPointer { bytes in face.width(ofUTF8: bytes) }
    }

    /// The advances `width(of:)` adds up for printable ASCII, to continue a width over more bytes; a font past the
    /// registry's room has none here, and its text is measured whole.
    var printableASCIIAdvances: DiagramFontAdvances? {
        face.advances
    }
}

extension CoreTextDiagramTextMeasurer: DiagramByteTextMeasuring {
    func width(ofUTF8 bytes: UnsafeBufferPointer<UInt8>, style: DiagramTextStyle) -> CGFloat {
        face.adding(style).width(ofUTF8: bytes)
    }

    func advances(of style: DiagramTextStyle) -> DiagramFontAdvances? {
        face.adding(style).advances
    }
}
