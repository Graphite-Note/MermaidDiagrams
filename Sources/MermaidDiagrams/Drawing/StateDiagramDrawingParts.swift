/**
 * File: StateDiagramDrawingParts.swift
 * ------------------------------------
 * Layer: Core
 * Description: A laid-out state diagram's geometry grouped by how it is painted, back to front as Pele draws it, as
 *              Core Graphics paths or in any kind a drawing records.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.3
 * Date: 24/11/2026
 */

import CoreGraphics

/// A laid-out state diagram's geometry grouped by how it is painted, so that drawing it in any colors is a handful of
/// fills and strokes, by Core Graphics (`StateDiagramRenderer`) or by a view's own shapes. Back to front, as Pele draws:
/// the composite states' boxes and the dashed lines between their regions, as a flowchart's groups are drawn; the
/// transitions, the dashed lines to the notes and the arrows; names of boxes transitions run through; the patches behind transition text and that text; the
/// states and their text; the notes and their text; the title.
public struct StateDiagramDrawingParts {
    /// The composite states' boxes, painted as a flowchart's groups are (`FlowchartClusterDrawingParts`).
    public let composites: FlowchartClusterDrawingParts
    /// The line under each named composite's title band, across its box, stroked one point wide in the border color
    /// (Pele's state/render.ts draws it with the box, before the name).
    public let compositeTitleRules: CGPath
    /// The lines between concurrent regions, stroked one point wide in the border color in dashes of 3 and gaps of 4.
    public let regionDividers: CGPath
    /// The transitions' lines, stroked one point wide with round caps in the line color.
    public let transitionLines: CGPath
    /// The lines from states to their notes, stroked one point wide in dashes of 3 and gaps of 4 in the border color.
    public let noteConnectors: CGPath
    /// The arrows at the ends of transitions, filled in the line color.
    public let arrows: CGPath
    /// The patches behind transition text, filled in the background color.
    public let transitionTextPatches: CGPath
    public let transitionTexts: [DiagramTextBlock]
    /// The boxes and the choices' diamonds, filled in the surface color.
    public let stateFills: CGPath
    /// The boxes' and diamonds' outlines, and the lines under the names of boxes with several descriptions, stroked one
    /// point wide in the border color.
    public let stateOutlines: CGPath
    /// The rings of ends, filled in the background color and stroked one point wide in the line color.
    public let endRings: CGPath
    /// Starts, the dots of ends, and the bars of forks and joins, filled in the line color.
    public let solidMarks: CGPath
    /// The states' names, and the descriptions under them in smaller type.
    public let stateTexts: [DiagramTextBlock]
    /// The notes' sheets, filled in the background color and stroked one point wide in the border color, with the folds
    /// of their corners (`noteFolds`) stroked the same.
    public let noteSheets: CGPath
    public let noteFolds: CGPath
    /// The notes' text, in a color between the background and the text (`DiagramPalette.noteText`).
    public let noteTexts: [DiagramTextBlock]
    /// The title, drawn bold, or nil.
    public let title: DiagramTextBlock?

    public static let lineWidth: CGFloat = 1
    public static let noteConnectorDashLengths: [CGFloat] = [3, 4]

    /// The corner radius of the patch behind a transition's text.
    static let transitionTextPatchCornerRadius: CGFloat = 3
    /// How much wider than its text the patch behind a transition's text is.
    static let transitionTextPatchExtraWidth: CGFloat = 8

    public init(layout: StateDiagramLayout) {
        composites = FlowchartClusterDrawingParts(clusters: layout.composites)
        let paths = StateDiagramPaths(layout: layout, making: DiagramCoreGraphicsPaths())
        compositeTitleRules = paths.compositeTitleRules.path
        regionDividers = paths.regionDividers.path
        transitionLines = paths.transitionLines.path
        noteConnectors = paths.noteConnectors.path
        arrows = paths.arrows.path
        transitionTextPatches = paths.transitionTextPatches.path
        transitionTexts = layout.transitions.compactMap(\.text)
        stateFills = paths.stateFills.path
        stateOutlines = paths.stateOutlines.path
        endRings = paths.endRings.path
        solidMarks = paths.solidMarks.path
        stateTexts = layout.states.flatMap { state in [state.name, state.details].compactMap { text in text } }
        noteSheets = paths.noteSheets.path
        noteFolds = paths.noteFolds.path
        noteTexts = layout.notes.map(\.text)
        title = layout.title
    }
}

/// The paths of `StateDiagramDrawingParts` in any kind a drawing records: Core Graphics paths or lanes of the scene's
/// workspace. A shape made whole (a box, an ellipse, an edge's line) is made for a moment, added where it is painted and
/// given back.
struct StateDiagramPaths<Path: DiagramPathRecording> {
    let compositeTitleRules: Path
    let regionDividers: Path
    let transitionLines: Path
    let noteConnectors: Path
    let arrows: Path
    let transitionTextPatches: Path
    let stateFills: Path
    let stateOutlines: Path
    let endRings: Path
    let solidMarks: Path
    let noteSheets: Path
    let noteFolds: Path

    init<Maker: DiagramPathMaking>(layout: StateDiagramLayout, making maker: Maker) where Maker.Path == Path {
        compositeTitleRules = maker.makePath()
        for composite in layout.composites {
            guard let title = composite.title else { continue }
            let band = composite.frame.minY + title.size.height + StateDiagramClusterGraph.titleRoom
            compositeTitleRules.move(to: CGPoint(x: composite.frame.minX, y: band))
            compositeTitleRules.addLine(to: CGPoint(x: composite.frame.maxX, y: band))
        }
        regionDividers = maker.makePath()
        for divider in layout.regionDividers { Self.add(divider, to: regionDividers, making: maker) }
        transitionLines = maker.makePath()
        noteConnectors = maker.makePath()
        arrows = maker.makePath()
        transitionTextPatches = maker.makePath()
        Self.addTransitions(of: layout, lines: transitionLines, arrows: arrows, textPatches: transitionTextPatches, making: maker)
        for note in layout.notes { Self.add(note.connector, to: noteConnectors, making: maker) }
        stateFills = maker.makePath()
        stateOutlines = maker.makePath()
        endRings = maker.makePath()
        solidMarks = maker.makePath()
        let shapes = (fills: stateFills, outlines: stateOutlines, endRings: endRings, solidMarks: solidMarks)
        for state in layout.states { Self.addShape(of: state, to: shapes, making: maker) }
        noteSheets = maker.makePath()
        noteFolds = maker.makePath()
        for note in layout.notes {
            let madeCount = maker.madePathCount
            noteSheets.addPath(StateDiagramShapeDrawing.noteSheet(in: note.frame, making: maker))
            noteFolds.addPath(StateDiagramShapeDrawing.noteFold(in: note.frame, making: maker))
            maker.givePathsBack(downTo: madeCount)
        }
    }

    /// The transitions' lines, their arrows and the patches behind their text.
    private static func addTransitions<Maker: DiagramPathMaking>(of layout: StateDiagramLayout, lines: Path, arrows: Path, textPatches: Path,
                                                                 making maker: Maker) where Maker.Path == Path {
        // A transition's arrow is only filled: nothing is ever stroked.
        let strokedMarks = maker.makePath()
        for transition in layout.transitions {
            add(transition.path, to: lines, making: maker)
            DiagramEdgeDrawing.addMark(transition.arrow, filled: arrows, stroked: strokedMarks)
            if let text = transition.text {
                let madeCount = maker.madePathCount
                let patch = text.frame.insetBy(dx: -StateDiagramDrawingParts.transitionTextPatchExtraWidth / 2, dy: 0)
                textPatches.addPath(maker.roundedRectangle(patch, cornerWidth: StateDiagramDrawingParts.transitionTextPatchCornerRadius,
                                                           cornerHeight: StateDiagramDrawingParts.transitionTextPatchCornerRadius))
                maker.givePathsBack(downTo: madeCount)
            }
        }
    }

    /// A line recorded on its own and added to `grouped`, as `CGMutablePath.addPath(_:)` adds it.
    private static func add<Maker: DiagramPathMaking>(_ line: DiagramPath, to grouped: Path, making maker: Maker) where Maker.Path == Path {
        let madeCount = maker.madePathCount
        let drawn = maker.makePath()
        DiagramEdgeDrawing.record(line, into: drawn)
        grouped.addPath(drawn)
        maker.givePathsBack(downTo: madeCount)
    }

    /// A state's shape, by how each part is painted.
    private static func addShape<Maker: DiagramPathMaking>(of state: StateDiagramLayoutState,
                                                           to shapes: (fills: Path, outlines: Path, endRings: Path, solidMarks: Path),
                                                           making maker: Maker) where Maker.Path == Path {
        let madeCount = maker.madePathCount
        defer { maker.givePathsBack(downTo: madeCount) }
        let frame = state.frame
        switch state.kind {
        case .state:
            shapes.fills.addPath(StateDiagramShapeDrawing.box(in: frame, making: maker), alsoTo: shapes.outlines)
            if state.details != nil, let name = state.name { shapes.outlines.addPath(StateDiagramShapeDrawing.rule(in: frame, below: name, making: maker)) }
        case .choice:
            shapes.fills.addPath(StateDiagramShapeDrawing.diamond(in: frame, making: maker), alsoTo: shapes.outlines)
        case .start: shapes.solidMarks.addEllipse(in: frame)
        case .end:
            shapes.endRings.addPath(StateDiagramShapeDrawing.endRing(in: frame, making: maker))
            shapes.solidMarks.addPath(StateDiagramShapeDrawing.endDot(in: frame, making: maker))
        case .fork, .join: shapes.solidMarks.addPath(StateDiagramShapeDrawing.bar(in: frame, making: maker))
        }
    }
}
