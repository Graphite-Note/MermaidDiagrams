/**
 * File: ClassDiagramDrawingParts.swift
 * ------------------------------------
 * Layer: Core
 * Description: A laid-out class diagram's geometry grouped by how it is painted, as Core Graphics paths or in any kind
 *              a drawing records.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.4
 * Date: 26/11/2026
 */

import CoreGraphics

/// A laid-out class diagram's geometry grouped by how it is painted, so that drawing it in any colors is a handful of
/// fills and strokes, by Core Graphics (`ClassDiagramRenderer`) or by a view's own shapes. Back to front, as Pele
/// draws: the lines and their marks, the patches behind relation text and that text, the cardinalities, the boxes,
/// notes and their text, the title.
public struct ClassDiagramDrawingParts {
    /// Solid relations, stroked one point wide with round caps.
    public let solidLines: CGPath
    /// Dashed relations (`..`), stroked one point wide in dashes of 6 and gaps of 4.
    public let dashedLines: CGPath
    /// The lines from notes to their classes, stroked one point wide in dashes of 2 and gaps of 4.
    public let dottedLines: CGPath
    /// Arrows and composition diamonds, filled in the line color.
    public let filledMarks: CGPath
    /// Triangles, diamonds and rings, stroked one point wide in the line color.
    public let strokedMarks: CGPath
    /// The patches behind relation text, filled in the background color.
    public let edgeTextPatches: CGPath
    public let edgeTexts: [DiagramTextBlock]
    /// Drawn in the muted color.
    public let cardinalities: [DiagramTextBlock]
    /// The classes' boxes, filled in the surface color.
    public let classFills: CGPath
    /// The notes, filled in the note color.
    public let noteFills: CGPath
    /// The boxes' and notes' outlines, the lines between compartments and the notes' folds, stroked one point wide in
    /// the border color.
    public let outlines: CGPath
    /// Drawn small in the muted color.
    public let annotations: [DiagramTextBlock]
    /// The classes' names, drawn bold.
    public let names: [DiagramTextBlock]
    /// Each class's attributes and methods: static ones underlined, abstract ones in italics.
    public let members: [ClassDiagramLayoutMember]
    /// The lines under static members, stroked one point wide in the text color.
    public let memberUnderlines: CGPath
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
        let paths = ClassDiagramPaths(layout: layout, making: DiagramCoreGraphicsPaths())
        solidLines = paths.solidLines.path
        dashedLines = paths.dashedLines.path
        dottedLines = paths.dottedLines.path
        filledMarks = paths.filledMarks.path
        strokedMarks = paths.strokedMarks.path
        edgeTextPatches = paths.edgeTextPatches.path
        edgeTexts = layout.relations.compactMap(\.text)
        cardinalities = layout.relations.flatMap { edge in [edge.sourceCardinality, edge.targetCardinality].compactMap { cardinality in cardinality } }
        classFills = paths.classFills.path
        noteFills = paths.noteFills.path
        outlines = paths.outlines.path
        annotations = layout.classes.flatMap(\.annotations)
        names = layout.classes.map(\.name)
        members = layout.classes.flatMap(\.members)
        memberUnderlines = paths.memberUnderlines.path
        noteTexts = layout.notes.map(\.text) + layout.interfaces
        title = layout.title
    }
}

/// The paths of `ClassDiagramDrawingParts` in any kind a drawing records: Core Graphics paths or lanes of the scene's
/// workspace. A shape made whole (a box, a relation's line, a diamond) is made for a moment, added where it is painted
/// and given back.
struct ClassDiagramPaths<Path: DiagramPathRecording> {
    let solidLines: Path
    let dashedLines: Path
    let dottedLines: Path
    let filledMarks: Path
    let strokedMarks: Path
    let edgeTextPatches: Path
    let classFills: Path
    let noteFills: Path
    let outlines: Path
    let memberUnderlines: Path

    init<Maker: DiagramPathMaking>(layout: ClassDiagramLayout, making maker: Maker) where Maker.Path == Path {
        solidLines = maker.makePath()
        dashedLines = maker.makePath()
        dottedLines = maker.makePath()
        filledMarks = maker.makePath()
        strokedMarks = maker.makePath()
        edgeTextPatches = maker.makePath()
        let lines = LinePaths(solid: solidLines, dashed: dashedLines, dotted: dottedLines, filledMarks: filledMarks, strokedMarks: strokedMarks,
                              textPatches: edgeTextPatches)
        for edge in layout.placedRelations { lines.addLine(of: edge, segments: layout.segments, making: maker) }
        for edge in layout.placedNoteLinks { lines.addLine(of: edge, segments: layout.segments, making: maker) }
        classFills = maker.makePath()
        noteFills = maker.makePath()
        outlines = maker.makePath()
        Self.addBoxes(of: layout, fills: classFills, noteFills: noteFills, outlines: outlines, making: maker)
        memberUnderlines = maker.makePath()
        Self.addUnderlines(of: layout, to: memberUnderlines)
    }

    /// The classes' boxes and the notes, filled and outlined, with the lines between compartments and the notes' folds.
    private static func addBoxes<Maker: DiagramPathMaking>(of layout: ClassDiagramLayout, fills classFills: Path, noteFills: Path, outlines: Path,
                                                           making maker: Maker) where Maker.Path == Path {
        for box in layout.placedClasses {
            let madeCount = maker.madePathCount
            let outline = maker.roundedRectangle(box.frame, cornerWidth: ClassDiagramDrawingParts.boxCornerRadius,
                                                 cornerHeight: ClassDiagramDrawingParts.boxCornerRadius)
            classFills.addPath(outline, alsoTo: outlines)
            maker.givePathsBack(downTo: madeCount)
            guard box.hasDividers else { continue }
            outlines.move(to: CGPoint(x: box.frame.minX, y: box.dividerYs.title))
            outlines.addLine(to: CGPoint(x: box.frame.maxX, y: box.dividerYs.title))
            outlines.move(to: CGPoint(x: box.frame.minX, y: box.dividerYs.attributes))
            outlines.addLine(to: CGPoint(x: box.frame.maxX, y: box.dividerYs.attributes))
        }
        for note in layout.placedNotes {
            let frame = note.frame
            let fold = ClassDiagramDrawingParts.noteFold
            let madeCount = maker.madePathCount
            let outline = maker.makePath()
            outline.addLines(between: [CGPoint(x: frame.minX, y: frame.minY), CGPoint(x: frame.maxX - fold, y: frame.minY),
                                       CGPoint(x: frame.maxX, y: frame.minY + fold), CGPoint(x: frame.maxX, y: frame.maxY),
                                       CGPoint(x: frame.minX, y: frame.maxY)])
            outline.closeSubpath()
            noteFills.addPath(outline, alsoTo: outlines)
            maker.givePathsBack(downTo: madeCount)
            outlines.addLines(between: [CGPoint(x: frame.maxX - fold, y: frame.minY), CGPoint(x: frame.maxX - fold, y: frame.minY + fold),
                                        CGPoint(x: frame.maxX, y: frame.minY + fold)])
        }
    }

    /// A line under each static member's text, from its first character to its last.
    private static func addUnderlines(of layout: ClassDiagramLayout, to memberUnderlines: Path) {
        for member in layout.placedMembers where member.classifier == .static {
            let text = member.text
            let y = text.center.y + text.fontSize * (DiagramTextDrawing.baselineShiftRatio + ClassDiagramDrawingParts.underlineDropRatio)
            memberUnderlines.move(to: CGPoint(x: text.frame.minX, y: y))
            memberUnderlines.addLine(to: CGPoint(x: text.frame.maxX, y: y))
        }
    }

    /// The lines by stroke, their marks, and the patches behind relation text.
    private struct LinePaths {
        let solid: Path
        let dashed: Path
        let dotted: Path
        let filledMarks: Path
        let strokedMarks: Path
        let textPatches: Path

        /// A relation's or a note's line by its stroke, its marks, and the patch behind its text.
        func addLine<Maker: DiagramPathMaking>(of edge: ClassDiagramPlacedEdge, segments: [DiagramPathSegment], making maker: Maker) where Maker.Path == Path {
            let madeCount = maker.madePathCount
            defer { maker.givePathsBack(downTo: madeCount) }
            let line = maker.makePath()
            DiagramRouteSegments.record(edge.path, of: segments, into: line)
            switch edge.line {
            case .solid: solid.addPath(line)
            case .dashed: dashed.addPath(line)
            case .dotted: dotted.addPath(line)
            }
            if let mark = edge.sourceMark { ClassDiagramMarkDrawing.addMark(mark, filled: filledMarks, stroked: strokedMarks, making: maker) }
            if let mark = edge.targetMark { ClassDiagramMarkDrawing.addMark(mark, filled: filledMarks, stroked: strokedMarks, making: maker) }
            if let text = edge.text {
                textPatches.addPath(maker.roundedRectangle(text.frame.insetBy(dx: -FlowchartDrawingParts.edgeTextPatchExtraWidth / 2, dy: 0),
                                                           cornerWidth: FlowchartDrawingParts.edgeTextPatchCornerRadius,
                                                           cornerHeight: FlowchartDrawingParts.edgeTextPatchCornerRadius))
            }
        }
    }
}
