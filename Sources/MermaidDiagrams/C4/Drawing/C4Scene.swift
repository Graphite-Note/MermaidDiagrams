/**
 * File: C4Scene.swift
 * -------------------
 * Layer: Core
 * Description: A laid-out C4 diagram's scene, as Pele paints it: the title, the boundaries with their headings, the
 *              casings, the relations' lines and arrowheads, the shapes with their texts, then the relations' labels,
 *              every path recorded into lanes of the thread's scene workspace.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

import CoreGraphics

extension DiagramScene {
    /// The C4 diagram's painting, back to front as Pele writes it: the title in bold; each boundary's frame in the border
    /// color, dashed unless it is a deployment node, and its heading; the page-colored casings under lines that cross a
    /// filled boundary's border; each relation's line and arrowheads in the line color; each shape in the surface color
    /// (an external one hollow and dashed) with its kind, name in bold, technology and description; each relation's label
    /// on a patch of the page's color, its technology in italic. A style's fill, border and text colors replace these, and
    /// text on a fill the style sets takes the dark or light text color that reads on it.
    public init(layout: C4Layout) {
        self = DiagramSceneWorkspace.withRecording { workspace in
            var builder = DiagramSceneBuilder(workspace: workspace)
            builder.title(layout.title)
            for boundary in layout.boundaries { C4ScenePainting.add(boundary, to: &builder, workspace: workspace) }
            for relation in layout.relations where relation.isCased { C4ScenePainting.addCasing(of: relation, to: &builder, workspace: workspace) }
            for relation in layout.relations { C4ScenePainting.addLine(of: relation, to: &builder, workspace: workspace) }
            for shape in layout.shapes { C4ScenePainting.add(shape, to: &builder, workspace: workspace) }
            for relation in layout.relations { C4ScenePainting.addLabel(of: relation, to: &builder, workspace: workspace) }
            return builder.scene(size: layout.size, font: layout.font)
        }
    }
}

/// The shapes and texts of a C4 diagram's scene. Each shape's paths are recorded into lanes made for a moment and given
/// back once the builder has copied them.
enum C4ScenePainting {
    static let lineWidth: CGFloat = 1
    /// Pele's `--pele-radius`, a person's body's corners, a label patch's corners.
    static let cornerRadius = FlowchartShapeDrawing.rectangleCornerRadius
    static let labelPatchRadius: CGFloat = 3
    static let boundaryDashes: [CGFloat] = [6, 4]
    static let externalDashes: [CGFloat] = [4, 3]
    /// A casing is this much wider than its line.
    static let casingWidening: CGFloat = 4

    static func add(_ boundary: C4LayoutBoundary, to builder: inout DiagramSceneBuilder, workspace: DiagramSceneWorkspace) {
        let madeCount = workspace.madePathCount
        defer { workspace.givePathsBack(downTo: madeCount) }
        let look = boundary.look
        let frame = workspace.roundedRectangle(boundary.frame, cornerWidth: cornerRadius, cornerHeight: cornerRadius)
        let stroke = DiagramStroke(lineWidth: lineWidth, dashLengths: boundary.isDeploymentNode ? [] : boundaryDashes)
        let strokePaint = look.stroke.map(DiagramPaint.color) ?? .border
        if let fill = look.fill {
            builder.fillAndStroke(frame, fill: .color(fill), stroke: strokePaint, stroke, part: .cluster)
        } else {
            builder.stroke(frame, strokePaint, stroke, part: .cluster)
        }
        builder.texts(boundary.name, textPaint(look, usual: .foreground), isBold: true, part: .clusterLabel)
        builder.texts(boundary.type, textPaint(look, usual: .muted), part: .c4Type)
        builder.texts(boundary.description, textPaint(look, usual: .muted), part: .c4Description)
    }

    /// A wider line of the page's color under the line and its arrowheads.
    static func addCasing(of relation: C4LayoutRelation, to builder: inout DiagramSceneBuilder, workspace: DiagramSceneWorkspace) {
        let madeCount = workspace.madePathCount
        defer { workspace.givePathsBack(downTo: madeCount) }
        let stroke = DiagramStroke.rounded(lineWidth: lineWidth + casingWidening)
        builder.stroke(line(of: relation, workspace: workspace), .background, stroke, part: .casing)
        let marks = arrowheads(of: relation, workspace: workspace)
        if !marks.isEmpty { builder.fillAndStroke(marks, fill: .background, stroke: .background, stroke, part: .casing) }
    }

    static func addLine(of relation: C4LayoutRelation, to builder: inout DiagramSceneBuilder, workspace: DiagramSceneWorkspace) {
        let madeCount = workspace.madePathCount
        defer { workspace.givePathsBack(downTo: madeCount) }
        let paint = relation.lineColor.map(DiagramPaint.color) ?? .line
        builder.stroke(line(of: relation, workspace: workspace), paint, .rounded(lineWidth: lineWidth), part: .edge)
        builder.fill(arrowheads(of: relation, workspace: workspace), paint, part: .marker)
    }

    private static func line(of relation: C4LayoutRelation, workspace: DiagramSceneWorkspace) -> DiagramPathLane {
        let drawn = workspace.makeLane()
        DiagramEdgeDrawing.record(relation.path, into: drawn)
        return drawn
    }

    /// The filled arrowheads at the relation's ends; their stroked parts, which an arrow has none of, are left out.
    private static func arrowheads(of relation: C4LayoutRelation, workspace: DiagramSceneWorkspace) -> DiagramPathLane {
        let filled = workspace.makeLane()
        let stroked = workspace.makeLane()
        if let mark = relation.startMark { DiagramEdgeDrawing.addMark(mark, filled: filled, stroked: stroked) }
        if let mark = relation.endMark { DiagramEdgeDrawing.addMark(mark, filled: filled, stroked: stroked) }
        return filled
    }

    /// A shape filled and outlined (a person's body and head one after the other), its inner lines, then its texts.
    static func add(_ shape: C4LayoutShape, to builder: inout DiagramSceneBuilder, workspace: DiagramSceneWorkspace) {
        let madeCount = workspace.madePathCount
        defer { workspace.givePathsBack(downTo: madeCount) }
        let look = shape.look
        let fill = look.fill.map(DiagramPaint.color) ?? (shape.isExternal ? .background : .surface)
        let strokePaint = look.stroke.map(DiagramPaint.color) ?? .border
        let stroke = DiagramStroke(lineWidth: lineWidth, dashLengths: shape.isExternal ? externalDashes : [])
        let flowchartShape = flowchartShape(of: shape.form)
        let isLayered = FlowchartLayeredShapeDrawing.forEachLayer(of: flowchartShape, in: shape.frame, making: workspace) { piece, _ in
            builder.keepNextShapeApart()
            builder.fillAndStroke(piece, fill: fill, stroke: strokePaint, stroke, part: .node)
        }
        if !isLayered, let outline = FlowchartShapeDrawing.outline(of: flowchartShape, in: shape.frame, making: workspace) {
            builder.fillAndStroke(outline, fill: fill, stroke: strokePaint, stroke, part: .node)
        }
        if let lines = FlowchartShapeDrawing.innerLines(of: flowchartShape, in: shape.frame, making: workspace) {
            builder.stroke(lines, strokePaint, stroke, part: .node)
        }
        builder.text(shape.type, textPaint(look, usual: .muted), part: .c4Type)
        builder.text(shape.name, textPaint(look, usual: .foreground), isBold: true, part: .label)
        builder.text(shape.technology, textPaint(look, usual: .muted), part: .c4Technology)
        builder.text(shape.description, textPaint(look, usual: .foreground), part: .c4Description)
    }

    static func addLabel(of relation: C4LayoutRelation, to builder: inout DiagramSceneBuilder, workspace: DiagramSceneWorkspace) {
        guard let frame = relation.labelFrame else { return }
        let madeCount = workspace.madePathCount
        defer { workspace.givePathsBack(downTo: madeCount) }
        builder.fill(workspace.roundedRectangle(frame, cornerWidth: labelPatchRadius, cornerHeight: labelPatchRadius), .background,
                     part: .labelBackground)
        let textColor = relation.textColor.map(DiagramPaint.color)
        builder.text(relation.label, textColor ?? .foreground, part: .edgeLabel)
        builder.text(relation.technology, textColor ?? .muted, isItalic: true, part: .c4Technology)
    }

    /// The flowchart shape that draws a C4 form: Pele's shared shapes.
    private static func flowchartShape(of form: C4ShapeForm) -> FlowchartNodeShape {
        switch form {
        case .rectangle: .rectangle
        case .person: .person
        case .cylinder: .cylinder
        case .horizontalCylinder: .horizontalCylinder
        }
    }

    /// The style's text color, else the one picked for its fill, else the usual one.
    private static func textPaint(_ look: C4ElementLook, usual: DiagramPaint) -> DiagramPaint {
        (look.textColor ?? look.ink).map(DiagramPaint.color) ?? usual
    }
}
