/**
 * File: CoreTextFontFaces.swift
 * -----------------------------
 * Layer: Core
 * Description: Makes each Core Text font a diagram measures or draws in, with the advances of its printable ASCII, once
 *              per process, so that a layout or a painting that asks for a size again does not read the font again.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

import CoreGraphics
import CoreText
import Foundation

/// A font a diagram's text is measured or drawn in: the diagram's font, its size, its bold or italic, or the system's
/// monospaced font at that size.
struct CoreTextFontFaceKey: Hashable {
    let postScriptName: String?
    let size: CGFloat
    let isBold: Bool
    let isItalic: Bool
    let isMonospaced: Bool
}

/// A Core Text font, its key, and the advances of the characters from space (32) to tilde (126) in it; made once per key
/// and shared, never changed.
final class CoreTextFontFace {
    let key: CoreTextFontFaceKey
    let font: CTFont
    let printableASCIIAdvances: [CGFloat]

    init(key: CoreTextFontFaceKey, font: CTFont, printableASCIIAdvances: [CGFloat]) {
        self.key = key
        self.font = font
        self.printableASCIIAdvances = printableASCIIAdvances
    }
}

/// The fonts made so far in this process. Making a Core Text font and reading its advances costs more than laying out a
/// small diagram (a treemap that measured each leaf's value at its fitted size made a font per text), and a font for one
/// key is always the same, so each is made once. Past `largestKeptFaceCount` keys (a diagram's classes may set any size)
/// a font is made without being kept.
final class CoreTextFontFaces: @unchecked Sendable {
    static let shared = CoreTextFontFaces()

    static let firstPrintableASCII: UInt8 = 32
    static let lastPrintableASCII: UInt8 = 126
    private static let largestKeptFaceCount = 256

    /// The most line widths kept, and the longest text kept, in UTF-8 bytes: past the count every width is let go, so that
    /// text of every kind keeps at most about a megabyte.
    private static let largestKeptWidthCount = 4_096
    private static let longestKeptTextByteCount = 256

    private let lock = NSLock()
    private var facesByKey: [CoreTextFontFaceKey: CoreTextFontFace] = [:]
    private var lineWidthsByText: [LineWidthKey: CGFloat] = [:]

    private struct LineWidthKey: Hashable {
        let face: CoreTextFontFaceKey
        let text: String
    }

    /// The face of `key`, made the first time it is asked for.
    func face(_ key: CoreTextFontFaceKey) -> CoreTextFontFace {
        lock.lock()
        let known = facesByKey[key]
        lock.unlock()
        if let known { return known }
        let made = Self.makeFace(key)
        lock.lock()
        if facesByKey.count < Self.largestKeptFaceCount { facesByKey[key] = made }
        lock.unlock()
        return made
    }

    /// The width of a Core Text line of `text` in the face of `key`, laid out the first time it is asked for: text beyond
    /// printable ASCII, whose fallback fonts Core Text finds for each line it makes (a tree view's box drawing, a C4
    /// diagram's guillemets), costs microseconds a line.
    func lineWidth(of text: String, in face: CoreTextFontFace) -> CGFloat {
        let font = face.font
        guard text.utf8.count <= Self.longestKeptTextByteCount else { return Self.layOutLineWidth(of: text, font: font) }
        let widthKey = LineWidthKey(face: face.key, text: text)
        lock.lock()
        let known = lineWidthsByText[widthKey]
        lock.unlock()
        if let known { return known }
        let width = Self.layOutLineWidth(of: text, font: font)
        lock.lock()
        if lineWidthsByText.count >= Self.largestKeptWidthCount { lineWidthsByText.removeAll(keepingCapacity: true) }
        lineWidthsByText[widthKey] = width
        lock.unlock()
        return width
    }

    private static func layOutLineWidth(of text: String, font: CTFont) -> CGFloat {
        let attributes = [kCTFontAttributeName as NSAttributedString.Key: font]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    private static func makeFace(_ key: CoreTextFontFaceKey) -> CoreTextFontFace {
        let diagramFont = DiagramFont(postScriptName: key.postScriptName, size: key.size)
        let regular = key.isMonospaced ? diagramFont.makeMonospacedCoreTextFont() : diagramFont.makeCoreTextFont()
        var traits: CTFontSymbolicTraits = []
        if key.isBold { traits.insert(.traitBold) }
        if key.isItalic { traits.insert(.traitItalic) }
        let font = traits.isEmpty ? regular : CTFontCreateCopyWithSymbolicTraits(regular, key.size, nil, traits, traits) ?? regular
        let characters = (firstPrintableASCII...lastPrintableASCII).map { byte in UniChar(byte) }
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        var advances = [CGSize](repeating: .zero, count: characters.count)
        CTFontGetGlyphsForCharacters(font, characters, &glyphs, characters.count)
        CTFontGetAdvancesForGlyphs(font, .horizontal, glyphs, &advances, glyphs.count)
        return CoreTextFontFace(key: key, font: font, printableASCIIAdvances: advances.map(\.width))
    }
}
