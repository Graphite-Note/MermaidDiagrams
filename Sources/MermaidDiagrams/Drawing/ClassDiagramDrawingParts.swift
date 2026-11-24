/**
 * File: ClassDiagramDrawingParts.swift
 * ------------------------------------
 * Layer: Core
 * Description: A laid-out class diagram's geometry grouped by how it is painted.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.3
 * Date: 23/11/2026
 */

import CoreGraphics

/// A laid-out class diagram's geometry grouped by how it is painted, so that drawing it in any colors is a handful of
/// fills and strokes, by Core Graphics (`ClassDiagramRenderer`) or by a view's own shapes. Back to front, as Pele
/// draws: the lines and their marks, the patches behind relation text and that text, the cardinalities, the boxes,
/// notes and their text, the title.
public struct ClassDiagramDrawingParts {
    /// Solid relations, stroked one point wide with round caps.
    public var solidLines: CGPath { solidLinesScenePath.coreGraphicsPath }
    let solidLinesScenePath: DiagramScenePath
    /// Dashed relations (`..`), stroked one point wide in dashes of 6 and gaps of 4.
    public var dashedLines: CGPath { dashedLinesScenePath.coreGraphicsPath }
    let dashedLinesScenePath: DiagramScenePath
    /// The lines from notes to their classes, stroked one point wide in dashes of 2 and gaps of 4.
    public var dottedLines: CGPath { dottedLinesScenePath.coreGraphicsPath }
    let dottedLinesScenePath: DiagramScenePath
    /// Arrows and composition diamonds, filled in the line color.
    public var filledMarks: CGPath { filledMarksScenePath.coreGraphicsPath }
    let filledMarksScenePath: DiagramScenePath
    /// Triangles, diamonds and rings, stroked one point wide in the line color.
    public var strokedMarks: CGPath { strokedMarksScenePath.coreGraphicsPath }
    let strokedMarksScenePath: DiagramScenePath
    /// The patches behind relation text, filled in the background color.
    public var edgeTextPatches: CGPath { edgeTextPatchesScenePath.coreGraphicsPath }
    let edgeTextPatchesScenePath: DiagramScenePath
    public let edgeTexts: [DiagramTextBlock]
    /// Drawn in the muted color.
    public let cardinalities: [DiagramTextBlock]
    /// The classes' boxes, filled in the surface color.
    public var classFills: CGPath { classFillsScenePath.coreGraphicsPath }
    let classFillsScenePath: DiagramScenePath
    /// The notes, filled in the note color.
    public var noteFills: CGPath { noteFillsScenePath.coreGraphicsPath }
    let noteFillsScenePath: DiagramScenePath
    /// The boxes' and notes' outlines, the lines between compartments and the notes' folds, stroked one point wide in
    /// the border color.
    public var outlines: CGPath { outlinesScenePath.coreGraphicsPath }
    let outlinesScenePath: DiagramScenePath
    /// Drawn small in the muted color.
    public let annotations: [DiagramTextBlock]
    /// The classes' names, drawn bold.
    public let names: [DiagramTextBlock]
    /// Each class's attributes and methods: static ones underlined, abstract ones in italics.
    public let members: [ClassDiagramLayoutMember]
    /// The lines under static members, stroked one point wide in the text color.
    public var memberUnderlines: CGPath { memberUnderlinesScenePath.coreGraphicsPath }
    let memberUnderlinesScenePath: DiagramScenePath
    /// The notes' text and the lollipop interfaces' names.
    public let noteTexts: [DiagramTextBlock]
    /// The title, drawn bold, or nil.
    public let title: DiagramTextBlock?
    /// The namespaces' boxes, painted as a flowchart's groups are; empty parts for a diagram without namespaces.
    public let namespaces: FlowchartClusterDrawingParts

    public static let lineWidth: CGFloat = 1
    public static let dashedDashLengths: [CGFloat] = [6, 4]
    public static let dottedDashLengths: [CGFloat] = [2, 4]

    /// The corner radius of a class's box: Pele's `--pele-radius`.
    static let boxCornerRadius: CGFloat = 4
    /// The size of a note's folded corner.
    static let noteFold: CGFloat = 8
    /// How far below a line's baseline its underline is, as a fraction of the font size.
    static let underlineDropRatio: CGFloat = 0.12

    public init(layout: ClassDiagramLayout) {
        namespaces = FlowchartClusterDrawingParts(clusters: layout.namespaces)
        let lines = LinePaths(edges: layout.relations + layout.noteLinks)
        solidLinesScenePath = lines.solid
        dashedLinesScenePath = lines.dashed
        dottedLinesScenePath = lines.dotted
        filledMarksScenePath = lines.filledMarks
        strokedMarksScenePath = lines.strokedMarks
        edgeTextPatchesScenePath = lines.textPatches
        edgeTexts = layout.relations.compactMap(\.text)
        cardinalities = layout.relations.flatMap { edge in [edge.sourceCardinality, edge.targetCardinality].compactMap { cardinality in cardinality } }
        let boxes = BoxPaths(classes: layout.classes, notes: layout.notes)
        classFillsScenePath = boxes.classFills
        noteFillsScenePath = boxes.noteFills
        outlinesScenePath = boxes.outlines
        annotations = layout.classes.flatMap(\.annotations)
        names = layout.classes.map(\.name)
        members = layout.classes.flatMap(\.members)
        memberUnderlinesScenePath = Self.underlines(of: members)
        noteTexts = layout.notes.map(\.text) + layout.interfaces
        title = layout.title
    }

    /// A line under each static member's text, from its first character to its last.
    private static func underlines(of members: [ClassDiagramLayoutMember]) -> DiagramScenePath {
        var path = DiagramScenePath()
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
        var solid = DiagramScenePath()
        var dashed = DiagramScenePath()
        var dotted = DiagramScenePath()
        var filledMarks = DiagramScenePath()
        var strokedMarks = DiagramScenePath()
        var textPatches = DiagramScenePath()

        init(edges: [ClassDiagramLayoutEdge]) {
            for edge in edges {
                let line = DiagramEdgeDrawing.path(edge.path)
                switch edge.line {
                case .solid: solid.addPath(line)
                case .dashed: dashed.addPath(line)
                case .dotted: dotted.addPath(line)
                }
                for mark in [edge.sourceMark, edge.targetMark].compactMap({ mark in mark }) {
                    ClassDiagramMarkDrawing.addMark(mark, filled: &filledMarks, stroked: &strokedMarks)
                }
                if let text = edge.text {
                    textPatches.addPathOfRoundedRect(text.frame.insetBy(dx: -FlowchartDrawingParts.edgeTextPatchExtraWidth / 2, dy: 0),
                                               cornerWidth: FlowchartDrawingParts.edgeTextPatchCornerRadius,
                                               cornerHeight: FlowchartDrawingParts.edgeTextPatchCornerRadius)
                }
            }
        }
    }

    /// The boxes and notes to fill, and every outline and inner line to stroke.
    private struct BoxPaths {
        var classFills = DiagramScenePath()
        var noteFills = DiagramScenePath()
        var outlines = DiagramScenePath()

        init(classes: [ClassDiagramLayoutClass], notes: [ClassDiagramLayoutNote]) {
            for box in classes {
                let outline = DiagramScenePath(roundedRect: box.frame, cornerWidth: ClassDiagramDrawingParts.boxCornerRadius,
                                     cornerHeight: ClassDiagramDrawingParts.boxCornerRadius)
                classFills.addPath(outline)
                outlines.addPath(outline)
                for y in box.dividerYs {
                    outlines.move(to: CGPoint(x: box.frame.minX, y: y))
                    outlines.addLine(to: CGPoint(x: box.frame.maxX, y: y))
                }
            }
            for note in notes {
                let frame = note.frame
                let fold = ClassDiagramDrawingParts.noteFold
                var outline = DiagramScenePath()
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
