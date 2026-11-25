/**
 * File: DiagramSceneBuilderMeasuredText.swift
 * -------------------------------------------
 * Layer: Core
 * Description: A scene's texts given to its builder as texts measured from their source's bytes (DiagramMeasuredText in
 *              a layout's DiagramMeasuredLines): each written into the scene's text once, the same text, SVG and
 *              accessibility to the byte as the block of its decoded label.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

import CoreGraphics

extension DiagramSceneBuilder {
    /// `text`, a text of `lines` measured from `source`'s bytes (`DiagramFlatTextMeasuring`), drawn as
    /// `text(_:_:isBold:isItalic:isMonospaced:rotation:outline:part:)` draws the block of the same text: its lines' bytes,
    /// widths and runs are copied into the scene's text here, so that the scene needs neither `lines` nor `source` once
    /// made. A text of no line paints nothing and is left out.
    mutating func text(_ text: DiagramMeasuredText, of lines: borrowing DiagramMeasuredLines, source: UnsafeBufferPointer<UInt8> = DiagramMeasuredLines.noSource,
                       _ paint: DiagramPaint, isBold: Bool = false, isItalic: Bool = false, isMonospaced: Bool = false, rotation: CGFloat? = nil,
                       outline: DiagramTextOutline? = nil, part: DiagramScenePart) {
        guard text.lineCount > 0 else { return }
        addText(DiagramTextBlock(text, of: lines, source: source), paint, isBold: isBold, isItalic: isItalic, isMonospaced: isMonospaced,
                rotation: rotation, outline: outline, part: part)
    }

    /// Each of `texts`, of `lines` over `source`, in their order.
    mutating func texts(_ texts: some Sequence<DiagramMeasuredText>, of lines: borrowing DiagramMeasuredLines,
                        source: UnsafeBufferPointer<UInt8> = DiagramMeasuredLines.noSource, _ paint: DiagramPaint, isBold: Bool = false, isItalic: Bool = false,
                        isMonospaced: Bool = false, outline: DiagramTextOutline? = nil, part: DiagramScenePart) {
        for text in texts {
            self.text(text, of: lines, source: source, paint, isBold: isBold, isItalic: isItalic, isMonospaced: isMonospaced, outline: outline, part: part)
        }
    }

    /// The diagram's title, measured from its bytes: bold in the foreground color, as `title(_:)` draws a block.
    mutating func title(_ text: DiagramMeasuredText?, of lines: borrowing DiagramMeasuredLines, source: UnsafeBufferPointer<UInt8> = DiagramMeasuredLines.noSource) {
        guard let text else { return }
        self.text(text, of: lines, source: source, .foreground, isBold: true, part: .title)
    }
}

#if DEBUG
/// For the tests: a text a scene builder is given as a block, given instead as the measured text this makes of it (nil
/// to keep the block), so that the scene of every corpus is also built from texts measured from their written bytes.
enum DiagramSceneTextSubstitution {
    struct Substituted {
        let text: DiagramMeasuredText
        let lines: DiagramMeasuredLines
        let source: [UInt8]
    }

    nonisolated(unsafe) static var measuredText: ((DiagramTextBlock) -> Substituted?)?
}
#endif
