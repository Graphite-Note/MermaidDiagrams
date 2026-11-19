/**
 * File: SequenceLayoutBox.swift
 * -----------------------------
 * Layer: Core
 * Description: A laid-out sequence box: the background behind a run of participants, its color and its title.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// A box behind a run of neighbouring participants in one `box`, from the page's top under the title to below the
/// participants mirrored under the last row.
public struct SequenceLayoutBox: Equatable, Sendable {
    public let frame: CGRect
    /// The color the box names, or nil for Pele's default shade.
    public let color: SequenceHighlightColor?
    /// The title centered at the box's top, or nil.
    public let title: DiagramTextBlock?
}

extension SequenceLayoutBox {
    func translated(by offset: CGVector) -> SequenceLayoutBox {
        SequenceLayoutBox(frame: frame.offsetBy(dx: offset.dx, dy: offset.dy), color: color, title: title?.translated(by: offset))
    }
}
