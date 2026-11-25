/**
 * File: SequenceLayoutBox.swift
 * -----------------------------
 * Layer: Core
 * Description: A laid-out sequence box: the background behind a run of participants, its color and its title.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

import CoreGraphics

/// A box behind a run of neighbouring participants in one `box`, from the page's top under the title to below the
/// participants mirrored under the last row.
public struct SequenceLayoutBox: Equatable, Sendable {
    public internal(set) var frame: CGRect
    /// The color the box names, or nil for Pele's default shade.
    public let color: SequenceHighlightColor?
    /// The title centered at the box's top, or nil.
    public internal(set) var title: DiagramTextBlock?
}

extension SequenceLayoutBox {
    func translated(by offset: CGVector) -> SequenceLayoutBox {
        SequenceLayoutBox(frame: frame.offsetBy(dx: offset.dx, dy: offset.dy), color: color, title: title?.translated(by: offset))
    }

    /// Moved by `offset` where it stands, as `translated(by:)` moves it.
    mutating func translate(by offset: CGVector) {
        frame = frame.offsetBy(dx: offset.dx, dy: offset.dy)
        title = title?.translated(by: offset)
    }
}
