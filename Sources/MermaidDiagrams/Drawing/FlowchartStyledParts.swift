/**
 * File: FlowchartStyledParts.swift
 * --------------------------------
 * Layer: Core
 * Description: The nodes and edges a flowchart gave colors of their own, painted apart.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 23/11/2026
 */

import CoreGraphics

/// A node the diagram gave colors of its own (`classDef`, `class`, `:::`, `style`): its shape, painted apart from the nodes
/// of the usual look, in the colors it sets and the usual ones for the rest.
public struct FlowchartStyledNodeParts {
    /// The shape's outline to fill, or nil for a shape drawn as text alone.
    public var fill: CGPath? { fillScenePath.map(\.coreGraphicsPath) }
    let fillScenePath: DiagramScenePath?
    /// The shape's outline and inner lines to stroke.
    public var outline: CGPath { outlineScenePath.coreGraphicsPath }
    let outlineScenePath: DiagramScenePath
    /// The pieces of a shape painted piece by piece, back to front, in place of `fill` and `outline`; empty for the others.
    public let layers: [FlowchartShapeLayer]
    public let text: DiagramTextBlock
    public let style: DiagramElementStyle

    init(node: FlowchartLayoutNode, style: DiagramElementStyle) {
        text = node.text
        self.style = style
        if let asset = node.asset {
            let frame = FlowchartNodeAssetDrawing.frame(of: asset, in: node)
            layers = []
            fillScenePath = frame
            outlineScenePath = frame ?? DiagramScenePath()
            return
        }
        if let layers = FlowchartShapeDrawing.layers(of: node.shape, in: node.frame) {
            self.layers = layers
            fillScenePath = nil
            outlineScenePath = DiagramScenePath()
            return
        }
        layers = []
        var outlines = DiagramScenePath()
        let outline = FlowchartShapeDrawing.outline(of: node.shape, in: node.frame)
        if let outline { outlines.addPath(outline) }
        if let innerLines = FlowchartShapeDrawing.innerLines(of: node.shape, in: node.frame) { outlines.addPath(innerLines) }
        fillScenePath = outline
        self.outlineScenePath = outlines
    }

    /// The width of the outline: the diagram's usual unless the style sets one.
    public var lineWidth: CGFloat { style.strokeWidth ?? FlowchartDrawingParts.lineWidth }
}

/// An edge the diagram gave a stroke or colors of its own (`linkStyle`): its line and marks, painted apart from the other edges.
public struct FlowchartStyledEdgeParts {
    public var line: CGPath { lineScenePath.coreGraphicsPath }
    let lineScenePath: DiagramScenePath
    /// Arrows and circles at the ends, filled in the line's color.
    public var filledMarks: CGPath { filledMarksScenePath.coreGraphicsPath }
    let filledMarksScenePath: DiagramScenePath
    /// Crosses at the ends, stroked in the line's color.
    public var strokedMarks: CGPath { strokedMarksScenePath.coreGraphicsPath }
    let strokedMarksScenePath: DiagramScenePath
    public let style: DiagramElementStyle
    /// The width of the line its kind has (`-->`, `==>`, `-.->`), when the style sets none.
    private let usualLineWidth: CGFloat
    private let usualDashLengths: [CGFloat]

    init(edge: FlowchartLayoutEdge, style: DiagramElementStyle) {
        lineScenePath = DiagramEdgeDrawing.path(edge.path)
        var filled = DiagramScenePath()
        var stroked = DiagramScenePath()
        for mark in [edge.sourceMark, edge.targetMark].compactMap({ mark in mark }) { DiagramEdgeDrawing.addMark(mark, filled: &filled, stroked: &stroked) }
        filledMarksScenePath = filled
        strokedMarksScenePath = stroked
        self.style = style
        usualLineWidth = edge.stroke == .thick ? FlowchartDrawingParts.thickLineWidth : FlowchartDrawingParts.lineWidth
        usualDashLengths = edge.stroke == .dotted ? FlowchartDrawingParts.dottedDashLengths : []
    }

    public var lineWidth: CGFloat { style.strokeWidth ?? usualLineWidth }
    public var dashLengths: [CGFloat] { style.strokeDashLengths ?? usualDashLengths }
}
