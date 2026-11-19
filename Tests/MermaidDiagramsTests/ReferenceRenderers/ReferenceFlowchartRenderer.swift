/**
 * File: ReferenceFlowchartRenderer.swift
 * --------------------------------------
 * Layer: Tests
 * Description: FlowchartRenderer's Core Graphics painting as it was before the scene, the reference
 *              DiagramSceneParityTests compares the scene's pixels with.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// The FlowchartRenderer as it painted before every type was painted from its scene, kept as the reference the scene's
/// pixels are compared with (`DiagramSceneParityTests`).
enum ReferenceFlowchartRenderer {
    static func draw(_ layout: FlowchartLayout, in context: CGContext, palette: DiagramPalette) {
        let parts = FlowchartDrawingParts(layout: layout)
        var text = DiagramTextDrawing(font: layout.font)
        context.saveGState()
        context.setLineCap(.round)
        context.setLineJoin(.round)
        drawClusters(parts.clusters, text: &text, in: context, palette: palette)
        stroke(parts.solidEdges, width: FlowchartDrawingParts.lineWidth, color: palette.line, in: context)
        stroke(parts.thickEdges, width: FlowchartDrawingParts.thickLineWidth, color: palette.line, in: context)
        context.setLineDash(phase: 0, lengths: FlowchartDrawingParts.dottedDashLengths)
        stroke(parts.dottedEdges, width: FlowchartDrawingParts.lineWidth, color: palette.line, in: context)
        context.setLineDash(phase: 0, lengths: [])
        fill(parts.filledMarks, color: palette.line, in: context)
        stroke(parts.strokedMarks, width: FlowchartDrawingParts.lineWidth, color: palette.line, in: context)
        drawStyledEdges(parts.styledEdges, in: context, palette: palette)
        drawCrossedClusterTitles(parts.clusters, text: &text, in: context, palette: palette)
        fill(parts.edgeTextPatches, color: palette.background, in: context)
        for edgeText in parts.edgeTexts { text.draw(edgeText, color: palette.foreground, in: context) }
        fill(parts.nodeFills, color: palette.surface, in: context)
        stroke(parts.nodeOutlines, width: FlowchartDrawingParts.lineWidth, color: palette.border, in: context)
        for layer in parts.layeredNodeShapes {
            draw(layer, fill: palette.surface, stroke: palette.border, strokesFilledOnly: false, width: FlowchartDrawingParts.lineWidth, palette: palette,
                 in: context)
        }
        drawStyledNodes(parts.styledNodes, in: context, palette: palette)
        for nodeText in parts.nodeTexts { text.draw(nodeText, color: palette.foreground, in: context) }
        for node in parts.styledNodes { text.draw(node.text, color: node.style.textColor?.cgColor ?? palette.foreground, in: context) }
        if let title = parts.title { text.draw(title, color: palette.foreground, isBold: true, in: context) }
        context.restoreGState()
    }

    /// The edges with a stroke or colors of their own, over the others: each line with its dashes and width, and its marks,
    /// in the color it sets or the usual line color.
    private static func drawStyledEdges(_ edges: [FlowchartStyledEdgeParts], in context: CGContext, palette: DiagramPalette) {
        for edge in edges {
            let color = edge.style.stroke?.cgColor ?? palette.line
            context.setLineDash(phase: 0, lengths: edge.dashLengths)
            stroke(edge.line, width: edge.lineWidth, color: color, in: context)
            context.setLineDash(phase: 0, lengths: [])
            fill(edge.filledMarks, color: color, in: context)
            stroke(edge.strokedMarks, width: FlowchartDrawingParts.lineWidth, color: color, in: context)
        }
    }

    /// The nodes with colors of their own: the inside in the fill they set, the outline in their stroke.
    private static func drawStyledNodes(_ nodes: [FlowchartStyledNodeParts], in context: CGContext, palette: DiagramPalette) {
        for node in nodes {
            if !node.layers.isEmpty {
                context.setLineDash(phase: 0, lengths: node.style.strokeDashLengths ?? [])
                for layer in node.layers {
                    draw(layer, fill: node.style.fill?.cgColor ?? palette.surface, stroke: node.style.stroke?.cgColor ?? palette.border,
                         strokesFilledOnly: node.style.stroke != nil, width: node.lineWidth, palette: palette, in: context)
                }
                context.setLineDash(phase: 0, lengths: [])
                continue
            }
            if let shape = node.fill { fill(shape, color: node.style.fill?.cgColor ?? palette.surface, in: context) }
            context.setLineDash(phase: 0, lengths: node.style.strokeDashLengths ?? [])
            stroke(node.outline, width: node.lineWidth, color: node.style.stroke?.cgColor ?? palette.border, in: context)
            context.setLineDash(phase: 0, lengths: [])
        }
    }

    /// The groups' boxes, behind everything: their fills depth by depth, their outlines and the titles no edge crosses.
    static func drawClusters(_ clusters: FlowchartClusterDrawingParts, text: inout DiagramTextDrawing, in context: CGContext,
                             palette: DiagramPalette) {
        let boxFill = clusterFill(palette)
        for depthFill in clusters.fillsByDepth { fill(depthFill, color: boxFill, in: context) }
        stroke(clusters.outlines, width: FlowchartDrawingParts.lineWidth, color: palette.border, in: context)
        for title in clusters.titles { text.draw(title, color: palette.muted, in: context) }
    }

    /// The titles edges run through, over the edges, each on a patch painted as its box is where it sits.
    static func drawCrossedClusterTitles(_ clusters: FlowchartClusterDrawingParts, text: inout DiagramTextDrawing, in context: CGContext,
                                         palette: DiagramPalette) {
        let boxFill = clusterFill(palette)
        for (depth, patches) in clusters.crossedTitlePatchesByDepth.enumerated() where !patches.isEmpty {
            fill(patches, color: palette.background, in: context)
            for _ in 0...depth { fill(patches, color: boxFill, in: context) }
        }
        for title in clusters.crossedTitles { text.draw(title, color: palette.muted, in: context) }
    }

    /// A piece of a shape painted piece by piece: filled, then stroked, as it says.
    private static func draw(_ layer: FlowchartShapeLayer, fill fillColor: CGColor, stroke strokeColor: CGColor, strokesFilledOnly: Bool, width: CGFloat,
                             palette: DiagramPalette, in context: CGContext) {
        switch layer.painting {
        case .filledAndOutlined:
            fill(layer.path, color: fillColor, in: context)
            stroke(layer.path, width: width, color: strokeColor, in: context)
        case .outlined: stroke(layer.path, width: width, color: strokeColor, in: context)
        case .filledInLineColorAndOutlined:
            fill(layer.path, color: palette.line, in: context)
            stroke(layer.path, width: width, color: strokeColor, in: context)
        case .filledOnly:
            fill(layer.path, color: fillColor, in: context)
            if strokesFilledOnly { stroke(layer.path, width: width, color: strokeColor, in: context) }
        }
    }

    private static func clusterFill(_ palette: DiagramPalette) -> CGColor {
        palette.alternateSurface.copy(alpha: palette.alternateSurface.alpha * FlowchartClusterDrawingParts.fillOpacity) ?? palette.alternateSurface
    }

    private static func stroke(_ path: CGPath, width: CGFloat, color: CGColor, in context: CGContext) {
        guard !path.isEmpty else { return }
        context.setStrokeColor(color)
        context.setLineWidth(width)
        context.addPath(path)
        context.strokePath()
    }

    private static func fill(_ path: CGPath, color: CGColor, in context: CGContext) {
        guard !path.isEmpty else { return }
        context.setFillColor(color)
        context.addPath(path)
        context.fillPath()
    }
}
