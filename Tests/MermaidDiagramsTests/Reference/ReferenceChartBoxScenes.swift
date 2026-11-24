/**
 * File: ReferenceChartBoxScenes.swift
 * -----------------------------------
 * Layer: Tests
 * Description: 0.7.0's treemap, Venn and block scenes, frozen as main 2a0cc65 made them from Core Graphics paths (the
 *              treemap's drawing parts as they were, the Venn and block shapes as Core Graphics paths), which the scenes
 *              recorded into lanes are compared with.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

extension ReferenceChartScene {
    /// The treemap's painting: the title, the sections as tints of their series colors with their names and totals, then the
    /// leaves in their series colors with their names and values.
    static func scene(layout: TreemapLayout) -> DiagramScene {
        var builder = DiagramSceneBuilder()
        ReferenceTreemapDrawingParts(layout: layout).referenceAddScene(to: &builder)
        return builder.scene(size: layout.size, font: layout.font, seriesColors: layout.seriesColors)
    }
}

extension ReferenceTreemapDrawingParts {
    func referenceAddScene(to builder: inout DiagramSceneBuilder) {
        builder.title(title)
        for box in sectionBoxes { builder.referenceAdd(box, part: .section) }
        for name in sectionNames { builder.referenceText(name, part: .label) }
        for value in sectionValues { builder.referenceText(value, part: .value) }
        for box in leafBoxes { builder.referenceAdd(box, part: .leaf) }
        for name in leafNames { builder.referenceText(name, part: .label) }
        for value in leafValues { builder.referenceText(value, part: .value) }
    }
}

extension DiagramSceneBuilder {
    /// A text in its paint, weight and slant.
    fileprivate mutating func referenceText(_ text: TreemapTextParts, part: DiagramScenePart) {
        self.text(text.block, text.paint, isBold: text.isBold, isItalic: text.isItalic, part: part)
    }

    /// A box filled, outlined, both or neither, as its parts say.
    fileprivate mutating func referenceAdd(_ box: TreemapBoxParts, part: DiagramScenePart) {
        switch (box.fill, box.outline) {
        case (let fill?, let outline?): fillAndStroke(box.path, fill: fill, stroke: outline, box.stroke, part: part)
        case (let fill?, nil): self.fill(box.path, fill, part: part)
        case (nil, let outline?): stroke(box.path, outline, box.stroke, part: part)
        case (nil, nil): break
        }
    }
}

/// A laid-out treemap's geometry grouped by how it is painted, so that drawing it in any colors is a few fills, strokes and
/// texts, by Core Graphics (`TreemapRenderer`) or by a view's own shapes. Back to front, as Pele draws: the title, the
/// sections' boxes and their names and totals, then the leaves' boxes and their names and values.
struct ReferenceTreemapDrawingParts {
    let sectionBoxes: [TreemapBoxParts]
    /// The sections' names, drawn bold unless their class sets a lighter weight.
    let sectionNames: [TreemapTextParts]
    /// The sections' totals, drawn in the muted color unless a class colors the text.
    let sectionValues: [TreemapTextParts]
    let leafBoxes: [TreemapBoxParts]
    let leafNames: [TreemapTextParts]
    let leafValues: [TreemapTextParts]
    /// The title, drawn bold, or nil.
    let title: DiagramTextBlock?

    /// The width of a box's outline.
    static let lineWidth: CGFloat = 1
    /// How opaque a section's tint of its series color is.
    static let sectionFillOpacity: CGFloat = 0.12

    init(layout: TreemapLayout) {
        var sectionBoxes: [TreemapBoxParts] = []
        var sectionNames: [TreemapTextParts] = []
        var sectionValues: [TreemapTextParts] = []
        var leafBoxes: [TreemapBoxParts] = []
        var leafNames: [TreemapTextParts] = []
        var leafValues: [TreemapTextParts] = []
        for box in layout.boxes {
            let style = box.style
            // Pele's ink on a fill a class sets (none for a fill whose color is not read), else on the box's series color
            // where the theme variables set it.
            let setsFill = style.fill != nil || box.textStyle.setsFill == true
            let contrast = setsFill ? TreemapInk.paint(onFill: style.fill) : layout.seriesColors.ink(ofSeries: box.seriesIndex).map(DiagramPaint.color)
            let isBold = box.textStyle.isBold ?? false
            let isItalic = box.textStyle.isItalic ?? false
            if box.isSection {
                if box.hasHeader { sectionBoxes.append(Self.sectionBox(box)) }
                let namePaint = style.textColor.map(DiagramPaint.color) ?? contrast ?? .foreground
                if let name = box.name {
                    sectionNames.append(TreemapTextParts(block: name, paint: namePaint, isBold: box.textStyle.isBold ?? true, isItalic: isItalic))
                }
                if let value = box.value {
                    sectionValues.append(TreemapTextParts(block: value, paint: style.textColor.map(DiagramPaint.color) ?? contrast ?? .muted, isBold: isBold,
                                                          isItalic: isItalic))
                }
            } else {
                leafBoxes.append(Self.leafBox(box))
                let paint = style.textColor.map(DiagramPaint.color) ?? contrast ?? .background
                if let name = box.name { leafNames.append(TreemapTextParts(block: name, paint: paint, isBold: isBold, isItalic: isItalic)) }
                if let value = box.value { leafValues.append(TreemapTextParts(block: value, paint: paint, isBold: isBold, isItalic: isItalic)) }
            }
        }
        self.sectionBoxes = sectionBoxes
        self.sectionNames = sectionNames
        self.sectionValues = sectionValues
        self.leafBoxes = leafBoxes
        self.leafNames = leafNames
        self.leafValues = leafValues
        title = layout.title
    }

    /// A section's box: a tint of its series color and an outline in it, unless its class gives a fill or an outline.
    private static func sectionBox(_ box: TreemapLayoutBox) -> TreemapBoxParts {
        let series = DiagramPaint.series(box.seriesIndex)
        return TreemapBoxParts(path: roundedPath(box), fill: box.style.fill.map(DiagramPaint.color) ?? series.atOpacity(sectionFillOpacity),
                               outline: box.style.stroke.map(DiagramPaint.color) ?? series, stroke: stroke(of: box.style))
    }

    /// A leaf's box: its series color, with an outline only where its class gives one.
    private static func leafBox(_ box: TreemapLayoutBox) -> TreemapBoxParts {
        TreemapBoxParts(path: roundedPath(box), fill: box.style.fill.map(DiagramPaint.color) ?? .series(box.seriesIndex),
                        outline: box.style.stroke.map(DiagramPaint.color), stroke: stroke(of: box.style))
    }

    private static func stroke(of style: DiagramElementStyle) -> DiagramStroke {
        DiagramStroke(lineWidth: style.strokeWidth ?? lineWidth, dashLengths: style.strokeDashLengths ?? [])
    }

    private static func roundedPath(_ box: TreemapLayoutBox) -> CGPath {
        let radius = min(box.cornerRadius, box.frame.width / 2, box.frame.height / 2)
        return CGPath(roundedRect: box.frame, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }
}

extension ReferenceChartScene {
    /// The Venn diagram's painting, back to front as Pele writes it: the title, each circle filled in its series color at
    /// a fifth of its opacity and outlined in it (or in its style's colors), the overlaps a style gives a look, and each
    /// region's lines, a set's label in the text color and its texts in the muted color unless a color is given.
    static func scene(layout: VennLayout) -> DiagramScene {
        var builder = DiagramSceneBuilder()
        builder.title(layout.title)
        for set in layout.sets {
            let circle = CGPath(ellipseIn: CGRect(x: set.center.x - set.radius, y: set.center.y - set.radius, width: 2 * set.radius,
                                                  height: 2 * set.radius), transform: nil)
            let appearance = set.appearance
            builder.fillAndStroke(circle, fill: ReferenceVennScenePaint.fill(appearance, usual: .series(set.seriesIndex), usualOpacity: ReferenceVennScenePaint.setFillOpacity),
                                  stroke: ReferenceVennScenePaint.stroke(appearance, usual: .series(set.seriesIndex)), ReferenceVennScenePaint.stroke(of: appearance),
                                  part: .vennSet)
        }
        for overlap in layout.overlaps {
            let outline = overlap.outline.path
            let appearance = overlap.appearance
            if appearance.fill != nil { builder.fill(outline, ReferenceVennScenePaint.fill(appearance, usual: .background, usualOpacity: 1), part: .vennOverlap) }
            if appearance.stroke != nil {
                builder.stroke(outline, ReferenceVennScenePaint.stroke(appearance, usual: .line), ReferenceVennScenePaint.stroke(of: appearance), part: .vennOverlap)
            }
        }
        for region in layout.regions {
            for line in region.lines {
                let usual: DiagramPaint = line.isRegionText ? .muted : .foreground
                let paint = (line.color.map(DiagramPaint.color) ?? usual).atOpacity(CGFloat(line.opacity ?? 1))
                builder.text(line.text, paint, isBold: line.isBold, isItalic: line.isItalic, part: line.isRegionText ? .vennText : .label)
            }
        }
        return builder.scene(size: layout.size, font: layout.font, seriesColors: layout.seriesColors)
    }
}

/// The paints a Venn diagram's styles give its shapes.
enum ReferenceVennScenePaint {
    /// A circle's fill is its color at a fifth of its opacity, unless its style sets a fill opacity.
    static let setFillOpacity = 0.2
    static let lineWidth: CGFloat = 1

    /// The style's fill at its fill opacity and opacity, else `usual` at `usualOpacity`.
    static func fill(_ appearance: VennAppearance, usual: DiagramPaint, usualOpacity: Double) -> DiagramPaint {
        (appearance.fill.map(DiagramPaint.color) ?? usual).atOpacity(CGFloat((appearance.fillOpacity ?? usualOpacity) * (appearance.opacity ?? 1)))
    }

    /// The style's stroke at its stroke opacity and opacity, else `usual`.
    static func stroke(_ appearance: VennAppearance, usual: DiagramPaint) -> DiagramPaint {
        (appearance.stroke.map(DiagramPaint.color) ?? usual).atOpacity(CGFloat((appearance.strokeOpacity ?? 1) * (appearance.opacity ?? 1)))
    }

    static func stroke(of appearance: VennAppearance) -> DiagramStroke {
        DiagramStroke(lineWidth: appearance.strokeWidth ?? lineWidth, dashLengths: appearance.strokeDashLengths ?? [])
    }
}

extension ReferenceChartScene {
    /// The block diagram's painting, in Pele's order: the bold title; each composite's box in the second surface at half
    /// opacity (the color its style fills it with at full) outlined in the border color, and its title in the muted
    /// color; the casings of the edges that cross the border of a composite a style fills (`BlockEdgeInk`); each edge's
    /// line in the line color (or in the ink of the filled composite that holds it), 2.5 points wide for `==` and dotted
    /// for `.-`, with its marks; each block's shape or arrow in the surface color outlined in the border color, its
    /// colors as its style sets, and its text; each edge's text on a patch of the page's color.
    static func scene(layout: BlockLayout) -> DiagramScene {
        var builder = DiagramSceneBuilder()
        builder.title(layout.title)
        for composite in layout.composites { ReferenceBlockScenePaths.add(composite, to: &builder) }
        let inks = BlockEdgeInk.inks(of: layout.edges, over: layout.composites)
        for (edge, ink) in zip(layout.edges, inks) where ink == .cased { ReferenceBlockScenePaths.addCasing(of: edge, to: &builder) }
        for (edge, ink) in zip(layout.edges, inks) {
            guard case .inked(let color) = ink else {
                ReferenceBlockScenePaths.add(edge, in: .line, to: &builder)
                continue
            }
            ReferenceBlockScenePaths.add(edge, in: .color(color), to: &builder)
        }
        for node in layout.nodes { ReferenceBlockScenePaths.add(node, to: &builder) }
        for edge in layout.edges {
            guard let text = edge.text else { continue }
            let patch = text.frame.insetBy(dx: -ReferenceBlockScenePaths.textPatchExtraWidth / 2, dy: 0)
            builder.fill(CGPath(roundedRect: patch, cornerWidth: ReferenceBlockScenePaths.textPatchCornerRadius, cornerHeight: ReferenceBlockScenePaths.textPatchCornerRadius,
                                transform: nil), .background, part: .labelBackground)
            builder.text(text, .foreground, part: .edgeLabel)
        }
        return builder.scene(size: layout.size, font: layout.font)
    }
}

/// The shapes of a block diagram's scene.
enum ReferenceBlockScenePaths {
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
