/**
 * File: FlowchartDrawingParts.swift
 * ---------------------------------
 * Layer: Core
 * Description: A laid-out flowchart's geometry grouped by how it is painted.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.7
 * Date: 26/11/2026
 */

import CoreGraphics

/// A laid-out flowchart's geometry grouped by how it is painted, so that drawing it in any colors is a handful of
/// fills and strokes, by Core Graphics (`FlowchartRenderer`) or by a view's own shapes. Back to front, as Pele draws:
/// the groups' boxes and the titles no edge crosses, the edges and their marks, the titles edges cross on their
/// patches, the patches behind edge text and that text, the node shapes and their text, the title.
public struct FlowchartDrawingParts {
    /// The boxes of the flowchart's groups; empty parts for a flowchart without groups.
    public let clusters: FlowchartClusterDrawingParts
    /// Solid edges, stroked one point wide with round caps.
    public let solidEdges: CGPath
    /// Thick edges, stroked 2.5 points wide.
    public let thickEdges: CGPath
    /// Dotted edges, stroked one point wide in dashes of 3 and gaps of 4.
    public let dottedEdges: CGPath
    /// Arrows and circles at the ends of edges, filled in the line color.
    public let filledMarks: CGPath
    /// Crosses at the ends of edges, stroked one point wide in the line color.
    public let strokedMarks: CGPath
    /// The patches behind edge text, filled in the background color.
    public let edgeTextPatches: CGPath
    public let edgeTexts: [DiagramTextBlock]
    /// The node shapes, filled in the surface color.
    public let nodeFills: CGPath
    /// The node shapes' outlines and inner lines, stroked one point wide in the border color.
    public let nodeOutlines: CGPath
    /// The shapes painted piece by piece (a person, stacked documents, a fork's bar), each piece in turn, after the
    /// node shapes above.
    public let layeredNodeShapes: [FlowchartShapeLayer]
    public let nodeTexts: [DiagramTextBlock]
    /// The edges the diagram gave colors or a stroke of their own (`linkStyle`), apart from the edges above.
    public let styledEdges: [FlowchartStyledEdgeParts]
    /// The nodes the diagram gave colors of their own (`classDef`, `class`, `style`), apart from the nodes above.
    public let styledNodes: [FlowchartStyledNodeParts]
    /// The title, drawn bold, or nil.
    public let title: DiagramTextBlock?

    public static let lineWidth: CGFloat = 1
    public static let thickLineWidth: CGFloat = 2.5
    public static let dottedDashLengths: [CGFloat] = [3, 4]

    /// The corner radius of the patch behind an edge's text.
    static let edgeTextPatchCornerRadius: CGFloat = 3
    /// How much wider than its text the patch behind an edge's text is.
    static let edgeTextPatchExtraWidth: CGFloat = 8

    public init(layout: FlowchartLayout) {
        let maker = DiagramCoreGraphicsPaths()
        let records = layout.records
        let edges = FlowchartEdgePaths(records: records, making: maker)
        let nodes = FlowchartNodePaths(records: records, making: maker)
        clusters = FlowchartClusterDrawingParts(clusters: layout.clusters)
        solidEdges = edges.solid.path
        thickEdges = edges.thick.path
        dottedEdges = edges.dotted.path
        filledMarks = edges.filledMarks.path
        strokedMarks = edges.strokedMarks.path
        edgeTextPatches = edges.textPatches.path
        edgeTexts = records.edges.compactMap { edge in edge.text.map(records.block) }
        nodeFills = nodes.fills.path
        nodeOutlines = nodes.outlines.path
        styledEdges = records.edges.indices.compactMap { index in
            let edge = records.edges[index]
            guard edge.isStyled, let style = records.style(at: edge.styleIndex) else { return nil }
            return FlowchartStyledEdgeParts(edge: records.layoutEdge(at: index), style: style)
        }
        var layered: [FlowchartShapeLayer] = []
        var texts: [DiagramTextBlock] = []
        var styled: [FlowchartStyledNodeParts] = []
        for (index, node) in records.nodes.enumerated() {
            if let style = records.style(at: node.styleIndex) {
                styled.append(FlowchartStyledNodeParts(node: records.layoutNode(at: index), style: style))
                continue
            }
            texts.append(records.block(node.text))
            if !node.hasAsset, let layers = FlowchartShapeDrawing.layers(of: node.shape, in: node.frame) { layered.append(contentsOf: layers) }
        }
        layeredNodeShapes = layered
        nodeTexts = texts
        styledNodes = styled
        title = layout.title
    }
}
