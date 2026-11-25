/**
 * File: ReferenceClassDiagramDrawingParts.swift
 * ---------------------------------------------
 * Layer: Tests
 * Description: 0.7.0's class diagram drawing parts and relation marks, frozen as main 2a0cc65 made them in Core
 *              Graphics paths, which the drawing parts and scenes made by the generic path code are compared with.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// A laid-out class diagram's geometry grouped by how it is painted, so that drawing it in any colors is a handful of
/// fills and strokes, by Core Graphics (`ClassDiagramRenderer`) or by a view's own shapes. Back to front, as Pele
/// draws: the lines and their marks, the patches behind relation text and that text, the cardinalities, the boxes,
/// notes and their text, the title.
struct ReferenceClassDiagramDrawingParts {
    /// Solid relations, stroked one point wide with round caps.
    let solidLines: CGPath
    /// Dashed relations (`..`), stroked one point wide in dashes of 6 and gaps of 4.
    let dashedLines: CGPath
    /// The lines from notes to their classes, stroked one point wide in dashes of 2 and gaps of 4.
    let dottedLines: CGPath
    /// Arrows and composition diamonds, filled in the line color.
    let filledMarks: CGPath
    /// Triangles, diamonds and rings, stroked one point wide in the line color.
    let strokedMarks: CGPath
    /// The patches behind relation text, filled in the background color.
    let edgeTextPatches: CGPath
    let edgeTexts: [DiagramTextBlock]
    /// Drawn in the muted color.
    let cardinalities: [DiagramTextBlock]
    /// The classes' boxes, filled in the surface color.
    let classFills: CGPath
    /// The notes, filled in the note color.
    let noteFills: CGPath
    /// The boxes' and notes' outlines, the lines between compartments and the notes' folds, stroked one point wide in
    /// the border color.
    let outlines: CGPath
    /// Drawn small in the muted color.
    let annotations: [DiagramTextBlock]
    /// The classes' names, drawn bold.
    let names: [DiagramTextBlock]
    /// Each class's attributes and methods: static ones underlined, abstract ones in italics.
    let members: [ClassDiagramLayoutMember]
    /// The lines under static members, stroked one point wide in the text color.
    let memberUnderlines: CGPath
    /// The notes' text and the lollipop interfaces' names.
    let noteTexts: [DiagramTextBlock]
    /// The title, drawn bold, or nil.
    let title: DiagramTextBlock?
    /// The namespaces' boxes, painted as a flowchart's groups are; empty parts for a diagram without namespaces.
    let namespaces: FlowchartClusterDrawingParts

    static let lineWidth: CGFloat = 1
    static let dashedDashLengths: [CGFloat] = [6, 4]
    static let dottedDashLengths: [CGFloat] = [2, 4]

    /// The corner radius of a class's box: Pele's `--pele-radius`.
    static let boxCornerRadius: CGFloat = 4
    /// The size of a note's folded corner.
    static let noteFold: CGFloat = 8
    /// How far below a line's baseline its underline is, as a fraction of the font size.
    static let underlineDropRatio: CGFloat = 0.12

    init(layout: ClassDiagramLayout) {
        namespaces = FlowchartClusterDrawingParts(clusters: layout.namespaces)
        let lines = LinePaths(edges: layout.relations + layout.noteLinks)
        solidLines = lines.solid
        dashedLines = lines.dashed
        dottedLines = lines.dotted
        filledMarks = lines.filledMarks
        strokedMarks = lines.strokedMarks
        edgeTextPatches = lines.textPatches
        edgeTexts = layout.relations.compactMap(\.text)
        cardinalities = layout.relations.flatMap { edge in [edge.sourceCardinality, edge.targetCardinality].compactMap { cardinality in cardinality } }
        let boxes = BoxPaths(classes: layout.classes, notes: layout.notes)
        classFills = boxes.classFills
        noteFills = boxes.noteFills
        outlines = boxes.outlines
        annotations = layout.classes.flatMap(\.annotations)
        names = layout.classes.map(\.name)
        members = layout.classes.flatMap(\.members)
        memberUnderlines = Self.underlines(of: members)
        noteTexts = layout.notes.map(\.text) + layout.interfaces
        title = layout.title
    }

    /// A line under each static member's text, from its first character to its last.
    private static func underlines(of members: [ClassDiagramLayoutMember]) -> CGPath {
        let path = CGMutablePath()
        for member in members {
            switch member.classifier {
            case .static:
                let text = member.text
                let y = text.center.y + text.fontSize * (DiagramTextDrawing.baselineShiftRatio + underlineDropRatio)
                path.move(to: CGPoint(x: text.frame.minX, y: y))
                path.addLine(to: CGPoint(x: text.frame.maxX, y: y))
            case .plain, .abstract:
                continue
            }
        }
        return path
    }

    /// The lines by stroke, their marks, and the patches behind relation text.
    private struct LinePaths {
        let solid = CGMutablePath()
        let dashed = CGMutablePath()
        let dotted = CGMutablePath()
        let filledMarks = CGMutablePath()
        let strokedMarks = CGMutablePath()
        let textPatches = CGMutablePath()

        init(edges: [ClassDiagramLayoutEdge]) {
            for edge in edges {
                let line = DiagramEdgeDrawing.path(edge.path)
                switch edge.line {
                case .solid: solid.addPath(line)
                case .dashed: dashed.addPath(line)
                case .dotted: dotted.addPath(line)
                }
                for mark in [edge.sourceMark, edge.targetMark].compactMap({ mark in mark }) {
                    ReferenceClassDiagramMarkDrawing.addMark(mark, filled: filledMarks, stroked: strokedMarks)
                }
                if let text = edge.text {
                    textPatches.addPath(CGPath(roundedRect: text.frame.insetBy(dx: -FlowchartDrawingParts.edgeTextPatchExtraWidth / 2, dy: 0),
                                               cornerWidth: FlowchartDrawingParts.edgeTextPatchCornerRadius,
                                               cornerHeight: FlowchartDrawingParts.edgeTextPatchCornerRadius, transform: nil))
                }
            }
        }
    }

    /// The boxes and notes to fill, and every outline and inner line to stroke.
    private struct BoxPaths {
        let classFills = CGMutablePath()
        let noteFills = CGMutablePath()
        let outlines = CGMutablePath()

        init(classes: [ClassDiagramLayoutClass], notes: [ClassDiagramLayoutNote]) {
            for box in classes {
                let outline = CGPath(roundedRect: box.frame, cornerWidth: ReferenceClassDiagramDrawingParts.boxCornerRadius,
                                     cornerHeight: ReferenceClassDiagramDrawingParts.boxCornerRadius, transform: nil)
                classFills.addPath(outline)
                outlines.addPath(outline)
                for y in box.dividerYs {
                    outlines.move(to: CGPoint(x: box.frame.minX, y: y))
                    outlines.addLine(to: CGPoint(x: box.frame.maxX, y: y))
                }
            }
            for note in notes {
                let frame = note.frame
                let fold = ReferenceClassDiagramDrawingParts.noteFold
                let outline = CGMutablePath()
                outline.addLines(between: [CGPoint(x: frame.minX, y: frame.minY), CGPoint(x: frame.maxX - fold, y: frame.minY),
                                           CGPoint(x: frame.maxX, y: frame.minY + fold), CGPoint(x: frame.maxX, y: frame.maxY),
                                           CGPoint(x: frame.minX, y: frame.maxY)])
                outline.closeSubpath()
                noteFills.addPath(outline)
                outlines.addPath(outline)
                outlines.addLines(between: [CGPoint(x: frame.maxX - fold, y: frame.minY), CGPoint(x: frame.maxX - fold, y: frame.minY + fold),
                                            CGPoint(x: frame.maxX, y: frame.minY + fold)])
            }
        }
    }
}

/// The geometry of a relation's marks, Pele's: a hollow triangle, a diamond filled for composition and hollow for
/// aggregation, the flowchart's filled arrow, and a hollow ring.
enum ReferenceClassDiagramMarkDrawing {
    /// Adds a mark to the paths that are filled in the line color (an arrow, a composition's diamond) and those
    /// stroked in it (a triangle, both diamonds, a ring).
    static func addMark(_ mark: ClassDiagramRelationMark, filled: CGMutablePath, stroked: CGMutablePath) {
        let direction = mark.direction
        let normal = CGVector(dx: -direction.dy, dy: direction.dx)
        let tip = mark.tip
        func point(back distance: CGFloat, across offset: CGFloat) -> CGPoint {
            CGPoint(x: tip.x - direction.dx * distance + normal.dx * offset, y: tip.y - direction.dy * distance + normal.dy * offset)
        }
        switch mark.end {
        case .none: break
        case .inheritance:
            let length = ClassDiagramMarkGeometry.triangleLength
            let halfWidth = ClassDiagramMarkGeometry.triangleHalfWidth
            stroked.addLines(between: [tip, point(back: length, across: halfWidth), point(back: length, across: -halfWidth)])
            stroked.closeSubpath()
        case .composition:
            let diamond = diamondPath(tip: tip, point: point)
            filled.addPath(diamond)
            stroked.addPath(diamond)
        case .aggregation:
            stroked.addPath(diamondPath(tip: tip, point: point))
        case .arrow:
            DiagramEdgeDrawing.addMark(DiagramEdgeMark(arrowhead: .arrow, tip: tip, direction: direction), filled: filled, stroked: stroked)
        case .lollipop:
            let radius = ClassDiagramMarkGeometry.ringRadius
            let center = point(back: radius, across: 0)
            stroked.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius))
        }
    }

    /// A diamond from the tip back along the line, its widest at half its length.
    private static func diamondPath(tip: CGPoint, point: (_ distance: CGFloat, _ offset: CGFloat) -> CGPoint) -> CGPath {
        let length = ClassDiagramMarkGeometry.diamondLength
        let halfWidth = ClassDiagramMarkGeometry.diamondHalfWidth
        let diamond = CGMutablePath()
        diamond.addLines(between: [tip, point(length / 2, halfWidth), point(length, 0), point(length / 2, -halfWidth)])
        diamond.closeSubpath()
        return diamond
    }
}
