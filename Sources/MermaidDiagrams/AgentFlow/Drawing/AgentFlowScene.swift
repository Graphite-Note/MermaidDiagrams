/**
 * File: AgentFlowScene.swift
 * --------------------------
 * Layer: Core
 * Description: A laid-out agent flow's scene in Pele's order and colors: the title, the flows' washed boxes and titles,
 *              the edges and their marks, the edges' text on patches, then the nodes in their kinds' series colors.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

extension DiagramScene {
    /// The agent flow's painting, back to front as Pele's SVG has it: the title; each flow's box, a wash of its series
    /// color at 6% with an outline in it, and its title in the muted color; the edges in the line color, a reference
    /// dotted, with their marks; the patches behind edge text and that text; each node's shape, a wash of its kind's
    /// series color at 14% outlined in it (a collapsed flow's at 6%, with a dashed line and three dots), and its text.
    /// A fill a style sets replaces the wash and stays opaque, and the text on it takes Pele's dark or white ink.
    public init(layout: AgentFlowLayout) {
        var builder = DiagramSceneBuilder()
        builder.title(layout.title)
        let line = DiagramStroke.rounded(lineWidth: FlowchartDrawingParts.lineWidth)
        for flow in layout.flows { AgentFlowScenePainting.add(flow, to: &builder, line: line) }
        for edge in layout.edges { AgentFlowScenePainting.add(edge, to: &builder, line: line) }
        for edge in layout.edges where edge.text != nil { AgentFlowScenePainting.addText(of: edge, to: &builder) }
        for node in layout.nodes { AgentFlowScenePainting.add(node, to: &builder, line: line) }
        self = builder.scene(size: layout.size, font: layout.font)
    }
}

/// How each part of an agent flow is painted.
enum AgentFlowScenePainting {
    /// Pele's washes: a flow's box and a collapsed flow, and a node.
    static let flowWash: CGFloat = 0.06
    static let nodeWash: CGFloat = 0.14
    /// The rounding of a flow's box and a collapsed flow, Pele's `--pele-radius`.
    static let cornerRadius: CGFloat = 4
    static let dottedDashLengths: [CGFloat] = [3, 4]
    static let collapsedLineDashLengths: [CGFloat] = [3, 3]
    static let collapsedLineInset: CGFloat = 10
    static let collapsedDotRadius: CGFloat = 1.75
    static let collapsedDotSpacing: CGFloat = 9

    static func add(_ flow: AgentFlowLayoutFlow, to builder: inout DiagramSceneBuilder, line: DiagramStroke) {
        let box = CGPath(roundedRect: flow.frame, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        let color = DiagramPaint.series(flow.paletteSlot)
        builder.keepNextShapeApart()
        builder.fillAndStroke(box, fill: fillPaint(flow.style, wash: color.atOpacity(flowWash)), stroke: flow.style?.stroke.map(DiagramPaint.color) ?? color,
                              stroke(line, style: flow.style), part: .cluster)
        builder.text(flow.title, textPaint(flow.style, fallback: .muted), part: .clusterLabel)
    }

    static func add(_ edge: AgentFlowLayoutEdge, to builder: inout DiagramSceneBuilder, line: DiagramStroke) {
        let paint = edge.style?.stroke.map(DiagramPaint.color) ?? .line
        let width = edge.style?.strokeWidth ?? FlowchartDrawingParts.lineWidth
        let dashes = edge.style?.strokeDashLengths ?? (edge.isDotted ? dottedDashLengths : [])
        builder.stroke(DiagramEdgeDrawing.path(edge.path), paint, .rounded(lineWidth: width, dashLengths: dashes), part: .edge)
        guard let mark = edge.targetMark else { return }
        let filled = CGMutablePath()
        let stroked = CGMutablePath()
        DiagramEdgeDrawing.addMark(mark, filled: filled, stroked: stroked)
        builder.fill(filled, paint, part: .marker)
        builder.stroke(stroked, paint, line, part: .marker)
    }

    static func addText(of edge: AgentFlowLayoutEdge, to builder: inout DiagramSceneBuilder) {
        guard let text = edge.text else { return }
        let patch = text.frame.insetBy(dx: -FlowchartDrawingParts.edgeTextPatchExtraWidth / 2, dy: 0)
        builder.fill(CGPath(roundedRect: patch, cornerWidth: FlowchartDrawingParts.edgeTextPatchCornerRadius,
                            cornerHeight: FlowchartDrawingParts.edgeTextPatchCornerRadius, transform: nil), .background, part: .labelBackground)
        builder.text(text, edge.style?.textColor.map(DiagramPaint.color) ?? .foreground, part: .edgeLabel)
    }

    static func add(_ node: AgentFlowLayoutNode, to builder: inout DiagramSceneBuilder, line: DiagramStroke) {
        let color = DiagramPaint.series(node.paletteSlot)
        let strokePaint = node.style?.stroke.map(DiagramPaint.color) ?? color
        let outlineStroke = stroke(line, style: node.style)
        builder.keepNextShapeApart()
        if node.isCollapsedFlow {
            addCollapsedFlow(node, color: color, strokePaint: strokePaint, stroke: outlineStroke, to: &builder)
        } else if let outline = FlowchartShapeDrawing.outline(of: node.shape, in: node.frame) {
            builder.fillAndStroke(outline, fill: fillPaint(node.style, wash: color.atOpacity(nodeWash)), stroke: strokePaint, outlineStroke, part: .node)
            if let innerLines = FlowchartShapeDrawing.innerLines(of: node.shape, in: node.frame) {
                builder.stroke(innerLines, strokePaint, outlineStroke, part: .node)
            }
        }
        builder.text(node.text, textPaint(node.style, fallback: .foreground), part: .label)
    }

    /// A collapsed flow: a washed box, a dashed line above its bottom, and three dots below the line.
    private static func addCollapsedFlow(_ node: AgentFlowLayoutNode, color: DiagramPaint, strokePaint: DiagramPaint, stroke: DiagramStroke,
                                         to builder: inout DiagramSceneBuilder) {
        let frame = node.frame
        let box = CGPath(roundedRect: frame, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        builder.fillAndStroke(box, fill: fillPaint(node.style, wash: color.atOpacity(flowWash)), stroke: strokePaint, stroke, part: .node)
        let lineY = frame.maxY - AgentFlowLayoutEngine.collapsedMarkHeight - 2
        let dashed = CGMutablePath()
        dashed.move(to: CGPoint(x: frame.minX + collapsedLineInset, y: lineY))
        dashed.addLine(to: CGPoint(x: frame.maxX - collapsedLineInset, y: lineY))
        builder.stroke(dashed, color, DiagramStroke(lineWidth: stroke.lineWidth, dashLengths: collapsedLineDashLengths), part: .node)
        let dotsY = lineY + (AgentFlowLayoutEngine.collapsedMarkHeight + 2) / 2
        let dots = CGMutablePath()
        for offset in [-collapsedDotSpacing, 0, collapsedDotSpacing] {
            dots.addEllipse(in: CGRect(x: frame.midX + offset - collapsedDotRadius, y: dotsY - collapsedDotRadius,
                                       width: 2 * collapsedDotRadius, height: 2 * collapsedDotRadius))
        }
        builder.fill(dots, color, part: .collapsedMark)
    }

    /// The wash, or the opaque fill a style sets.
    private static func fillPaint(_ style: DiagramElementStyle?, wash: DiagramPaint) -> DiagramPaint {
        style?.fill.map(DiagramPaint.color) ?? wash
    }

    /// The text's color a style sets, else Pele's dark or white ink on a fill it sets, else `fallback`.
    private static func textPaint(_ style: DiagramElementStyle?, fallback: DiagramPaint) -> DiagramPaint {
        if let color = style?.textColor { return .color(color) }
        if let fill = style?.fill, let ink = SequenceTextInk.ink(onColor: fill) { return .color(ink) }
        return fallback
    }

    private static func stroke(_ line: DiagramStroke, style: DiagramElementStyle?) -> DiagramStroke {
        guard let style, style.strokeWidth != nil || style.strokeDashLengths != nil else { return line }
        return .rounded(lineWidth: style.strokeWidth ?? line.lineWidth, dashLengths: style.strokeDashLengths ?? [])
    }
}
