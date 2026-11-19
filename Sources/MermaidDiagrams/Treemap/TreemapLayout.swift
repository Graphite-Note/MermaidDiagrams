/**
 * File: TreemapLayout.swift
 * -------------------------
 * Layer: Core
 * Description: A laid-out treemap: its boxes with their texts and styles, and its title.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */

import CoreGraphics

/// A treemap laid out on a page whose origin is the top left corner and whose y runs down, in points: a box for every node
/// with a size and every section holding one, parents before children (so a child is painted over its parent), the title
/// above.
public struct TreemapLayout: Equatable, Sendable {
    public let size: CGSize
    /// The font the text was measured in: the title at its size, the names and values at their own.
    public let font: DiagramFont
    public let boxes: [TreemapLayoutBox]
    public let title: DiagramTextBlock?
}

/// One box of a treemap: a leaf, or a section with or without its header band.
public struct TreemapLayoutBox: Equatable, Sendable {
    /// The node's index in the diagram's nodes.
    public let nodeIndex: Int
    /// The position of the box's branch among the top-level nodes, which picks its series color.
    public let seriesIndex: Int
    public let frame: CGRect
    public let isSection: Bool
    /// Whether a section keeps a header band and is drawn as a box; one too small gives its whole box to its children and
    /// draws nothing.
    public let hasHeader: Bool
    /// The corners' radius: 4 points, less on a small box (a quarter of its shorter side).
    public let cornerRadius: CGFloat
    /// The node's name, fitted to the box: in a section's header at the left, centered in a leaf. Nil when it does not fit.
    public let name: DiagramTextBlock?
    /// The value, right-aligned in a section's header or centered under a leaf's name. Nil when it is not shown or does not fit.
    public let value: DiagramTextBlock?
    /// What the node's class sets, or nothing.
    public let style: DiagramElementStyle
    /// What the node's class sets of its text: the size its name and value are written at, their weight and slant.
    public let textStyle: TreemapClassTextStyle
}
