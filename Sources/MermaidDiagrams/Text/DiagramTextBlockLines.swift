/**
 * File: DiagramTextBlockLines.swift
 * ---------------------------------
 * Layer: Core
 * Description: A text block's lines as blocks of one line each, so that lines can be left aligned.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 24/11/2026
 */

import CoreGraphics

extension DiagramTextBlock {
    /// The block's lines as one-line blocks that start where the block's widest line starts, each line's left end at the
    /// block's left end instead of its middle at the block's middle: how an outline's text is aligned. A block of one line,
    /// or none, is returned as it is, since its line is already where the block's left end is. The blocks refer to this
    /// block's lines where they are.
    func leftAlignedLines() -> [DiagramTextBlock] {
        guard lineCount > 1 else { return [self] }
        let left = center.x - size.width / 2
        let top = center.y - size.height / 2
        return (0..<lineCount).map { index in
            lineBlock(at: index, center: CGPoint(x: left + lineWidth(at: index) / 2, y: top + (CGFloat(index) + 0.5) * lineHeight))
        }
    }
}
