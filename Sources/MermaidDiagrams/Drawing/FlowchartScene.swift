/**
 * File: FlowchartScene.swift
 * --------------------------
 * Layer: Core
 * Description: A laid-out flowchart's scene: its drawing parts back to front in the colors' roles, as Pele paints them.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 23/11/2026
 */

import CoreGraphics

extension DiagramScene {
    /// The flowchart's painting: the groups' boxes and the titles no edge crosses, the edges and their marks, the
    /// styled edges, the titles edges cross on their patches, the patches behind edge text and that text, the node
    /// shapes, those painted piece by piece, the styled ones, the nodes' text, the title.
    public init(layout: FlowchartLayout) {
        var builder = DiagramSceneBuilder()
        FlowchartDrawingParts(layout: layout).addScene(to: &builder)
        self = builder.scene(size: layout.size, font: layout.font)
    }
}

extension FlowchartDrawingParts {
    /// Every line is drawn with round caps and joins.
    func addScene(to builder: inout DiagramSceneBuilder) {
        let line = DiagramStroke.rounded(lineWidth: Self.lineWidth)
        clusters.addBoxes(to: &builder)
        builder.stroke(solidEdgesScenePath, .line, line, part: .edge)
        builder.stroke(thickEdgesScenePath, .line, .rounded(lineWidth: Self.thickLineWidth), part: .edge)
        builder.stroke(dottedEdgesScenePath, .line, .rounded(lineWidth: Self.lineWidth, dashLengths: Self.dottedDashLengths), part: .edge)
        builder.fill(filledMarksScenePath, .line, part: .marker)
        builder.stroke(strokedMarksScenePath, .line, line, part: .marker)
        for edge in styledEdges {
            let paint = edge.style.stroke.map(DiagramPaint.color) ?? .line
            builder.stroke(edge.lineScenePath, paint, .rounded(lineWidth: edge.lineWidth, dashLengths: edge.dashLengths), part: .edge)
            builder.fill(edge.filledMarksScenePath, paint, part: .marker)
            builder.stroke(edge.strokedMarksScenePath, paint, line, part: .marker)
        }
        clusters.addCrossedTitles(to: &builder)
        builder.fill(edgeTextPatchesScenePath, .background, part: .labelBackground)
        builder.texts(edgeTexts, .foreground, part: .edgeLabel)
        builder.fill(nodeFillsScenePath, .surface, part: .node)
        builder.stroke(nodeOutlinesScenePath, .border, line, part: .node)
        for layer in layeredNodeShapes { layer.add(to: &builder, style: nil, stroke: line) }
        for node in styledNodes {
            if !node.layers.isEmpty {
                let stroke = DiagramStroke.rounded(lineWidth: node.lineWidth, dashLengths: node.style.strokeDashLengths ?? [])
                for layer in node.layers { layer.add(to: &builder, style: node.style, stroke: stroke) }
                continue
            }
            if let shape = node.fillScenePath { builder.fill(shape, node.style.fill.map(DiagramPaint.color) ?? .surface, part: .node) }
            builder.stroke(node.outlineScenePath, node.style.stroke.map(DiagramPaint.color) ?? .border,
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
    func add(to builder: inout DiagramSceneBuilder, style: DiagramElementStyle?, stroke: DiagramStroke) {
        builder.keepNextShapeApart()
        let fillPaint = style?.fill.map(DiagramPaint.color) ?? .surface
        let strokePaint = style?.stroke.map(DiagramPaint.color) ?? .border
        switch painting {
        case .filledAndOutlined: builder.fillAndStroke(pathScenePath, fill: fillPaint, stroke: strokePaint, stroke, part: .node)
        case .outlined: builder.stroke(pathScenePath, strokePaint, stroke, part: .node)
        case .filledInLineColorAndOutlined: builder.fillAndStroke(pathScenePath, fill: .line, stroke: strokePaint, stroke, part: .node)
        case .filledOnly:
            builder.fill(pathScenePath, fillPaint, part: .node)
            if let color = style?.stroke { builder.stroke(pathScenePath, .color(color), stroke, part: .node) }
        }
    }
}

extension FlowchartClusterDrawingParts {
    /// Each box's inside: the alternate surface at `fillOpacity`.
    static let boxPaint = DiagramPaint.alternateSurface.atOpacity(fillOpacity)

    /// The boxes behind everything: their fills depth by depth, their outlines and the titles no edge crosses.
    func addBoxes(to builder: inout DiagramSceneBuilder) {
        for depthFill in fillsByDepthScenePaths { builder.fill(depthFill, Self.boxPaint, part: .cluster) }
        builder.stroke(outlinesScenePath, .border, .rounded(lineWidth: FlowchartDrawingParts.lineWidth), part: .cluster)
        builder.texts(titles, .muted, part: .clusterLabel)
    }

    /// The titles edges run through, over the edges, each on a patch painted as its box is where it sits: the background,
    /// then the box's paint once for each box it is inside and its own.
    func addCrossedTitles(to builder: inout DiagramSceneBuilder) {
        for (depth, patches) in crossedTitlePatchesByDepthScenePaths.enumerated() where !patches.isEmpty {
            builder.fill(patches, .background, part: .labelBackground)
            for _ in 0...depth { builder.fill(patches, Self.boxPaint, part: .labelBackground) }
        }
        builder.texts(crossedTitles, .muted, part: .clusterLabel)
    }
}
