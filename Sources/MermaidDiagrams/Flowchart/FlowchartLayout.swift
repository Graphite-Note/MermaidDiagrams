/**
 * File: FlowchartLayout.swift
 * ---------------------------
 * Layer: Core
 * Description: A flowchart laid out on a page: its nodes and edges kept as flat records its scene reads where they lie,
 *              and made as values only for a reader that asks for them.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.5
 * Date: 26/11/2026
 */

import CoreGraphics

/// A flowchart laid out on a page whose origin is the top left corner and whose y runs down, in points. Drawing it
/// needs only colors: every position, path and text measurement is here.
///
/// The nodes and edges are kept as flat records (`FlowchartLayoutRecords`): a few numbers each, every edge's segments in
/// one list. `nodes` and `edges` make them as values each time they are read; the scene reads the records themselves.
public struct FlowchartLayout: Equatable, Sendable {
    public let size: CGSize
    /// The font the nodes' text was measured in; edge text is in the same font at its own `fontSize`.
    public let font: DiagramFont
    /// The diagram's title above it, or nil.
    public let title: DiagramTextBlock?
    /// The boxes of the diagram's groups (`subgraph … end`), in the order of `FlowchartDiagram.subgraphs`: each before
    /// the boxes inside it. Empty for a flowchart without groups.
    public let clusters: [FlowchartLayoutCluster]
    /// The nodes and edges.
    let records: FlowchartLayoutRecords

    init(size: CGSize, font: DiagramFont, records: FlowchartLayoutRecords, title: DiagramTextBlock?, clusters: [FlowchartLayoutCluster]) {
        self.size = size
        self.font = font
        self.records = records
        self.title = title
        self.clusters = clusters
    }

    /// A layout of nodes and edges kept as values, each copied once into the records.
    init(size: CGSize, font: DiagramFont, nodes: [FlowchartLayoutNode], edges: [FlowchartLayoutEdge], title: DiagramTextBlock?,
         clusters: [FlowchartLayoutCluster]) {
        self.init(size: size, font: font, records: FlowchartLayoutRecords(nodes: nodes, edges: edges), title: title, clusters: clusters)
    }

    /// The nodes drawn, in the order the diagram names them. A node that stands for a group (`A --> group`) is the
    /// group's box, not a node, so a flowchart with subgraphs may have fewer nodes here than its diagram. Made from the
    /// records each time it is read.
    public var nodes: [FlowchartLayoutNode] { (0..<records.nodes.count).map(records.layoutNode(at:)) }

    /// The edges in the order they are written, edges to a node itself included. Made from the records each time it is
    /// read.
    public var edges: [FlowchartLayoutEdge] { (0..<records.edges.count).map(records.layoutEdge(at:)) }

    /// Layouts are equal when their sizes, fonts, titles, boxes, nodes and edges are, as values.
    public static func == (left: FlowchartLayout, right: FlowchartLayout) -> Bool {
        left.size == right.size && left.font == right.font && left.title == right.title && left.clusters == right.clusters
            && left.records.nodes.count == right.records.nodes.count && left.records.edges.count == right.records.edges.count
            && left.nodes == right.nodes && left.edges == right.edges
    }
}

/// A group's box, drawn behind everything else, in Pele's style: half of the alternate surface color over what is
/// behind it, so that a box inside another is darker, with an outline and its title along the top.
public struct FlowchartLayoutCluster: Equatable, Sendable {
    public let frame: CGRect
    /// The title, along the top of the box, or nil for a group without one.
    public let title: DiagramTextBlock?
    /// How many boxes this one is inside: 0 for a box at the top level.
    public let depth: Int
    /// Whether an edge runs through the title where it sits: it is then drawn over the edges, on a patch of the box's
    /// color, so that the edge stops short of its letters.
    public let isTitleCrossed: Bool
}

public struct FlowchartLayoutNode: Equatable, Sendable {
    public let shape: FlowchartNodeShape
    /// The shape's bounding box.
    public let frame: CGRect
    public let text: DiagramTextBlock
    /// The colors the diagram's statements give the node, or nil for the usual look.
    public let style: DiagramElementStyle?
    /// The icon or picture the node shows instead of its shape, or nil.
    public internal(set) var asset: FlowchartNodeAsset? = nil
}

public struct FlowchartLayoutEdge: Equatable, Sendable {
    public let stroke: FlowchartEdgeStroke
    /// The line, which stops where a mark begins.
    public let path: DiagramPath
    public let sourceMark: DiagramEdgeMark?
    public let targetMark: DiagramEdgeMark?
    /// The edge's text, drawn on a patch of the background, or nil.
    public let text: DiagramTextBlock?
    /// The line and mark colors and stroke the diagram's statements give the edge, or nil for the usual look.
    public let style: DiagramElementStyle?
}

extension FlowchartLayoutNode {
    func translated(by offset: CGVector) -> FlowchartLayoutNode {
        FlowchartLayoutNode(shape: shape, frame: frame.offsetBy(dx: offset.dx, dy: offset.dy), text: text.translated(by: offset), style: style, asset: asset)
    }
}

extension FlowchartLayoutCluster {
    func translated(by offset: CGVector) -> FlowchartLayoutCluster {
        FlowchartLayoutCluster(frame: frame.offsetBy(dx: offset.dx, dy: offset.dy), title: title?.translated(by: offset), depth: depth,
                               isTitleCrossed: isTitleCrossed)
    }
}

extension FlowchartLayoutEdge {
    func translated(by offset: CGVector) -> FlowchartLayoutEdge {
        FlowchartLayoutEdge(stroke: stroke, path: path.translated(by: offset), sourceMark: sourceMark?.translated(by: offset),
                            targetMark: targetMark?.translated(by: offset), text: text?.translated(by: offset), style: style)
    }
}
