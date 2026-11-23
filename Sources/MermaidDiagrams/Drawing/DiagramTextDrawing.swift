/**
 * File: DiagramTextDrawing.swift
 * ------------------------------
 * Layer: Core
 * Description: Draws a diagram's text blocks with Core Text, regular, bold, italic or monospaced, each run of a line in
 *              its emphasis, into a context whose y runs down.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.4
 * Date: 23/11/2026
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
    /// edges stroked in a color with round joins) when it has one. A line's runs are drawn one after the other from the
    /// line's start, each in its emphasis added to the text's own.
    mutating func draw(_ block: DiagramTextBlock, color: CGColor, isBold: Bool = false, isItalic: Bool = false, isMonospaced: Bool = false,
                       outline: (color: CGColor, lineWidth: CGFloat)? = nil, in context: CGContext) {
        guard !block.lines.isEmpty else { return }
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
        for (index, line) in block.lines.enumerated() {
            let baseline = top + (CGFloat(index) + 0.5) * block.lineHeight + block.fontSize * Self.baselineShiftRatio
            var start = block.center.x - block.lineWidths[index] / 2
            guard let runs = block.lineRuns?[index] else {
                draw(line, font: coreTextFont(key), color: color, at: CGPoint(x: start, y: baseline), in: context)
                continue
            }
            for run in runs {
                let runKey = FontKey(size: key.size, isBold: key.isBold || run.style.contains(.bold), isItalic: key.isItalic || run.style.contains(.italic),
                                     isMonospaced: key.isMonospaced || run.style.contains(.monospaced))
                draw(run.text, font: coreTextFont(runKey), color: color, at: CGPoint(x: start, y: baseline), in: context)
                start += run.width
            }
        }
    }

    private func draw(_ text: String, font: CTFont, color: CGColor, at baselineStart: CGPoint, in context: CGContext) {
        let attributes: [NSAttributedString.Key: Any] = [
            kCTFontAttributeName as NSAttributedString.Key: font,
            kCTForegroundColorAttributeName as NSAttributedString.Key: color,
        ]
        let coreTextLine = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        context.textPosition = baselineStart
        CTLineDraw(coreTextLine, context)
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
