/**
 * File: StateDiagramDrawingParts.swift
 * ------------------------------------
 * Layer: Core
 * Description: A laid-out state diagram's geometry grouped by how it is painted, back to front as Pele draws it.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.3
 * Date: 23/11/2026
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
    public var compositeTitleRules: CGPath { compositeTitleRulesScenePath.coreGraphicsPath }
    let compositeTitleRulesScenePath: DiagramScenePath
    /// The lines between concurrent regions, stroked one point wide in the border color in dashes of 3 and gaps of 4.
    public var regionDividers: CGPath { regionDividersScenePath.coreGraphicsPath }
    let regionDividersScenePath: DiagramScenePath
    /// The transitions' lines, stroked one point wide with round caps in the line color.
    public var transitionLines: CGPath { transitionLinesScenePath.coreGraphicsPath }
    let transitionLinesScenePath: DiagramScenePath
    /// The lines from states to their notes, stroked one point wide in dashes of 3 and gaps of 4 in the border color.
    public var noteConnectors: CGPath { noteConnectorsScenePath.coreGraphicsPath }
    let noteConnectorsScenePath: DiagramScenePath
    /// The arrows at the ends of transitions, filled in the line color.
    public var arrows: CGPath { arrowsScenePath.coreGraphicsPath }
    let arrowsScenePath: DiagramScenePath
    /// The patches behind transition text, filled in the background color.
    public var transitionTextPatches: CGPath { transitionTextPatchesScenePath.coreGraphicsPath }
    let transitionTextPatchesScenePath: DiagramScenePath
    public let transitionTexts: [DiagramTextBlock]
    /// The boxes and the choices' diamonds, filled in the surface color.
    public var stateFills: CGPath { stateFillsScenePath.coreGraphicsPath }
    let stateFillsScenePath: DiagramScenePath
    /// The boxes' and diamonds' outlines, and the lines under the names of boxes with several descriptions, stroked one
    /// point wide in the border color.
    public var stateOutlines: CGPath { stateOutlinesScenePath.coreGraphicsPath }
    let stateOutlinesScenePath: DiagramScenePath
    /// The rings of ends, filled in the background color and stroked one point wide in the line color.
    public var endRings: CGPath { endRingsScenePath.coreGraphicsPath }
    let endRingsScenePath: DiagramScenePath
    /// Starts, the dots of ends, and the bars of forks and joins, filled in the line color.
    public var solidMarks: CGPath { solidMarksScenePath.coreGraphicsPath }
    let solidMarksScenePath: DiagramScenePath
    /// The states' names, and the descriptions under them in smaller type.
    public let stateTexts: [DiagramTextBlock]
    /// The notes' sheets, filled in the background color and stroked one point wide in the border color, with the folds
    /// of their corners (`noteFolds`) stroked the same.
    public var noteSheets: CGPath { noteSheetsScenePath.coreGraphicsPath }
    let noteSheetsScenePath: DiagramScenePath
    public var noteFolds: CGPath { noteFoldsScenePath.coreGraphicsPath }
    let noteFoldsScenePath: DiagramScenePath
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
        var rules = DiagramScenePath()
        for composite in layout.composites {
            guard let title = composite.title else { continue }
            let band = composite.frame.minY + title.size.height + StateDiagramClusterGraph.titleRoom
            rules.move(to: CGPoint(x: composite.frame.minX, y: band))
            rules.addLine(to: CGPoint(x: composite.frame.maxX, y: band))
        }
        compositeTitleRulesScenePath = rules
        var dividers = DiagramScenePath()
        for divider in layout.regionDividers { dividers.addEdgePath(divider) }
        regionDividersScenePath = dividers
        let transitions = TransitionPaths(transitions: layout.transitions, notes: layout.notes)
        let states = StatePaths(states: layout.states)
        let notes = NotePaths(notes: layout.notes)
        transitionLinesScenePath = transitions.lines
        noteConnectorsScenePath = transitions.noteConnectors
        arrowsScenePath = transitions.arrows
        transitionTextPatchesScenePath = transitions.textPatches
        transitionTexts = layout.transitions.compactMap(\.text)
        stateFillsScenePath = states.fills
        stateOutlinesScenePath = states.outlines
        endRingsScenePath = states.endRings
        solidMarksScenePath = states.solidMarks
        stateTexts = layout.states.flatMap { state in [state.name, state.details].compactMap { text in text } }
        noteSheetsScenePath = notes.sheets
        noteFoldsScenePath = notes.folds
        noteTexts = layout.notes.map(\.text)
        title = layout.title
    }

    /// The transitions' lines and arrows, the patches behind their text, and the lines to the notes.
    private struct TransitionPaths {
        var lines = DiagramScenePath()
        var noteConnectors = DiagramScenePath()
        var arrows = DiagramScenePath()
        var textPatches = DiagramScenePath()

        init(transitions: [StateDiagramLayoutTransition], notes: [StateDiagramLayoutNote]) {
            // A transition's arrow is only filled: nothing is ever stroked.
            var strokedMarks = DiagramScenePath()
            for transition in transitions {
                lines.addEdgePath(transition.path)
                DiagramEdgeDrawing.addMark(transition.arrow, filled: &arrows, stroked: &strokedMarks)
                if let text = transition.text {
                    let patch = text.frame.insetBy(dx: -StateDiagramDrawingParts.transitionTextPatchExtraWidth / 2, dy: 0)
                    textPatches.addPathOfRoundedRect(patch, cornerWidth: StateDiagramDrawingParts.transitionTextPatchCornerRadius,
                                               cornerHeight: StateDiagramDrawingParts.transitionTextPatchCornerRadius)
                }
            }
            for note in notes { noteConnectors.addEdgePath(note.connector) }
        }
    }

    /// The states' shapes, by how each part is painted.
    private struct StatePaths {
        var fills = DiagramScenePath()
        var outlines = DiagramScenePath()
        var endRings = DiagramScenePath()
        var solidMarks = DiagramScenePath()

        init(states: [StateDiagramLayoutState]) {
            for state in states {
                let frame = state.frame
                switch state.kind {
                case .state:
                    let box = StateDiagramShapeDrawing.box(in: frame)
                    fills.addPath(box)
                    outlines.addPath(box)
                    if state.details != nil, let name = state.name { outlines.addPath(StateDiagramShapeDrawing.rule(in: frame, below: name)) }
                case .choice:
                    let diamond = StateDiagramShapeDrawing.diamond(in: frame)
                    fills.addPath(diamond)
                    outlines.addPath(diamond)
                case .start: solidMarks.addEllipse(in: frame)
                case .end:
                    endRings.addPath(StateDiagramShapeDrawing.endRing(in: frame))
                    solidMarks.addPath(StateDiagramShapeDrawing.endDot(in: frame))
                case .fork, .join: solidMarks.addPath(StateDiagramShapeDrawing.bar(in: frame))
                }
            }
        }
    }

    /// The notes' sheets and folds.
    private struct NotePaths {
        var sheets = DiagramScenePath()
        var folds = DiagramScenePath()

        init(notes: [StateDiagramLayoutNote]) {
            for note in notes {
                sheets.addPath(StateDiagramShapeDrawing.noteSheet(in: note.frame))
                folds.addPath(StateDiagramShapeDrawing.noteFold(in: note.frame))
            }
        }
    }
}
