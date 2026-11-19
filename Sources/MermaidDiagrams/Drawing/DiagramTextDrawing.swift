/**
 * File: DiagramTextDrawing.swift
 * ------------------------------
 * Layer: Core
 * Description: Draws a diagram's text blocks with Core Text, regular, bold, italic or monospaced, into a context whose y
 *              runs down.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.3
 * Date: 19/11/2026
 */

import CoreGraphics
import CoreText
import Foundation

/// Draws text blocks with Core Text into a context whose y runs down. The fonts for one drawing are made once.
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

    init(font: DiagramFont) {
        self.font = font
    }

    /// Draws each line centered on the block's center, one line height below the last, over its outline (the glyphs'
    /// edges stroked in a color with round joins) when it has one.
    mutating func draw(_ block: DiagramTextBlock, color: CGColor, isBold: Bool = false, isItalic: Bool = false, isMonospaced: Bool = false,
                       outline: (color: CGColor, lineWidth: CGFloat)? = nil, in context: CGContext) {
        guard !block.lines.isEmpty else { return }
        let coreTextFont = coreTextFont(FontKey(size: block.fontSize, isBold: isBold, isItalic: isItalic, isMonospaced: isMonospaced))
        let attributes: [NSAttributedString.Key: Any] = [
            kCTFontAttributeName as NSAttributedString.Key: coreTextFont,
            kCTForegroundColorAttributeName as NSAttributedString.Key: color,
        ]
        let top = block.center.y - block.size.height / 2
        context.saveGState()
        // Core Text draws glyphs upright in a context whose y runs up; this one's runs down.
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        if let outline {
            context.setTextDrawingMode(.stroke)
            context.setStrokeColor(outline.color)
            context.setLineWidth(outline.lineWidth)
            context.setLineJoin(.round)
            Self.drawLines(of: block, attributes: attributes, top: top, in: context)
            context.setTextDrawingMode(.fill)
        }
        Self.drawLines(of: block, attributes: attributes, top: top, in: context)
        context.restoreGState()
    }

    private static func drawLines(of block: DiagramTextBlock, attributes: [NSAttributedString.Key: Any], top: CGFloat, in context: CGContext) {
        for (index, line) in block.lines.enumerated() {
            let coreTextLine = CTLineCreateWithAttributedString(NSAttributedString(string: line, attributes: attributes))
            let baseline = top + (CGFloat(index) + 0.5) * block.lineHeight + block.fontSize * baselineShiftRatio
            context.textPosition = CGPoint(x: block.center.x - block.lineWidths[index] / 2, y: baseline)
            CTLineDraw(coreTextLine, context)
        }
    }

    /// The font at the key's size, in its bold or italic (or both) when it has them, else in the regular font.
    private mutating func coreTextFont(_ key: FontKey) -> CTFont {
        if let made = fontsByKey[key] { return made }
        let regularKey = FontKey(size: key.size, isBold: false, isItalic: false, isMonospaced: key.isMonospaced)
        let resized = font.resized(to: key.size)
        let regular = fontsByKey[regularKey] ?? (key.isMonospaced ? resized.makeMonospacedCoreTextFont() : resized.makeCoreTextFont())
        fontsByKey[regularKey] = regular
        var traits: CTFontSymbolicTraits = []
        if key.isBold { traits.insert(.traitBold) }
        if key.isItalic { traits.insert(.traitItalic) }
        guard !traits.isEmpty else { return regular }
        let made = CTFontCreateCopyWithSymbolicTraits(regular, key.size, nil, traits, traits) ?? regular
        fontsByKey[key] = made
        return made
    }
}
