/**
 * File: PlaneMapLabel.swift
 * -------------------------
 * Layer: Core
 * Description: Measures a text as Pele's layoutLabel does for the diagrams drawn on a fixed plane: nothing for an empty
 *              text, wrapped at spaces past a width, and a text of several lines set closer, 1.3 times the size apart.
 *
 * Authors: Bahey Shalash
 * Version: 0.5
 * Date: 23/11/2026
 */

import CoreGraphics

/// A measured text as Pele's `layoutLabel` gives it: nil for an empty text, one line where it fits or has no space,
/// wrapped at spaces where it is wider than its room, and a text of more than one line, wrapped or broken by `<br>`, has
/// its lines 1.3 times the size apart, rounded (Pele's `WRAPPED_LINE_HEIGHT`), where a single line is 1.5 times its size
/// high.
enum PlaneMapLabel {
    /// The width past which Pele wraps a text that has no room of its own: wide enough that it does not.
    static let unwrappedWidth: CGFloat = 4_000

    /// `form` is how the text is read: plain, or Markdown (an architecture diagram's titles), its emphasis markers left out.
    static func block(_ text: String?, measurer: some DiagramTextMeasuring, maximumWidth: CGFloat = unwrappedWidth,
                      form: DiagramLabelDecoder.Form = .plain) -> DiagramTextBlock? {
        guard let text, !text.isEmpty else { return nil }
        let label = DiagramLabelDecoder.label(from: text, form: form)
        guard !label.isEmpty else { return nil }
        return block(label, measurer: measurer, maximumWidth: maximumWidth)
    }

    /// A label already decoded, measured as `block` measures a text; an empty label has no lines.
    static func block(_ label: DiagramLabel, measurer: some DiagramTextMeasuring, maximumWidth: CGFloat = unwrappedWidth) -> DiagramTextBlock {
        DiagramTextBlock(label: label, measurer: measurer, maximumWidth: maximumWidth)
    }

    /// `block` with its center at `center`.
    static func placed(_ block: DiagramTextBlock, at center: CGPoint) -> DiagramTextBlock {
        var placed = block
        placed.center = center
        return placed
    }
}
