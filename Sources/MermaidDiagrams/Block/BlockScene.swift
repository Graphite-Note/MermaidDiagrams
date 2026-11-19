/**
 * File: BlockScene.swift
 * ----------------------
 * Layer: Core
 * Description: A laid-out block diagram's scene, back to front as Pele writes its SVG: the title, the composites with
 *              their titles, the edges and their marks, the blocks and arrows with their text, the edges' text.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

extension DiagramScene {
    /// The block diagram's painting, in Pele's order: the bold title; each composite's box in the second surface at half
    /// opacity (the color its style fills it with at full) outlined in the border color, and its title in the muted
    /// color; each edge's line in the line color, 2.5 points wide for `==` and dotted for `.-`, with its marks; each
    /// block's shape or arrow in the surface color outlined in the border color, its colors as its style sets, and its
    /// text; each edge's text on a patch of the page's color.
    public init(layout: BlockLayout) {
        var builder = DiagramSceneBuilder()
        builder.title(layout.title)
        for composite in layout.composites { BlockScenePaths.add(composite, to: &builder) }
        for edge in layout.edges { BlockScenePaths.add(edge, to: &builder) }
        for node in layout.nodes { BlockScenePaths.add(node, to: &builder) }
        for edge in layout.edges {
            guard let text = edge.text else { continue }
            let patch = text.frame.insetBy(dx: -BlockScenePaths.textPatchExtraWidth / 2, dy: 0)
            builder.fill(CGPath(roundedRect: patch, cornerWidth: BlockScenePaths.textPatchCornerRadius, cornerHeight: BlockScenePaths.textPatchCornerRadius,
                                transform: nil), .background, part: .labelBackground)
            builder.text(text, .foreground, part: .edgeLabel)
        }
        self = builder.scene(size: layout.size, font: layout.font)
    }
}

/// The shapes of a block diagram's scene.
enum BlockScenePaths {
    /// Pele's `--pele-radius`, round a composite's corners.
    static let cornerRadius: CGFloat = 4
    static let compositeFillOpacity: CGFloat = 0.5
    static let textPatchExtraWidth: CGFloat = 8
    static let textPatchCornerRadius: CGFloat = 3
    static let thickLineWidth: CGFloat = 2.5
    static let dottedDashLengths: [CGFloat] = [3, 4]

    static func add(_ composite: BlockLayoutComposite, to builder: inout DiagramSceneBuilder) {
        let style = composite.appearance.style
        let box = CGPath(roundedRect: composite.frame, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        let fill = style.fill.map(DiagramPaint.color) ?? DiagramPaint.alternateSurface.atOpacity(compositeFillOpacity)
        builder.fillAndStroke(box, fill: fill, stroke: style.stroke.map(DiagramPaint.color) ?? .border, outlineStroke(style), part: .cluster)
        builder.text(composite.title, composite.appearance.textColor.map(DiagramPaint.color) ?? .muted, isBold: composite.appearance.isBold,
                     isItalic: composite.appearance.isItalic, part: .clusterLabel)
    }

    static func add(_ edge: BlockLayoutEdge, to builder: inout DiagramSceneBuilder) {
        let stroke = DiagramStroke(lineWidth: edge.isThick ? thickLineWidth : 1, dashLengths: edge.isDotted ? dottedDashLengths : [], lineCap: .round)
        builder.stroke(DiagramEdgeDrawing.path(edge.path), .line, stroke, part: .edge)
        let filled = CGMutablePath()
        let stroked = CGMutablePath()
        for mark in [edge.sourceMark, edge.targetMark].compactMap({ mark in mark }) { DiagramEdgeDrawing.addMark(mark, filled: filled, stroked: stroked) }
        builder.fill(filled, .line, part: .marker)
        builder.stroke(stroked, .line, DiagramStroke(lineWidth: 1, lineCap: .round), part: .marker)
    }

    static func add(_ node: BlockLayoutNode, to builder: inout DiagramSceneBuilder) {
        let style = node.appearance.style
        let fill = style.fill.map(DiagramPaint.color) ?? .surface
        let strokePaint = style.stroke.map(DiagramPaint.color) ?? .border
        switch node.form {
        case .arrow(let corners):
            let outline = CGMutablePath()
            outline.addLines(between: corners)
            outline.closeSubpath()
            var stroke = outlineStroke(style)
            stroke = DiagramStroke(lineWidth: stroke.lineWidth, dashLengths: stroke.dashLengths, lineJoin: .round)
            builder.fillAndStroke(outline, fill: fill, stroke: strokePaint, stroke, part: .node)
        case .shape(let shape):
            if let outline = FlowchartShapeDrawing.outline(of: shape, in: node.frame) {
                builder.fillAndStroke(outline, fill: fill, stroke: strokePaint, outlineStroke(style), part: .node)
            }
            if let lines = FlowchartShapeDrawing.innerLines(of: shape, in: node.frame) { builder.stroke(lines, strokePaint, outlineStroke(style), part: .node) }
        }
        builder.text(node.text, node.appearance.textColor.map(DiagramPaint.color) ?? .foreground, isBold: node.appearance.isBold,
                     isItalic: node.appearance.isItalic, part: .label)
    }

    /// An outline's stroke: a point wide unless the style sets its width, dashed as the style sets.
    private static func outlineStroke(_ style: DiagramElementStyle) -> DiagramStroke {
        DiagramStroke(lineWidth: style.strokeWidth ?? 1, dashLengths: style.strokeDashLengths ?? [])
    }
}

/// Draws a laid-out block diagram into a Core Graphics context whose origin is the layout's top left and whose y runs
/// down, back to front, by painting its scene (`DiagramScene(layout:)`) with `DiagramSceneRenderer`.
public enum BlockRenderer {
    public static func draw(_ layout: BlockLayout, in context: CGContext, palette: DiagramPalette) {
        DiagramSceneRenderer.draw(DiagramScene(layout: layout), in: context, palette: palette)
    }
}
