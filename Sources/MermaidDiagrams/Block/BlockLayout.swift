/**
 * File: BlockLayout.swift
 * -----------------------
 * Layer: Core
 * Description: A laid-out block diagram: its composites' boxes and titles, its blocks' shapes and arrows with their
 *              text, its edges' lines, marks and text, on a page whose origin is its top left.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// A block diagram laid out on a page whose origin is the top left corner and whose y runs down, in points, as Pele lays
/// it out: the bold title above; the composites' boxes, outermost first; the blocks in their cells; the edges.
public struct BlockLayout: Equatable, Sendable {
    public let size: CGSize
    /// The font the blocks' text was measured in; the title is in its bold, an edge's text at seven eighths of its size,
    /// and a block's at the size its style sets.
    public let font: DiagramFont
    public let title: DiagramTextBlock?
    /// The composites, outermost first, in the order they are reached.
    public let composites: [BlockLayoutComposite]
    /// The blocks and arrows, in the order they are reached.
    public let nodes: [BlockLayoutNode]
    public let edges: [BlockLayoutEdge]
}

/// A composite's box and its title.
public struct BlockLayoutComposite: Equatable, Sendable {
    public let identifier: String
    public let frame: CGRect
    public let title: DiagramTextBlock?
    public let appearance: BlockAppearance
}

/// What a block is drawn as.
public enum BlockLayoutNodeForm: Equatable, Sendable {
    /// One of the flowchart's classic shapes in the node's frame.
    case shape(FlowchartNodeShape)
    /// A block arrow: its outline's corners on the page.
    case arrow([CGPoint])
}

/// A block or an arrow: its frame as drawn, its form and its text.
public struct BlockLayoutNode: Equatable, Sendable {
    public let identifier: String
    public let form: BlockLayoutNodeForm
    public let frame: CGRect
    public let text: DiagramTextBlock?
    public let appearance: BlockAppearance
}

/// An edge: its line, the marks at its ends, its line's kind and its text.
public struct BlockLayoutEdge: Equatable, Sendable {
    public let identifier: String
    public let path: DiagramPath
    public let sourceMark: DiagramEdgeMark?
    public let targetMark: DiagramEdgeMark?
    public let isThick: Bool
    public let isDotted: Bool
    /// Its text, drawn on a patch of the page's color 8 points wider than it.
    public let text: DiagramTextBlock?
}
