/**
 * File: DiagramSceneTextLine.swift
 * --------------------------------
 * Layer: Core
 * Description: Where each line of a scene's text sits: the center of its line box and the start of its baseline, as Core
 *              Text and SVG place it.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

import CoreGraphics

/// One line of a scene's text, placed as `DiagramSceneRenderer` draws it, before any rotation of its text: centered on
/// the block's center across, one line height below the line before it.
public struct DiagramSceneTextLine: Equatable, Sendable {
    public let text: String
    /// The middle of the line's box: where a view that centers text in its frame puts it.
    public let center: CGPoint
    /// The line's width in the font it was measured in.
    public let width: CGFloat
    /// The left end of the line's baseline, Pele's `fontSize × 0.35` below the middle of its box.
    public let baselineStart: CGPoint
    /// The line's pieces in their emphasis, from `baselineStart` on, each `width` after the one before: one run in the
    /// text's own font for a line without emphasis, none for an empty line.
    public let runs: [DiagramTextRun]
}

extension DiagramSceneText {
    /// The block's lines, top to bottom. A turned text turns them about the block's center (`rotation`).
    public var lines: [DiagramSceneTextLine] {
        let top = block.center.y - block.size.height / 2
        return block.lines.indices.map { index in
            let middle = top + (CGFloat(index) + 0.5) * block.lineHeight
            let width = block.lineWidths[index]
            return DiagramSceneTextLine(text: block.lines[index], center: CGPoint(x: block.center.x, y: middle), width: width,
                                        baselineStart: CGPoint(x: block.center.x - width / 2,
                                                               y: middle + block.fontSize * DiagramTextDrawing.baselineShiftRatio),
                                        runs: block.runs(ofLine: index))
        }
    }

    /// Each line's pieces in their emphasis (bold, italic or monospaced beyond `isBold`, `isItalic` and `isMonospaced`),
    /// as Pele draws a label's spans, or nil when the whole text is in its own font.
    public var styledRuns: [[DiagramTextRun]]? {
        block.lineRuns
    }
}
