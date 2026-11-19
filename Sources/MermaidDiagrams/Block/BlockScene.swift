/**
 * File: BlockScene.swift
 * ----------------------
 * Layer: Core
 * Description: A laid-out block diagram's scene, back to front as Pele writes its SVG: the title, the composites with
 *              their titles, the edges and their marks, the blocks and arrows with their text, the edges' text.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */

import CoreGraphics

extension DiagramScene {
    /// The block diagram's painting, in Pele's order: the bold title; each composite's box in the second surface at half
    /// opacity (the color its style fills it with at full) outlined in the border color, and its title in the muted
    /// color; the casings of the edges that cross the border of a composite a style fills (`BlockEdgeInk`); each edge's
    /// line in the line color (or in the ink of the filled composite that holds it), 2.5 points wide for `==` and dotted
    /// for `.-`, with its marks; each block's shape or arrow in the surface color outlined in the border color, its
    /// colors as its style sets, and its text; each edge's text on a patch of the page's color.
    public init(layout: BlockLayout) {
        var builder = DiagramSceneBuilder()
        builder.title(layout.title)
        for composite in layout.composites { BlockScenePaths.add(composite, to: &builder) }
        let inks = BlockEdgeInk.inks(of: layout.edges, over: layout.composites)
        for (edge, ink) in zip(layout.edges, inks) where ink == .cased { BlockScenePaths.addCasing(of: edge, to: &builder) }
        for (edge, ink) in zip(layout.edges, inks) {
            guard case .inked(let color) = ink else {
                BlockScenePaths.add(edge, in: .line, to: &builder)
                continue
            }
            BlockScenePaths.add(edge, in: .color(color), to: &builder)
        }
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

    /// The width a casing adds to the line it lies under, Pele's `CASE`.
    static let casingExtraWidth: CGFloat = 4

    /// `edge`'s line and marks in `paint`.
    static func add(_ edge: BlockLayoutEdge, in paint: DiagramPaint, to builder: inout DiagramSceneBuilder) {
        let stroke = DiagramStroke(lineWidth: edge.isThick ? thickLineWidth : 1, dashLengths: edge.isDotted ? dottedDashLengths : [], lineCap: .round)
        builder.stroke(DiagramEdgeDrawing.path(edge.path), paint, stroke, part: .edge)
        let (filled, stroked) = marks(of: edge)
        builder.fill(filled, paint, part: .marker)
        builder.stroke(stroked, paint, DiagramStroke(lineWidth: 1, lineCap: .round), part: .marker)
    }

    /// The stroke of the page's color under `edge` and its marks, 4 points wider than its line, with round ends and
    /// corners, and its marks filled and outlined in it: Pele's `edgeCasing`.
    static func addCasing(of edge: BlockLayoutEdge, to builder: inout DiagramSceneBuilder) {
        let casing = DiagramStroke.rounded(lineWidth: (edge.isThick ? thickLineWidth : 1) + casingExtraWidth)
        builder.stroke(DiagramEdgeDrawing.path(edge.path), .background, casing, part: .casing)
        let (filled, stroked) = marks(of: edge)
        builder.fillAndStroke(filled, fill: .background, stroke: .background, casing, part: .casing)
        builder.stroke(stroked, .background, casing, part: .casing)
    }

    /// The marks at `edge`'s ends: those filled (arrows and circles) and those stroked (crosses).
    private static func marks(of edge: BlockLayoutEdge) -> (filled: CGPath, stroked: CGPath) {
        let filled = CGMutablePath()
        let stroked = CGMutablePath()
        for mark in [edge.sourceMark, edge.targetMark].compactMap({ mark in mark }) { DiagramEdgeDrawing.addMark(mark, filled: filled, stroked: stroked) }
        return (filled, stroked)
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
