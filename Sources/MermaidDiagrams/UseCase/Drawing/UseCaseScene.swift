/**
 * File: UseCaseScene.swift
 * ------------------------
 * Layer: Core
 * Description: A laid-out use case diagram's scene, as Pele paints it: the title, the system boundaries with their
 *              titles, the casings, the lines with their marks, the lines' labels, then the actors, use cases, notes
 *              and JSON tables with their texts.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */

import CoreGraphics

extension DiagramScene {
    /// The use case diagram's painting, back to front as Pele writes it: the title in bold; each boundary's box in the
    /// alternate surface at half its opacity outlined in the border color, a package's tab above it, its title muted;
    /// the page-colored casings under lines that cross a filled boundary's border; each line in the line color (a note's
    /// connector dashed 2 3, an include or extend 5 4, an animated relationship 9 5) with its marks; each label on a
    /// patch of the page's color, an include's or extend's muted; then each node in the surface color outlined in the
    /// border color, a note in the alternate surface, with its stereotype muted and its label. A style's colors, width
    /// and dashes replace these and its opacities fade them (a line whose stroke is none has no casing), its weight and
    /// slant reach a label but not a stereotype or a JSON key, and text on a fill a style sets takes the dark or light
    /// text color that reads on it.
    public init(layout: UseCaseLayout) {
        var builder = DiagramSceneBuilder()
        builder.title(layout.title)
        for boundary in layout.boundaries { UseCaseScenePainting.add(boundary, to: &builder) }
        for edge in layout.edges where edge.isCased && !edge.look.hidesStroke { UseCaseScenePainting.addCasing(of: edge, to: &builder) }
        for edge in layout.edges { UseCaseScenePainting.addLine(of: edge, to: &builder) }
        for edge in layout.edges { UseCaseScenePainting.addLabel(of: edge, to: &builder) }
        for node in layout.nodes { UseCaseNodePainting.add(node, to: &builder) }
        self = builder.scene(size: layout.size, font: layout.font)
    }
}

/// The boundaries and lines of a use case diagram's scene.
enum UseCaseScenePainting {
    static let cornerRadius = FlowchartShapeDrawing.rectangleCornerRadius
    static let labelPatchRadius: CGFloat = 3
    /// How much of the alternate surface a boundary shows over the page.
    static let boundaryFillOpacity: CGFloat = 0.5
    /// A casing is this much wider than its line.
    static let casingWidening: CGFloat = 4

    /// A look's outline: its stroke color, else the border's, at its stroke's opacity; its width, else 1; its dashes.
    static func outline(_ look: UseCaseLook) -> (paint: DiagramPaint, stroke: DiagramStroke) {
        ((look.stroke.map(DiagramPaint.color) ?? .border).atOpacity(look.strokeAmount),
         DiagramStroke(lineWidth: look.strokeWidth ?? 1, dashLengths: look.strokeDashLengths ?? []))
    }

    /// A look's fill: its fill color, else `usual`, at its fill's opacity (`usualOpacity` when it writes none).
    static func fill(_ look: UseCaseLook, usual: DiagramPaint, usualOpacity: CGFloat = 1) -> DiagramPaint {
        (look.fill.map(DiagramPaint.color) ?? usual).atOpacity(look.fillAmount(usual: usualOpacity))
    }

    /// A text's color: its style's (unless the text does not read it), else the one picked over its fill (unless it
    /// does not read that), else `usual`.
    static func textPaint(_ look: UseCaseLook, usual: DiagramPaint, readsInk: Bool = true, readsTextColor: Bool = true) -> DiagramPaint {
        (readsTextColor ? look.textColor.map(DiagramPaint.color) : nil) ?? (readsInk ? look.ink.map(DiagramPaint.color) : nil) ?? usual
    }

    static func add(_ boundary: UseCaseLayoutBoundary, to builder: inout DiagramSceneBuilder) {
        let look = boundary.look
        let fill = fill(look, usual: .alternateSurface, usualOpacity: look.setsFill ? 1 : boundaryFillOpacity)
        let (strokePaint, stroke) = outline(look)
        if let tab = boundary.tabFrame {
            builder.fillAndStroke(CGPath(rect: tab, transform: nil), fill: fill, stroke: strokePaint, stroke, part: .boundaryTab)
            let body = CGRect(x: boundary.frame.minX, y: tab.maxY, width: boundary.frame.width, height: boundary.frame.height - tab.height)
            builder.fillAndStroke(CGPath(rect: body, transform: nil), fill: fill, stroke: strokePaint, stroke, part: .cluster)
        } else {
            let box = CGPath(roundedRect: boundary.frame, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
            builder.fillAndStroke(box, fill: fill, stroke: strokePaint, stroke, part: .cluster)
        }
        builder.text(boundary.title, textPaint(look, usual: .muted), isBold: look.isBold, isItalic: look.isItalic, part: .clusterLabel)
    }

    /// A wider line of the page's color under the line and its marks, as faint as the line.
    static func addCasing(of edge: UseCaseLayoutEdge, to builder: inout DiagramSceneBuilder) {
        let stroke = DiagramStroke.rounded(lineWidth: edge.lineWidth + casingWidening)
        let paint = DiagramPaint.background.atOpacity(edge.look.strokeAmount)
        builder.stroke(DiagramEdgeDrawing.path(edge.path), paint, stroke, part: .casing)
        let marks = CGMutablePath()
        for mark in [edge.startMark, edge.endMark].compactMap({ mark in mark }) { addOutline(of: mark, to: marks) }
        if !marks.isEmpty { builder.fillAndStroke(marks, fill: paint, stroke: paint, stroke, part: .casing) }
    }

    static func addLine(of edge: UseCaseLayoutEdge, to builder: inout DiagramSceneBuilder) {
        // The line's style sets the opacity of the whole line, and its stroke's opacity that of what is stroked.
        let color = edge.inkOverFill.map(DiagramPaint.color) ?? edge.look.stroke.map(DiagramPaint.color) ?? .line
        let paint = color.atOpacity(edge.look.strokeAmount)
        let filledPaint = color.atOpacity(edge.look.opacity)
        builder.stroke(DiagramEdgeDrawing.path(edge.path), paint, DiagramStroke(lineWidth: edge.lineWidth, dashLengths: edge.dashLengths, lineCap: .round),
                       part: .edge)
        let filled = CGMutablePath()
        let stroked = CGMutablePath()
        for mark in [edge.startMark, edge.endMark].compactMap({ mark in mark }) {
            guard mark.marker == .hollowTriangle else {
                DiagramEdgeDrawing.addMark(DiagramEdgeMark(arrowhead: arrowhead(of: mark.marker), tip: mark.tip, direction: mark.direction),
                                           filled: filled, stroked: stroked)
                continue
            }
            builder.fillAndStroke(UseCaseFigureShapes.extensionTriangle(tip: mark.tip, direction: mark.direction),
                                  fill: (edge.fillUnderMarks.map(DiagramPaint.color) ?? .background).atOpacity(edge.look.opacity), stroke: paint,
                                  DiagramStroke(lineWidth: edge.lineWidth, lineCap: .round, lineJoin: .round), part: .marker)
        }
        builder.fill(filled, filledPaint, part: .marker)
        builder.stroke(stroked, paint, DiagramStroke(lineWidth: edge.lineWidth, lineCap: .round), part: .marker)
    }

    /// The mark's shape as its casing covers it: an arrow's triangle, a circle, a cross's arms, a triangle.
    private static func addOutline(of mark: UseCaseLayoutMark, to path: CGMutablePath) {
        if mark.marker == .hollowTriangle {
            path.addPath(UseCaseFigureShapes.extensionTriangle(tip: mark.tip, direction: mark.direction))
        } else {
            DiagramEdgeDrawing.addMark(DiagramEdgeMark(arrowhead: arrowhead(of: mark.marker), tip: mark.tip, direction: mark.direction),
                                       filled: path, stroked: path)
        }
    }

    private static func arrowhead(of marker: UseCaseMarker) -> FlowchartArrowhead {
        switch marker {
        case .point: .arrow
        case .circle: .circle
        case .cross: .cross
        case .none, .hollowTriangle: .none
        }
    }

    /// The label on a patch of the page's color: an include's or extend's muted, else in the style's text color.
    static func addLabel(of edge: UseCaseLayoutEdge, to builder: inout DiagramSceneBuilder) {
        guard let label = edge.label, let patch = edge.labelPatch else { return }
        builder.fill(CGPath(roundedRect: patch, cornerWidth: labelPatchRadius, cornerHeight: labelPatchRadius, transform: nil), .background,
                     part: .labelBackground)
        builder.text(label, edge.look.textColor.map(DiagramPaint.color) ?? (edge.isSemantic ? .muted : .foreground), isBold: edge.look.isBold,
                     isItalic: edge.look.isItalic, part: .edgeLabel)
    }
}
