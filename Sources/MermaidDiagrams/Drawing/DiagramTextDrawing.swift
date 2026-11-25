/**
 * File: DiagramTextDrawing.swift
 * ------------------------------
 * Layer: Core
 * Description: Draws a diagram's text blocks with Core Text, regular, bold, italic or monospaced, each run of a line in
 *              its emphasis, into a context whose y runs down: each line's or run's Core Foundation string is made straight
 *              from the bytes its block's storage keeps (a leading U+FEFF kept), its attributes once per font and color.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.9
 * Date: 24/11/2026
 */

import CoreGraphics
import CoreText
import Foundation

/// Draws text blocks with Core Text into a context whose y runs down. The fonts for one drawing are made once, and the
/// attributes of each font and color once: a line's string is made from its UTF-8 bytes where its block keeps them, with no
/// Swift String, and laid out by Core Text as an attributed string of those attributes, the same line 0.7.0 laid out from
/// a String (`DiagramSceneTextDrawingTests` compares their pixels).
struct DiagramTextDrawing {
    /// Where a line's baseline sits below the middle of its line, as a fraction of the font size: Pele's.
    static let baselineShiftRatio: CGFloat = 0.35

    /// A font of one drawing: its size, whether it is the bold or the italic of the diagram's font, and whether it is the
    /// system's monospaced font instead.
    private struct FontKey: Hashable {
        let size: CGFloat
        let isBold: Bool
        let isItalic: Bool
        var isMonospaced = false
    }

    private let font: DiagramFont
    private var fontsByKey: [FontKey: CTFont] = [:]
    /// The attributes of each font and color drawn so far, the color compared by identity: a drawing's paints give the
    /// same color object each time (`DiagramPaintColors`).
    private var attributesMade: [(font: CTFont, color: CGColor, attributes: CFDictionary)] = []

    init(font: DiagramFont) {
        self.font = font
    }

    /// Draws each line centered on the block's center, one line height below the last, over its outline (the glyphs'
    /// edges stroked in a color with round joins) when it has one. A line's runs are drawn one after the other from the
    /// line's start, each in its emphasis added to the text's own.
    mutating func draw(_ block: DiagramTextBlock, color: CGColor, isBold: Bool = false, isItalic: Bool = false, isMonospaced: Bool = false,
                       outline: (color: CGColor, lineWidth: CGFloat)? = nil, in context: CGContext) {
        guard block.lineCount > 0 else { return }
        let key = FontKey(size: block.fontSize, isBold: isBold, isItalic: isItalic, isMonospaced: isMonospaced)
        context.saveGState()
        // Core Text draws glyphs upright in a context whose y runs up; this one's runs down.
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        if let outline {
            context.setTextDrawingMode(.stroke)
            context.setStrokeColor(outline.color)
            context.setLineWidth(outline.lineWidth)
            context.setLineJoin(.round)
            drawLines(of: block, key: key, color: color, in: context)
            context.setTextDrawingMode(.fill)
        }
        drawLines(of: block, key: key, color: color, in: context)
        context.restoreGState()
    }

    private mutating func drawLines(of block: DiagramTextBlock, key: FontKey, color: CGColor, in context: CGContext) {
        let top = block.center.y - block.size.height / 2
        for index in 0..<block.lineCount {
            let baseline = top + (CGFloat(index) + 0.5) * block.lineHeight + block.fontSize * Self.baselineShiftRatio
            var start = block.center.x - block.lineWidth(at: index) / 2
            guard block.record.hasEmphasis else {
                let attributes = self.attributes(font: coreTextFont(key), color: color)
                block.withUTF8(ofLine: index) { bytes in draw(bytes, attributes: attributes, at: CGPoint(x: start, y: baseline), in: context) }
                continue
            }
            block.forEachRun(ofLine: index) { bytes, style, width in
                let runKey = FontKey(size: key.size, isBold: key.isBold || style.contains(.bold), isItalic: key.isItalic || style.contains(.italic),
                                     isMonospaced: key.isMonospaced || style.contains(.monospaced))
                draw(bytes, attributes: attributes(font: coreTextFont(runKey), color: color), at: CGPoint(x: start, y: baseline), in: context)
                start += width
            }
        }
    }

    /// Draws the text of `bytes`, UTF-8, with its baseline starting at `baselineStart`.
    private func draw(_ bytes: UnsafeBufferPointer<UInt8>, attributes: CFDictionary, at baselineStart: CGPoint, in context: CGContext) {
        guard let attributed = CFAttributedStringCreate(kCFAllocatorDefault, Self.coreFoundationString(of: bytes), attributes) else { return }
        context.textPosition = baselineStart
        CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
    }

    /// The characters of `bytes`, UTF-8, as a Core Foundation string, made straight from the bytes. `CFStringCreateWithBytes`
    /// takes a leading U+FEFF for a byte order mark and leaves it out, so a text that starts with one, and bytes it does
    /// not take as UTF-8, are made as a String makes them: every character 0.7.0 drew is kept.
    static func coreFoundationString(of bytes: UnsafeBufferPointer<UInt8>) -> CFString {
        if let start = bytes.baseAddress, !startsWithByteOrderMark(bytes),
           let made = CFStringCreateWithBytes(kCFAllocatorDefault, start, bytes.count, CFStringBuiltInEncodings.UTF8.rawValue, false) {
            return made
        }
        return String(decoding: bytes, as: UTF8.self) as CFString
    }

    /// Whether `bytes` start with U+FEFF in UTF-8 (`EF BB BF`).
    @inline(__always)
    private static func startsWithByteOrderMark(_ bytes: UnsafeBufferPointer<UInt8>) -> Bool {
        bytes.count >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF
    }

    /// The attributes of text in `font` and `color`, made the first time they are drawn; past `largestKeptAttributeCount`
    /// pairs, which a scene of a color per text could reach, the others are made each time, so that the search stays short.
    private mutating func attributes(font: CTFont, color: CGColor) -> CFDictionary {
        for made in attributesMade where made.font === font && made.color === color { return made.attributes }
        let attributes = [kCTFontAttributeName as String: font, kCTForegroundColorAttributeName as String: color] as CFDictionary
        if attributesMade.count < Self.largestKeptAttributeCount { attributesMade.append((font, color, attributes)) }
        return attributes
    }

    /// The most pairs of a font and a color whose attributes one drawing keeps.
    private static let largestKeptAttributeCount = 32

    /// The font at the key's size, in its bold or italic (or both) when it has them, else in the regular font.
    private mutating func coreTextFont(_ key: FontKey) -> CTFont {
        if let made = fontsByKey[key] { return made }
        let made = DiagramFontFaceRegistry.shared.coreTextFont(of: CoreTextFontFaceKey(postScriptName: font.postScriptName, size: key.size,
                                                                                       isBold: key.isBold, isItalic: key.isItalic,
                                                                                       isMonospaced: key.isMonospaced))
        fontsByKey[key] = made
        return made
    }
}
