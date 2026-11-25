/**
 * File: AgentFlowScene.swift
 * --------------------------
 * Layer: Core
 * Description: A laid-out agent flow's scene in Pele's order and colors: the title, the flows' washed boxes and titles,
 *              the edges and their marks, the edges' text on patches, then the nodes in their kinds' series colors, its
 *              paths recorded into lanes of the thread's scene workspace.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 25/11/2026
 */

import CoreGraphics

extension DiagramScene {
    /// The agent flow's painting, back to front as Pele's SVG has it: the title; each flow's box, a wash of its series
    /// color at 6% with an outline in it, and its title in the muted color; the edges in the line color, a reference
    /// dotted, with their marks; the patches behind edge text and that text; each node's shape, a wash of its kind's
    /// series color at 14% outlined in it (a collapsed flow's at 6%, with a dashed line and three dots), and its text.
    /// A fill a style sets replaces the wash and stays opaque, and the text on it takes Pele's dark or white ink. An edge
    /// that one filled flow holds whole is drawn in that fill's ink, and one that crosses a filled flow's border runs
    /// over a casing of the page's color, painted after the flows (Pele's `overFills` and `edgeCasing`).
    public init(layout: AgentFlowLayout) {
        self.init(layout: layout, limits: .standard)
    }

    /// The scene recorded into lanes of at most `DiagramSceneWorkspace.elementLimit(for: limits)` elements: one past
    /// it marks the scene (`exceededPathElementLimit`), which the preparation refuses.
    init(layout: AgentFlowLayout, limits: MermaidDiagramLimits) {
        self = DiagramSceneWorkspace.withRecording(limits: limits) { workspace in
            var builder = DiagramSceneBuilder(workspace: workspace)
            builder.title(layout.title)
            let line = DiagramStroke.rounded(lineWidth: FlowchartDrawingParts.lineWidth)
            for flow in layout.flows { AgentFlowScenePainting.add(flow, to: &builder, workspace: workspace, line: line) }
            let inks = AgentFlowScenePainting.inks(of: layout)
            for (edge, ink) in zip(layout.edges, inks) where ink == .cased { AgentFlowScenePainting.addCasing(of: edge, to: &builder, workspace: workspace) }
            for (edge, ink) in zip(layout.edges, inks) { AgentFlowScenePainting.add(edge, ink: ink, to: &builder, workspace: workspace, line: line) }
            for edge in layout.edges where edge.text != nil { AgentFlowScenePainting.addText(of: edge, to: &builder, workspace: workspace) }
            for node in layout.nodes { AgentFlowScenePainting.add(node, to: &builder, workspace: workspace, line: line) }
            return builder.scene(size: layout.size, font: layout.font)
        }
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

    static func add(_ flow: AgentFlowLayoutFlow, to builder: inout DiagramSceneBuilder, workspace: DiagramSceneWorkspace, line: DiagramStroke) {
        let madeCount = workspace.madePathCount
        defer { workspace.givePathsBack(downTo: madeCount) }
        let box = workspace.roundedRectangle(flow.frame, cornerWidth: cornerRadius, cornerHeight: cornerRadius)
        let color = DiagramPaint.series(flow.paletteSlot)
        builder.keepNextShapeApart()
        builder.fillAndStroke(box, fill: fillPaint(flow.style, wash: color.atOpacity(flowWash)), stroke: flow.style?.stroke.map(DiagramPaint.color) ?? color,
                              stroke(line, style: flow.style), part: .cluster)
        builder.text(flow.title, textPaint(flow.style, fallback: .muted), part: .clusterLabel)
    }

    /// The width a casing adds to the line it lies under, Pele's `CASE`.
    static let casingExtraWidth: CGFloat = 4

    /// Each edge's ink over the flows a style fills, in the order of the layout's edges; plain past the comparisons'
    /// bound (`BlockEdgeInk.comparisonBudget`).
    static func inks(of layout: AgentFlowLayout) -> [BlockEdgeInk] {
        let fills = layout.flows.compactMap { flow -> (box: CGRect, color: DiagramColor)? in
            guard let color = flow.style?.fill, color.alpha > 0 else { return nil }
            return (flow.frame, color)
        }
        guard !fills.isEmpty, layout.edges.count * fills.count <= BlockEdgeInk.comparisonBudget else {
            return Array(repeating: .plain, count: layout.edges.count)
        }
        return layout.edges.map { edge in
            BlockEdgeInk.ink(of: edge.path, targetTip: edge.targetMark?.tip, over: fills)
        }
    }

    /// The stroke of the page's color under `edge` and its mark, 4 points wider than its line, with round ends and
    /// corners, the mark filled and outlined in it.
    static func addCasing(of edge: AgentFlowLayoutEdge, to builder: inout DiagramSceneBuilder, workspace: DiagramSceneWorkspace) {
        let madeCount = workspace.madePathCount
        defer { workspace.givePathsBack(downTo: madeCount) }
        let casing = DiagramStroke.rounded(lineWidth: (edge.style?.strokeWidth ?? FlowchartDrawingParts.lineWidth) + casingExtraWidth)
        builder.stroke(line(of: edge, workspace: workspace), .background, casing, part: .casing)
        guard let mark = edge.targetMark else { return }
        let filled = workspace.makeLane()
        let stroked = workspace.makeLane()
        DiagramEdgeDrawing.addMark(mark, filled: filled, stroked: stroked)
        builder.fillAndStroke(filled, fill: .background, stroke: .background, casing, part: .casing)
        builder.stroke(stroked, .background, casing, part: .casing)
    }

    /// The edge's line and mark in its style's color, or in the ink of the filled flow that holds it.
    static func add(_ edge: AgentFlowLayoutEdge, ink: BlockEdgeInk, to builder: inout DiagramSceneBuilder, workspace: DiagramSceneWorkspace,
                    line: DiagramStroke) {
        let madeCount = workspace.madePathCount
        defer { workspace.givePathsBack(downTo: madeCount) }
        var paint = edge.style?.stroke.map(DiagramPaint.color) ?? .line
        if case .inked(let color) = ink { paint = .color(color) }
        let width = edge.style?.strokeWidth ?? FlowchartDrawingParts.lineWidth
        let dashes = edge.style?.strokeDashLengths ?? (edge.isDotted ? dottedDashLengths : [])
        builder.stroke(self.line(of: edge, workspace: workspace), paint, .rounded(lineWidth: width, dashLengths: dashes), part: .edge)
        guard let mark = edge.targetMark else { return }
        let filled = workspace.makeLane()
        let stroked = workspace.makeLane()
        DiagramEdgeDrawing.addMark(mark, filled: filled, stroked: stroked)
        builder.fill(filled, paint, part: .marker)
        builder.stroke(stroked, paint, line, part: .marker)
    }

    /// The edge's line, recorded into a lane of `workspace` for the moment.
    private static func line(of edge: AgentFlowLayoutEdge, workspace: DiagramSceneWorkspace) -> DiagramPathLane {
        let drawn = workspace.makeLane()
        DiagramEdgeDrawing.record(edge.path, into: drawn)
        return drawn
    }

    static func addText(of edge: AgentFlowLayoutEdge, to builder: inout DiagramSceneBuilder, workspace: DiagramSceneWorkspace) {
        guard let text = edge.text else { return }
        let madeCount = workspace.madePathCount
        defer { workspace.givePathsBack(downTo: madeCount) }
        let patch = text.frame.insetBy(dx: -FlowchartDrawingParts.edgeTextPatchExtraWidth / 2, dy: 0)
        builder.fill(workspace.roundedRectangle(patch, cornerWidth: FlowchartDrawingParts.edgeTextPatchCornerRadius,
                                                cornerHeight: FlowchartDrawingParts.edgeTextPatchCornerRadius), .background, part: .labelBackground)
        builder.text(text, edge.style?.textColor.map(DiagramPaint.color) ?? .foreground, part: .edgeLabel)
    }

    static func add(_ node: AgentFlowLayoutNode, to builder: inout DiagramSceneBuilder, workspace: DiagramSceneWorkspace, line: DiagramStroke) {
        let madeCount = workspace.madePathCount
        defer { workspace.givePathsBack(downTo: madeCount) }
        let color = DiagramPaint.series(node.paletteSlot)
        let strokePaint = node.style?.stroke.map(DiagramPaint.color) ?? color
        let outlineStroke = stroke(line, style: node.style)
        builder.keepNextShapeApart()
        if node.isCollapsedFlow {
            addCollapsedFlow(node, color: color, strokePaint: strokePaint, stroke: outlineStroke, to: &builder, workspace: workspace)
        } else if let outline = FlowchartShapeDrawing.outline(of: node.shape, in: node.frame, making: workspace) {
            builder.fillAndStroke(outline, fill: fillPaint(node.style, wash: color.atOpacity(nodeWash)), stroke: strokePaint, outlineStroke, part: .node)
            if let innerLines = FlowchartShapeDrawing.innerLines(of: node.shape, in: node.frame, making: workspace) {
                builder.stroke(innerLines, strokePaint, outlineStroke, part: .node)
            }
        }
        builder.text(node.text, textPaint(node.style, fallback: .foreground), isBold: node.isBold, isItalic: node.isItalic, part: .label)
    }

    /// A collapsed flow: a washed box, a dashed line above its bottom, and three dots below the line.
    private static func addCollapsedFlow(_ node: AgentFlowLayoutNode, color: DiagramPaint, strokePaint: DiagramPaint, stroke: DiagramStroke,
                                         to builder: inout DiagramSceneBuilder, workspace: DiagramSceneWorkspace) {
        let frame = node.frame
        let box = workspace.roundedRectangle(frame, cornerWidth: cornerRadius, cornerHeight: cornerRadius)
        builder.fillAndStroke(box, fill: fillPaint(node.style, wash: color.atOpacity(flowWash)), stroke: strokePaint, stroke, part: .node)
        let lineY = frame.maxY - AgentFlowLayoutEngine.collapsedMarkHeight - 2
        let dashed = workspace.makeLane()
        dashed.move(to: CGPoint(x: frame.minX + collapsedLineInset, y: lineY))
        dashed.addLine(to: CGPoint(x: frame.maxX - collapsedLineInset, y: lineY))
        builder.stroke(dashed, color, DiagramStroke(lineWidth: stroke.lineWidth, dashLengths: collapsedLineDashLengths), part: .node)
        let dotsY = lineY + (AgentFlowLayoutEngine.collapsedMarkHeight + 2) / 2
        let dots = workspace.makeLane()
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
