/**
 * File: C4Scene.swift
 * -------------------
 * Layer: Core
 * Description: A laid-out C4 diagram's scene, as Pele paints it: the title, the boundaries with their headings, the
 *              casings, the relations' lines and arrowheads, the shapes with their texts, then the relations' labels,
 *              read from the layout's records, every text from its measured lines, every path recorded into lanes of the
 *              thread's scene workspace.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 26/11/2026
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
        self.init(layout: layout, limits: .standard)
    }

    /// The scene recorded into lanes of at most `DiagramSceneWorkspace.elementLimit(for: limits)` elements: one past
    /// it marks the scene (`exceededPathElementLimit`), which the preparation refuses.
    init(layout: C4Layout, limits: MermaidDiagramLimits) {
        self = layout.withSource { source in
            DiagramSceneWorkspace.withRecording(limits: limits) { workspace in
                var painting = C4ScenePainting(layout: layout, source: source, workspace: workspace)
                painting.builder.title(layout.titleText, of: layout.lines, source: source)
                for boundary in layout.boundaryRecords { painting.add(boundary) }
                for relation in layout.relationRecords where relation.isCased { painting.addCasing(of: relation) }
                for relation in layout.relationRecords { painting.addLine(of: relation) }
                for shape in layout.shapeRecords { painting.add(shape) }
                for relation in layout.relationRecords { painting.addLabel(of: relation) }
                return painting.builder.scene(size: layout.size, font: layout.font)
            }
        }
    }
}

/// The shapes and texts of a C4 diagram's scene, made into `builder`. Each shape's paths are recorded into lanes made
/// for a moment and given back once the builder has copied them; each text is copied from the layout's lines, over
/// `source`, the diagram's text.
struct C4ScenePainting: ~Copyable {
    static let lineWidth: CGFloat = 1
    /// Pele's `--pele-radius`, a person's body's corners, a label patch's corners.
    static let cornerRadius = FlowchartShapeDrawing.rectangleCornerRadius
    static let labelPatchRadius: CGFloat = 3
    static let boundaryDashes: [CGFloat] = [6, 4]
    static let externalDashes: [CGFloat] = [4, 3]
    /// A casing is this much wider than its line.
    static let casingWidening: CGFloat = 4

    let layout: C4Layout
    let source: UnsafeBufferPointer<UInt8>
    let workspace: DiagramSceneWorkspace
    var builder: DiagramSceneBuilder

    init(layout: C4Layout, source: UnsafeBufferPointer<UInt8>, workspace: DiagramSceneWorkspace) {
        self.layout = layout
        self.source = source
        self.workspace = workspace
        builder = DiagramSceneBuilder(workspace: workspace)
    }

    mutating func add(_ boundary: C4LaidOutBoundary) {
        let madeCount = workspace.madePathCount
        defer { workspace.givePathsBack(downTo: madeCount) }
        let look = boundary.look
        let frame = workspace.roundedRectangle(boundary.frame, cornerWidth: Self.cornerRadius, cornerHeight: Self.cornerRadius)
        let stroke = DiagramStroke(lineWidth: Self.lineWidth, dashLengths: boundary.isDeploymentNode ? [] : Self.boundaryDashes)
        let strokePaint = look.stroke.map(DiagramPaint.color) ?? .border
        if let fill = look.fill {
            builder.fillAndStroke(frame, fill: .color(fill), stroke: strokePaint, stroke, part: .cluster)
        } else {
            builder.stroke(frame, strokePaint, stroke, part: .cluster)
        }
        let headingLines = layout.headingLines
        builder.texts(headingLines[boundary.nameLines], of: layout.lines, source: source, Self.textPaint(look, usual: .foreground), isBold: true,
                      part: .clusterLabel)
        builder.texts(headingLines[boundary.typeLines], of: layout.lines, source: source, Self.textPaint(look, usual: .muted), part: .c4Type)
        builder.texts(headingLines[boundary.descriptionLines], of: layout.lines, source: source, Self.textPaint(look, usual: .muted), part: .c4Description)
    }

    /// A wider line of the page's color under the line and its arrowheads.
    mutating func addCasing(of relation: C4LaidOutRelation) {
        let madeCount = workspace.madePathCount
        defer { workspace.givePathsBack(downTo: madeCount) }
        let stroke = DiagramStroke.rounded(lineWidth: Self.lineWidth + Self.casingWidening)
        builder.stroke(line(of: relation), .background, stroke, part: .casing)
        let marks = arrowheads(of: relation)
        if !marks.isEmpty { builder.fillAndStroke(marks, fill: .background, stroke: .background, stroke, part: .casing) }
    }

    mutating func addLine(of relation: C4LaidOutRelation) {
        let madeCount = workspace.madePathCount
        defer { workspace.givePathsBack(downTo: madeCount) }
        let paint = relation.lineColor.map(DiagramPaint.color) ?? .line
        builder.stroke(line(of: relation), paint, .rounded(lineWidth: Self.lineWidth), part: .edge)
        builder.fill(arrowheads(of: relation), paint, part: .marker)
    }

    /// The relation's line, from its start through its segments in the layout's list.
    private func line(of relation: C4LaidOutRelation) -> DiagramPathLane {
        let drawn = workspace.makeLane()
        drawn.move(to: relation.pathStart)
        for segment in layout.segments[relation.segments] {
            switch segment {
            case .line(let end): drawn.addLine(to: end)
            case .curve(let end, let firstControl, let secondControl): drawn.addCurve(to: end, control1: firstControl, control2: secondControl)
            }
        }
        return drawn
    }

    /// The filled arrowheads at the relation's ends; their stroked parts, which an arrow has none of, are left out.
    private func arrowheads(of relation: C4LaidOutRelation) -> DiagramPathLane {
        let filled = workspace.makeLane()
        let stroked = workspace.makeLane()
        if let mark = relation.startMark { DiagramEdgeDrawing.addMark(mark, filled: filled, stroked: stroked) }
        if let mark = relation.endMark { DiagramEdgeDrawing.addMark(mark, filled: filled, stroked: stroked) }
        return filled
    }

    /// A shape filled and outlined (a person's body and head one after the other), its inner lines, then its texts.
    mutating func add(_ shape: C4LaidOutShape) {
        let madeCount = workspace.madePathCount
        defer { workspace.givePathsBack(downTo: madeCount) }
        let look = shape.look
        let fill = look.fill.map(DiagramPaint.color) ?? (shape.isExternal ? .background : .surface)
        let strokePaint = look.stroke.map(DiagramPaint.color) ?? .border
        let stroke = DiagramStroke(lineWidth: Self.lineWidth, dashLengths: shape.isExternal ? Self.externalDashes : [])
        let flowchartShape = Self.flowchartShape(of: shape.form)
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
        text(shape.type, Self.textPaint(look, usual: .muted), part: .c4Type)
        text(shape.name, Self.textPaint(look, usual: .foreground), isBold: true, part: .label)
        text(shape.technology, Self.textPaint(look, usual: .muted), part: .c4Technology)
        text(shape.description, Self.textPaint(look, usual: .foreground), part: .c4Description)
    }

    mutating func addLabel(of relation: C4LaidOutRelation) {
        guard let frame = relation.labelFrame else { return }
        let madeCount = workspace.madePathCount
        defer { workspace.givePathsBack(downTo: madeCount) }
        builder.fill(workspace.roundedRectangle(frame, cornerWidth: Self.labelPatchRadius, cornerHeight: Self.labelPatchRadius), .background,
                     part: .labelBackground)
        let textColor = relation.textColor.map(DiagramPaint.color)
        text(relation.label, textColor ?? .foreground, part: .edgeLabel)
        text(relation.technology, textColor ?? .muted, isItalic: true, part: .c4Technology)
    }

    /// A text of the layout, when there is one.
    private mutating func text(_ text: DiagramMeasuredText?, _ paint: DiagramPaint, isBold: Bool = false, isItalic: Bool = false, part: DiagramScenePart) {
        guard let text else { return }
        builder.text(text, of: layout.lines, source: source, paint, isBold: isBold, isItalic: isItalic, part: part)
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
