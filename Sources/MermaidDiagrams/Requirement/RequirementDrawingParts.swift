/**
 * File: RequirementDrawingParts.swift
 * -----------------------------------
 * Layer: Core
 * Description: A laid-out requirement diagram's geometry grouped by how it is painted, as Core Graphics paths or in any
 *              kind a drawing records, and its renderer.
 *
 * Authors: Bahey Shalash
 * Version: 0.5
 * Date: 26/11/2026
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
        let paths = RequirementPaths(layout: layout, making: DiagramCoreGraphicsPaths())
        solidLines = paths.solidLines.path
        dashedLines = paths.dashedLines.path
        marks = paths.marks.path
        textPatches = paths.textPatches.path
        texts = layout.relations.map(\.text)
        boxFills = paths.boxFills.path
        boxOutlines = paths.boxOutlines.path
        let plainBoxes = layout.boxes.filter { box in box.style == nil }
        stereotypes = plainBoxes.map(\.stereotype)
        names = plainBoxes.map(\.name)
        fieldNames = plainBoxes.flatMap(\.fieldNames)
        fieldValues = plainBoxes.flatMap(\.fieldValues)
        styledBoxes = layout.boxes.filter { box in box.style != nil }
    }

    /// A box's rounded rectangle to fill, and it and its divider to stroke.
    static func addBox(_ box: RequirementLayoutBox, fill: CGMutablePath, outline: CGMutablePath) {
        addBox(frame: box.frame, dividerY: box.dividerY, fill: DiagramCoreGraphicsPath(mutable: fill), outline: DiagramCoreGraphicsPath(mutable: outline),
               making: DiagramCoreGraphicsPaths())
    }

    /// `addBox` in any kind a drawing records; the rounded rectangle is made for a moment and given back.
    static func addBox<Maker: DiagramPathMaking>(frame: CGRect, dividerY: CGFloat?, fill: Maker.Path, outline: Maker.Path, making maker: Maker) {
        let madeCount = maker.madePathCount
        fill.addPath(maker.roundedRectangle(frame, cornerWidth: cornerRadius, cornerHeight: cornerRadius), alsoTo: outline)
        maker.givePathsBack(downTo: madeCount)
        if let dividerY {
            outline.move(to: CGPoint(x: frame.minX, y: dividerY))
            outline.addLine(to: CGPoint(x: frame.maxX, y: dividerY))
        }
    }

    /// Pele's marks: a circle of radius 6 whose rim touches the box with a plus through it, or an open arrowhead 9 points
    /// long and 9 wide.
    static func addMark<Path: DiagramPathRecording>(_ mark: RequirementRelationMark, to path: Path) {
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

/// The paths of `RequirementDrawingParts` in any kind a drawing records: Core Graphics paths or lanes of the scene's
/// workspace. A shape made whole (a box, a relation's line, a patch) is made for a moment, added where it is painted and
/// given back.
struct RequirementPaths<Path: DiagramPathRecording> {
    let solidLines: Path
    let dashedLines: Path
    let marks: Path
    let textPatches: Path
    /// The boxes of the usual look, filled and outlined with their dividers.
    let boxFills: Path
    let boxOutlines: Path

    init<Maker: DiagramPathMaking>(layout: RequirementLayout, making maker: Maker) where Maker.Path == Path {
        solidLines = maker.makePath()
        dashedLines = maker.makePath()
        marks = maker.makePath()
        textPatches = maker.makePath()
        for relation in layout.placedRelations {
            let madeCount = maker.madePathCount
            let line = maker.makePath()
            line.move(to: relation.start)
            for segment in layout.segments[relation.segmentIndices] {
                switch segment {
                case .line(let end): line.addLine(to: end)
                case .curve(let end, let firstControl, let secondControl): line.addCurve(to: end, control1: firstControl, control2: secondControl)
                }
            }
            (relation.kind == .contains ? solidLines : dashedLines).addPath(line)
            RequirementDrawingParts.addMark(relation.mark, to: marks)
            let radius = RequirementDrawingParts.textPatchCornerRadius
            textPatches.addPath(maker.roundedRectangle(relation.text.frame.insetBy(dx: -RequirementDrawingParts.textPatchExtraWidth / 2, dy: 0),
                                                       cornerWidth: radius, cornerHeight: radius))
            maker.givePathsBack(downTo: madeCount)
        }
        boxFills = maker.makePath()
        boxOutlines = maker.makePath()
        for box in layout.placedBoxes where box.style == nil {
            RequirementDrawingParts.addBox(frame: box.frame, dividerY: box.dividerY, fill: boxFills, outline: boxOutlines, making: maker)
        }
    }
}

/// Draws a laid-out requirement diagram into a Core Graphics context whose origin is the layout's top left and whose y runs
/// down, by painting its scene with `DiagramSceneRenderer`.
public enum RequirementRenderer {
    public static func draw(_ layout: RequirementLayout, in context: CGContext, palette: DiagramPalette) {
        DiagramSceneRenderer.draw(DiagramScene(layout: layout), in: context, palette: palette)
    }
}
