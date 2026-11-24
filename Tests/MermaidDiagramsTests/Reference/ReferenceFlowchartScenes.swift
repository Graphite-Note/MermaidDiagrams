/**
 * File: ReferenceFlowchartScenes.swift
 * ------------------------------------
 * Layer: Tests
 * Description: 0.7.0's flowchart, swimlane and agent flow scenes, frozen as main 12970e9 made them from Core Graphics
 *              paths (the public drawing parts and the builder's Core Graphics paths), which the scenes recorded into
 *              lanes are compared with.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// 0.7.0's flowchart scene, made from the public drawing parts' Core Graphics paths.
enum ReferenceFlowchartScene {
    static func scene(layout: FlowchartLayout) -> DiagramScene {
        var builder = DiagramSceneBuilder()
        FlowchartDrawingParts(layout: layout).referenceAddScene(to: &builder)
        return builder.scene(size: layout.size, font: layout.font)
    }
}

extension FlowchartDrawingParts {
    /// Every line is drawn with round caps and joins.
    func referenceAddScene(to builder: inout DiagramSceneBuilder) {
        let line = DiagramStroke.rounded(lineWidth: Self.lineWidth)
        clusters.referenceAddBoxes(to: &builder)
        builder.stroke(solidEdges, .line, line, part: .edge)
        builder.stroke(thickEdges, .line, .rounded(lineWidth: Self.thickLineWidth), part: .edge)
        builder.stroke(dottedEdges, .line, .rounded(lineWidth: Self.lineWidth, dashLengths: Self.dottedDashLengths), part: .edge)
        builder.fill(filledMarks, .line, part: .marker)
        builder.stroke(strokedMarks, .line, line, part: .marker)
        for edge in styledEdges {
            let paint = edge.style.stroke.map(DiagramPaint.color) ?? .line
            builder.stroke(edge.line, paint, .rounded(lineWidth: edge.lineWidth, dashLengths: edge.dashLengths), part: .edge)
            builder.fill(edge.filledMarks, paint, part: .marker)
            builder.stroke(edge.strokedMarks, paint, line, part: .marker)
        }
        clusters.referenceAddCrossedTitles(to: &builder)
        builder.fill(edgeTextPatches, .background, part: .labelBackground)
        builder.texts(edgeTexts, .foreground, part: .edgeLabel)
        builder.fill(nodeFills, .surface, part: .node)
        builder.stroke(nodeOutlines, .border, line, part: .node)
        for layer in layeredNodeShapes { layer.referenceAdd(to: &builder, style: nil, stroke: line) }
        for node in styledNodes {
            if !node.layers.isEmpty {
                let stroke = DiagramStroke.rounded(lineWidth: node.lineWidth, dashLengths: node.style.strokeDashLengths ?? [])
                for layer in node.layers { layer.referenceAdd(to: &builder, style: node.style, stroke: stroke) }
                continue
            }
            if let shape = node.fill { builder.fill(shape, node.style.fill.map(DiagramPaint.color) ?? .surface, part: .node) }
            builder.stroke(node.outline, node.style.stroke.map(DiagramPaint.color) ?? .border,
                           .rounded(lineWidth: node.lineWidth, dashLengths: node.style.strokeDashLengths ?? []), part: .node)
        }
        builder.texts(nodeTexts, .foreground, part: .label)
        for node in styledNodes { builder.text(node.text, node.style.textColor.map(DiagramPaint.color) ?? .foreground, part: .label) }
        builder.title(title)
    }
}

extension FlowchartShapeLayer {
    /// The piece in the usual colors, or in those a node's style sets: Pele's style overrides the fill and the stroke of
    /// every piece but a fork's or a junction's line-colored fill, and strokes a data store's box only when it sets a stroke.
    func referenceAdd(to builder: inout DiagramSceneBuilder, style: DiagramElementStyle?, stroke: DiagramStroke) {
        builder.keepNextShapeApart()
        let fillPaint = style?.fill.map(DiagramPaint.color) ?? .surface
        let strokePaint = style?.stroke.map(DiagramPaint.color) ?? .border
        switch painting {
        case .filledAndOutlined: builder.fillAndStroke(path, fill: fillPaint, stroke: strokePaint, stroke, part: .node)
        case .outlined: builder.stroke(path, strokePaint, stroke, part: .node)
        case .filledInLineColorAndOutlined: builder.fillAndStroke(path, fill: .line, stroke: strokePaint, stroke, part: .node)
        case .filledOnly:
            builder.fill(path, fillPaint, part: .node)
            if let color = style?.stroke { builder.stroke(path, .color(color), stroke, part: .node) }
        }
    }
}

extension FlowchartClusterDrawingParts {
    /// Each box's inside: the alternate surface at `fillOpacity`.
    static let referenceBoxPaint = DiagramPaint.alternateSurface.atOpacity(fillOpacity)

    /// The boxes behind everything: their fills depth by depth, their outlines and the titles no edge crosses.
    func referenceAddBoxes(to builder: inout DiagramSceneBuilder) {
        for depthFill in fillsByDepth { builder.fill(depthFill, Self.referenceBoxPaint, part: .cluster) }
        builder.stroke(outlines, .border, .rounded(lineWidth: FlowchartDrawingParts.lineWidth), part: .cluster)
        builder.texts(titles, .muted, part: .clusterLabel)
    }

    /// The titles edges run through, over the edges, each on a patch painted as its box is where it sits: the background,
    /// then the box's paint once for each box it is inside and its own.
    func referenceAddCrossedTitles(to builder: inout DiagramSceneBuilder) {
        for (depth, patches) in crossedTitlePatchesByDepth.enumerated() where !patches.isEmpty {
            builder.fill(patches, .background, part: .labelBackground)
            for _ in 0...depth { builder.fill(patches, Self.referenceBoxPaint, part: .labelBackground) }
        }
        builder.texts(crossedTitles, .muted, part: .clusterLabel)
    }
}

/// 0.7.0's swimlane scene, made from the public drawing parts' Core Graphics paths.
enum ReferenceSwimlaneScene {
    static func scene(layout: SwimlaneLayout) -> DiagramScene {
        var builder = DiagramSceneBuilder()
        SwimlaneDrawingParts(layout: layout).referenceAddScene(to: &builder)
        return builder.scene(size: layout.size, font: layout.flowchart.font)
    }
}

extension SwimlaneDrawingParts {
    func referenceAddScene(to builder: inout DiagramSceneBuilder) {
        let line = DiagramStroke(lineWidth: FlowchartDrawingParts.lineWidth)
        builder.stroke(laneOutlines, .border, line, part: .cluster)
        builder.fillAndStroke(titleBands, fill: .alternateSurface, stroke: .border, line, part: .cluster)
        for title in titles { builder.text(title, .muted, rotation: areTitlesTurned ? Self.turnedTitleRotation : nil, part: .clusterLabel) }
        flowchart.referenceAddScene(to: &builder)
    }
}

/// 0.7.0's agent flow scene, its paths Core Graphics paths.
enum ReferenceAgentFlowScene {
    /// The agent flow's painting, back to front as Pele's SVG has it: the title; each flow's box, a wash of its series
    /// color at 6% with an outline in it, and its title in the muted color; the edges in the line color, a reference
    /// dotted, with their marks; the patches behind edge text and that text; each node's shape, a wash of its kind's
    /// series color at 14% outlined in it (a collapsed flow's at 6%, with a dashed line and three dots), and its text.
    /// A fill a style sets replaces the wash and stays opaque, and the text on it takes Pele's dark or white ink. An edge
    /// that one filled flow holds whole is drawn in that fill's ink, and one that crosses a filled flow's border runs
    /// over a casing of the page's color, painted after the flows (Pele's `overFills` and `edgeCasing`).
    static func scene(layout: AgentFlowLayout) -> DiagramScene {
        var builder = DiagramSceneBuilder()
        builder.title(layout.title)
        let line = DiagramStroke.rounded(lineWidth: FlowchartDrawingParts.lineWidth)
        for flow in layout.flows { ReferenceAgentFlowScenePainting.add(flow, to: &builder, line: line) }
        let inks = ReferenceAgentFlowScenePainting.inks(of: layout)
        for (edge, ink) in zip(layout.edges, inks) where ink == .cased { ReferenceAgentFlowScenePainting.addCasing(of: edge, to: &builder) }
        for (edge, ink) in zip(layout.edges, inks) { ReferenceAgentFlowScenePainting.add(edge, ink: ink, to: &builder, line: line) }
        for edge in layout.edges where edge.text != nil { ReferenceAgentFlowScenePainting.addText(of: edge, to: &builder) }
        for node in layout.nodes { ReferenceAgentFlowScenePainting.add(node, to: &builder, line: line) }
        return builder.scene(size: layout.size, font: layout.font)
    }
}

/// How each part of an agent flow is painted.
enum ReferenceAgentFlowScenePainting {
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
    static func addCasing(of edge: AgentFlowLayoutEdge, to builder: inout DiagramSceneBuilder) {
        let casing = DiagramStroke.rounded(lineWidth: (edge.style?.strokeWidth ?? FlowchartDrawingParts.lineWidth) + casingExtraWidth)
        builder.stroke(DiagramEdgeDrawing.path(edge.path), .background, casing, part: .casing)
        guard let mark = edge.targetMark else { return }
        let filled = CGMutablePath()
        let stroked = CGMutablePath()
        DiagramEdgeDrawing.addMark(mark, filled: filled, stroked: stroked)
        builder.fillAndStroke(filled, fill: .background, stroke: .background, casing, part: .casing)
        builder.stroke(stroked, .background, casing, part: .casing)
    }

    /// The edge's line and mark in its style's color, or in the ink of the filled flow that holds it.
    static func add(_ edge: AgentFlowLayoutEdge, ink: BlockEdgeInk, to builder: inout DiagramSceneBuilder, line: DiagramStroke) {
        var paint = edge.style?.stroke.map(DiagramPaint.color) ?? .line
        if case .inked(let color) = ink { paint = .color(color) }
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
        builder.text(node.text, textPaint(node.style, fallback: .foreground), isBold: node.isBold, isItalic: node.isItalic, part: .label)
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
