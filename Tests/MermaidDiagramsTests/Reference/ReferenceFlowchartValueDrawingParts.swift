/**
 * File: ReferenceFlowchartValueDrawingParts.swift
 * -----------------------------------------------
 * Layer: Tests
 * Description: 0.7.0's flowchart drawing parts and scene, frozen as main ba176e5 made them from the layout's nodes and
 *              edges kept as values (FlowchartLayoutNode, FlowchartLayoutEdge), with no flat record read, so that the
 *              scene and the public drawing parts read from the layout's records are compared with code that never
 *              reads them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// 0.7.0's flowchart scene, made from drawing parts built from the layout's nodes and edges as values.
enum ReferenceFlowchartValueScene {
    static func scene(layout: FlowchartLayout) -> DiagramScene {
        var builder = DiagramSceneBuilder()
        ReferenceFlowchartValueDrawingParts(layout: layout).addScene(to: &builder)
        return builder.scene(size: layout.size, font: layout.font)
    }
}

/// main ba176e5's `FlowchartDrawingParts`, built from `FlowchartLayout.nodes` and `.edges`.
struct ReferenceFlowchartValueDrawingParts {
    let clusters: FlowchartClusterDrawingParts
    let solidEdges: CGPath
    let thickEdges: CGPath
    let dottedEdges: CGPath
    let filledMarks: CGPath
    let strokedMarks: CGPath
    let edgeTextPatches: CGPath
    let edgeTexts: [DiagramTextBlock]
    let nodeFills: CGPath
    let nodeOutlines: CGPath
    let layeredNodeShapes: [FlowchartShapeLayer]
    let nodeTexts: [DiagramTextBlock]
    let styledEdges: [FlowchartStyledEdgeParts]
    let styledNodes: [FlowchartStyledNodeParts]
    let title: DiagramTextBlock?

    init(layout: FlowchartLayout) {
        let layoutNodes = layout.nodes
        let layoutEdges = layout.edges
        let maker = DiagramCoreGraphicsPaths()
        let edges = ReferenceFlowchartValueEdgePaths(edges: layoutEdges, making: maker)
        let nodes = ReferenceFlowchartValueNodePaths(nodes: layoutNodes, making: maker)
        clusters = FlowchartClusterDrawingParts(clusters: layout.clusters)
        solidEdges = edges.solid.path
        thickEdges = edges.thick.path
        dottedEdges = edges.dotted.path
        filledMarks = edges.filledMarks.path
        strokedMarks = edges.strokedMarks.path
        edgeTextPatches = edges.textPatches.path
        edgeTexts = layoutEdges.compactMap(\.text)
        nodeFills = nodes.fills.path
        nodeOutlines = nodes.outlines.path
        styledEdges = layoutEdges.compactMap { edge in
            guard ReferenceFlowchartValueEdgePaths.isStyled(edge), let style = edge.style else { return nil }
            return FlowchartStyledEdgeParts(edge: edge, style: style)
        }
        var layered: [FlowchartShapeLayer] = []
        var texts: [DiagramTextBlock] = []
        var styled: [FlowchartStyledNodeParts] = []
        for node in layoutNodes {
            if let style = node.style {
                styled.append(FlowchartStyledNodeParts(node: node, style: style))
                continue
            }
            texts.append(node.text)
            if node.asset == nil, let layers = FlowchartShapeDrawing.layers(of: node.shape, in: node.frame) { layered.append(contentsOf: layers) }
        }
        layeredNodeShapes = layered
        nodeTexts = texts
        styledNodes = styled
        title = layout.title
    }

    /// As `FlowchartDrawingParts.referenceAddScene(to:)` adds the public parts.
    func addScene(to builder: inout DiagramSceneBuilder) {
        let line = DiagramStroke.rounded(lineWidth: FlowchartDrawingParts.lineWidth)
        clusters.referenceAddBoxes(to: &builder)
        builder.stroke(solidEdges, .line, line, part: .edge)
        builder.stroke(thickEdges, .line, .rounded(lineWidth: FlowchartDrawingParts.thickLineWidth), part: .edge)
        builder.stroke(dottedEdges, .line, .rounded(lineWidth: FlowchartDrawingParts.lineWidth, dashLengths: FlowchartDrawingParts.dottedDashLengths),
                       part: .edge)
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

/// main ba176e5's `FlowchartEdgePaths`, over the layout's edges as values, in Core Graphics paths.
struct ReferenceFlowchartValueEdgePaths {
    let solid: DiagramCoreGraphicsPath
    let thick: DiagramCoreGraphicsPath
    let dotted: DiagramCoreGraphicsPath
    let filledMarks: DiagramCoreGraphicsPath
    let strokedMarks: DiagramCoreGraphicsPath
    let textPatches: DiagramCoreGraphicsPath

    init(edges: [FlowchartLayoutEdge], making maker: DiagramCoreGraphicsPaths) {
        solid = maker.makePath()
        thick = maker.makePath()
        dotted = maker.makePath()
        filledMarks = maker.makePath()
        strokedMarks = maker.makePath()
        textPatches = maker.makePath()
        for edge in edges {
            if !Self.isStyled(edge) { addLineAndMarks(of: edge, making: maker) }
            if let text = edge.text {
                textPatches.addPath(maker.roundedRectangle(text.frame.insetBy(dx: -FlowchartDrawingParts.edgeTextPatchExtraWidth / 2, dy: 0),
                                                           cornerWidth: FlowchartDrawingParts.edgeTextPatchCornerRadius,
                                                           cornerHeight: FlowchartDrawingParts.edgeTextPatchCornerRadius))
            }
        }
    }

    static func isStyled(_ edge: FlowchartLayoutEdge) -> Bool {
        if case .none = edge.style { return false }
        return edge.stroke != .invisible
    }

    private func addLineAndMarks(of edge: FlowchartLayoutEdge, making maker: DiagramCoreGraphicsPaths) {
        let grouped: DiagramCoreGraphicsPath
        switch edge.stroke {
        case .solid: grouped = solid
        case .thick: grouped = thick
        case .dotted: grouped = dotted
        case .invisible: return
        }
        let line = maker.makePath()
        DiagramEdgeDrawing.record(edge.path, into: line)
        grouped.addPath(line)
        if let mark = edge.sourceMark { DiagramEdgeDrawing.addMark(mark, filled: filledMarks, stroked: strokedMarks) }
        if let mark = edge.targetMark { DiagramEdgeDrawing.addMark(mark, filled: filledMarks, stroked: strokedMarks) }
    }
}

/// main ba176e5's `FlowchartNodePaths`, over the layout's nodes as values, in Core Graphics paths.
struct ReferenceFlowchartValueNodePaths {
    let fills: DiagramCoreGraphicsPath
    let outlines: DiagramCoreGraphicsPath

    init(nodes: [FlowchartLayoutNode], making maker: DiagramCoreGraphicsPaths) {
        fills = maker.makePath()
        outlines = maker.makePath()
        for node in nodes where node.hasUsualLook {
            if let asset = node.asset {
                if let frame = FlowchartNodeAssetDrawing.frame(of: asset, in: node, making: maker) { fills.addPath(frame, alsoTo: outlines) }
                continue
            }
            if FlowchartLayeredShapeDrawing.isPaintedPieceByPiece(node.shape) { continue }
            if let outline = FlowchartShapeDrawing.outline(of: node.shape, in: node.frame, making: maker) { fills.addPath(outline, alsoTo: outlines) }
            if let innerLines = FlowchartShapeDrawing.innerLines(of: node.shape, in: node.frame, making: maker) { outlines.addPath(innerLines) }
        }
    }
}
