/**
 * File: RequirementDrawingParts.swift
 * -----------------------------------
 * Layer: Core
 * Description: A laid-out requirement diagram's geometry grouped by how it is painted, its scene in Pele's order and
 *              roles, and its renderer.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */

import CoreGraphics

/// A laid-out requirement diagram's geometry grouped by how Pele paints it, back to front: the title, the relations'
/// lines (`contains` solid, the others dashed 5 and 4) and their marks stroked in the line color, the patches behind the
/// relations' texts and those texts in the muted color, the boxes on the surface with their outlines and dividers, the
/// stereotypes and field names muted, the names bold and the values in the foreground color.
public struct RequirementDrawingParts {
    public let title: DiagramTextBlock?
    public let solidLines: CGPath
    public let dashedLines: CGPath
    /// The containment marks' circles and crosses and the open arrowheads, stroked.
    public let marks: CGPath
    public let textPatches: CGPath
    public let texts: [DiagramTextBlock]
    public let boxFills: CGPath
    /// The boxes' outlines and dividers, stroked in the border color.
    public let boxOutlines: CGPath
    public let stereotypes: [DiagramTextBlock]
    public let names: [DiagramTextBlock]
    public let fieldNames: [DiagramTextBlock]
    public let fieldValues: [DiagramTextBlock]
    /// The boxes the diagram gave colors of their own, painted apart from those of the usual look.
    public let styledBoxes: [RequirementLayoutBox]

    public static let lineWidth: CGFloat = 1
    public static let dashedLineLengths: [CGFloat] = [5, 4]
    /// Pele's `--pele-radius`.
    static let cornerRadius: CGFloat = 4
    static let containmentRadius: CGFloat = RequirementLayoutEngine.containmentRadius
    static let arrowLength: CGFloat = 9
    static let arrowHalfWidth: CGFloat = 4.5
    /// How much wider than its text the patch behind a relation's text is, and its corners.
    static let textPatchExtraWidth: CGFloat = 8
    static let textPatchCornerRadius: CGFloat = 3

    public init(layout: RequirementLayout) {
        title = layout.title
        let solid = CGMutablePath()
        let dashed = CGMutablePath()
        let marks = CGMutablePath()
        let patches = CGMutablePath()
        for relation in layout.relations {
            (relation.kind == .contains ? solid : dashed).addPath(DiagramEdgeDrawing.path(relation.path))
            Self.addMark(relation.mark, to: marks)
            patches.addPath(CGPath(roundedRect: relation.text.frame.insetBy(dx: -Self.textPatchExtraWidth / 2, dy: 0), cornerWidth: Self.textPatchCornerRadius,
                                   cornerHeight: Self.textPatchCornerRadius, transform: nil))
        }
        solidLines = solid
        dashedLines = dashed
        self.marks = marks
        textPatches = patches
        texts = layout.relations.map(\.text)
        let plainBoxes = layout.boxes.filter { box in box.style == nil }
        let fills = CGMutablePath()
        let outlines = CGMutablePath()
        for box in plainBoxes { Self.addBox(box, fill: fills, outline: outlines) }
        boxFills = fills
        boxOutlines = outlines
        stereotypes = plainBoxes.map(\.stereotype)
        names = plainBoxes.map(\.name)
        fieldNames = plainBoxes.flatMap(\.fieldNames)
        fieldValues = plainBoxes.flatMap(\.fieldValues)
        styledBoxes = layout.boxes.filter { box in box.style != nil }
    }

    /// A box's rounded rectangle to fill, and it and its divider to stroke.
    static func addBox(_ box: RequirementLayoutBox, fill: CGMutablePath, outline: CGMutablePath) {
        let rectangle = CGPath(roundedRect: box.frame, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        fill.addPath(rectangle)
        outline.addPath(rectangle)
        if let dividerY = box.dividerY {
            outline.move(to: CGPoint(x: box.frame.minX, y: dividerY))
            outline.addLine(to: CGPoint(x: box.frame.maxX, y: dividerY))
        }
    }

    /// Pele's marks: a circle of radius 6 whose rim touches the box with a plus through it, or an open arrowhead 9 points
    /// long and 9 wide.
    static func addMark(_ mark: RequirementRelationMark, to path: CGMutablePath) {
        switch mark {
        case .containment(let point, let toward):
            let radius = containmentRadius
            let center = CGPoint(x: point.x - toward.dx * radius, y: point.y - toward.dy * radius)
            path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius))
            path.move(to: CGPoint(x: center.x - toward.dx * radius, y: center.y - toward.dy * radius))
            path.addLine(to: CGPoint(x: center.x + toward.dx * radius, y: center.y + toward.dy * radius))
            path.move(to: CGPoint(x: center.x + toward.dy * radius, y: center.y - toward.dx * radius))
            path.addLine(to: CGPoint(x: center.x - toward.dy * radius, y: center.y + toward.dx * radius))
        case .arrow(let tip, let direction):
            let base = CGPoint(x: tip.x - direction.dx * arrowLength, y: tip.y - direction.dy * arrowLength)
            path.move(to: CGPoint(x: base.x - direction.dy * arrowHalfWidth, y: base.y + direction.dx * arrowHalfWidth))
            path.addLine(to: tip)
            path.addLine(to: CGPoint(x: base.x + direction.dy * arrowHalfWidth, y: base.y - direction.dx * arrowHalfWidth))
        }
    }
}

extension DiagramScene {
    /// The requirement diagram's painting, as Pele paints it (`RequirementDrawingParts`).
    public init(layout: RequirementLayout) {
        var builder = DiagramSceneBuilder()
        RequirementDrawingParts(layout: layout).addScene(to: &builder)
        self = builder.scene(size: layout.size, font: layout.font)
    }
}

extension RequirementDrawingParts {
    func addScene(to builder: inout DiagramSceneBuilder) {
        let line = DiagramStroke.rounded(lineWidth: Self.lineWidth)
        builder.title(title)
        builder.stroke(solidLines, .line, line, part: .edge)
        builder.stroke(dashedLines, .line, .rounded(lineWidth: Self.lineWidth, dashLengths: Self.dashedLineLengths), part: .edge)
        builder.stroke(marks, .line, line, part: .marker)
        builder.fill(textPatches, .background, part: .labelBackground)
        builder.texts(texts, .muted, part: .edgeLabel)
        let outline = DiagramStroke(lineWidth: Self.lineWidth)
        builder.fill(boxFills, .surface, part: .node)
        builder.stroke(boxOutlines, .border, outline, part: .node)
        builder.texts(stereotypes, .muted, part: .stereotype)
        builder.texts(names, .foreground, isBold: true, part: .label)
        builder.texts(fieldNames, .muted, part: .field)
        builder.texts(fieldValues, .foreground, part: .value)
        for box in styledBoxes { addStyledBox(box, to: &builder) }
    }

    /// A box in the colors and stroke its style sets, and the usual ones for the rest; all its text in its style's color, or
    /// else, on a fill it sets, in the ink that contrasts more with that fill (Pele's `inkFill`), or else in the usual roles.
    private func addStyledBox(_ box: RequirementLayoutBox, to builder: inout DiagramSceneBuilder) {
        let style = box.style ?? DiagramElementStyle()
        let fill = CGMutablePath()
        let outline = CGMutablePath()
        Self.addBox(box, fill: fill, outline: outline)
        builder.keepNextShapeApart()
        builder.fill(fill, style.fill.map(DiagramPaint.color) ?? .surface, part: .node)
        builder.stroke(outline, style.stroke.map(DiagramPaint.color) ?? .border,
                       DiagramStroke(lineWidth: style.strokeWidth ?? Self.lineWidth, dashLengths: style.strokeDashLengths ?? []), part: .node)
        let text = style.textColor.map(DiagramPaint.color) ?? TreemapInk.paint(onFill: style.fill)
        builder.text(box.stereotype, text ?? .muted, part: .stereotype)
        builder.text(box.name, text ?? .foreground, isBold: true, part: .label)
        builder.texts(box.fieldNames, text ?? .muted, part: .field)
        builder.texts(box.fieldValues, text ?? .foreground, part: .value)
    }
}

/// Draws a laid-out requirement diagram into a Core Graphics context whose origin is the layout's top left and whose y runs
/// down, by painting its scene with `DiagramSceneRenderer`.
public enum RequirementRenderer {
    public static func draw(_ layout: RequirementLayout, in context: CGContext, palette: DiagramPalette) {
        DiagramSceneRenderer.draw(DiagramScene(layout: layout), in: context, palette: palette)
    }
}
