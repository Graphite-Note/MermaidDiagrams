/**
 * File: ReferenceRequirementDrawingParts.swift
 * --------------------------------------------
 * Layer: Tests
 * Description: 0.7.0's requirement diagram drawing parts, frozen as main 2a0cc65 made them in Core Graphics paths,
 *              which the drawing parts and scenes made by the generic path code are compared with.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// A laid-out requirement diagram's geometry grouped by how Pele paints it, back to front: the title, the relations'
/// lines (`contains` solid, the others dashed 5 and 4) and their marks stroked in the line color, the patches behind the
/// relations' texts and those texts in the muted color, the boxes on the surface with their outlines and dividers, the
/// stereotypes and field names muted, the names bold and the values in the foreground color.
struct ReferenceRequirementDrawingParts {
    let title: DiagramTextBlock?
    let solidLines: CGPath
    let dashedLines: CGPath
    /// The containment marks' circles and crosses and the open arrowheads, stroked.
    let marks: CGPath
    let textPatches: CGPath
    let texts: [DiagramTextBlock]
    let boxFills: CGPath
    /// The boxes' outlines and dividers, stroked in the border color.
    let boxOutlines: CGPath
    let stereotypes: [DiagramTextBlock]
    let names: [DiagramTextBlock]
    let fieldNames: [DiagramTextBlock]
    let fieldValues: [DiagramTextBlock]
    /// The boxes the diagram gave colors of their own, painted apart from those of the usual look.
    let styledBoxes: [RequirementLayoutBox]

    static let lineWidth: CGFloat = 1
    static let dashedLineLengths: [CGFloat] = [5, 4]
    /// Pele's `--pele-radius`.
    static let cornerRadius: CGFloat = 4
    static let containmentRadius: CGFloat = RequirementLayoutEngine.containmentRadius
    static let arrowLength: CGFloat = 9
    static let arrowHalfWidth: CGFloat = 4.5
    /// How much wider than its text the patch behind a relation's text is, and its corners.
    static let textPatchExtraWidth: CGFloat = 8
    static let textPatchCornerRadius: CGFloat = 3

    init(layout: RequirementLayout) {
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
