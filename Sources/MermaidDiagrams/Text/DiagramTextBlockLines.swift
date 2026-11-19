/**
 * File: DiagramTextBlockLines.swift
 * ---------------------------------
 * Layer: Core
 * Description: A text block's lines as blocks of one line each, so that lines can be left aligned.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

extension DiagramTextBlock {
    /// The block's lines as one-line blocks that start where the block's widest line starts, each line's left end at the
    /// block's left end instead of its middle at the block's middle: how an outline's text is aligned. A block of one line,
    /// or none, is returned as it is, since its line is already where the block's left end is.
    func leftAlignedLines() -> [DiagramTextBlock] {
        guard lines.count > 1 else { return [self] }
        let left = center.x - size.width / 2
        let top = center.y - size.height / 2
        return lines.indices.map { index in
            DiagramTextBlock(oneLine: lines[index], width: lineWidths[index], fontSize: fontSize, lineHeight: lineHeight,
                             center: CGPoint(x: left + lineWidths[index] / 2, y: top + (CGFloat(index) + 0.5) * lineHeight))
        }
    }

    private init(oneLine line: String, width: CGFloat, fontSize: CGFloat, lineHeight: CGFloat, center: CGPoint) {
        self.lines = [line]
        self.lineWidths = [width]
        self.fontSize = fontSize
        self.lineHeight = lineHeight
        self.center = center
    }
}
