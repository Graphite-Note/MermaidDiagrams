/**
 * File: ReferenceStateDiagramDrawingParts.swift
 * ---------------------------------------------
 * Layer: Tests
 * Description: 0.7.0's state diagram drawing parts and shapes, frozen as main 2a0cc65 made them in Core Graphics
 *              paths, which the drawing parts and scenes made by the generic path code are compared with.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// A laid-out state diagram's geometry grouped by how it is painted, so that drawing it in any colors is a handful of
/// fills and strokes, by Core Graphics (`StateDiagramRenderer`) or by a view's own shapes. Back to front, as Pele draws:
/// the composite states' boxes and the dashed lines between their regions, as a flowchart's groups are drawn; the
/// transitions, the dashed lines to the notes and the arrows; names of boxes transitions run through; the patches behind transition text and that text; the
/// states and their text; the notes and their text; the title.
struct ReferenceStateDiagramDrawingParts {
    /// The composite states' boxes, painted as a flowchart's groups are (`FlowchartClusterDrawingParts`).
    let composites: FlowchartClusterDrawingParts
    /// The line under each named composite's title band, across its box, stroked one point wide in the border color
    /// (Pele's state/render.ts draws it with the box, before the name).
    let compositeTitleRules: CGPath
    /// The lines between concurrent regions, stroked one point wide in the border color in dashes of 3 and gaps of 4.
    let regionDividers: CGPath
    /// The transitions' lines, stroked one point wide with round caps in the line color.
    let transitionLines: CGPath
    /// The lines from states to their notes, stroked one point wide in dashes of 3 and gaps of 4 in the border color.
    let noteConnectors: CGPath
    /// The arrows at the ends of transitions, filled in the line color.
    let arrows: CGPath
    /// The patches behind transition text, filled in the background color.
    let transitionTextPatches: CGPath
    let transitionTexts: [DiagramTextBlock]
    /// The boxes and the choices' diamonds, filled in the surface color.
    let stateFills: CGPath
    /// The boxes' and diamonds' outlines, and the lines under the names of boxes with several descriptions, stroked one
    /// point wide in the border color.
    let stateOutlines: CGPath
    /// The rings of ends, filled in the background color and stroked one point wide in the line color.
    let endRings: CGPath
    /// Starts, the dots of ends, and the bars of forks and joins, filled in the line color.
    let solidMarks: CGPath
    /// The states' names, and the descriptions under them in smaller type.
    let stateTexts: [DiagramTextBlock]
    /// The notes' sheets, filled in the background color and stroked one point wide in the border color, with the folds
    /// of their corners (`noteFolds`) stroked the same.
    let noteSheets: CGPath
    let noteFolds: CGPath
    /// The notes' text, in a color between the background and the text (`DiagramPalette.noteText`).
    let noteTexts: [DiagramTextBlock]
    /// The title, drawn bold, or nil.
    let title: DiagramTextBlock?

    static let lineWidth: CGFloat = 1
    static let noteConnectorDashLengths: [CGFloat] = [3, 4]

    /// The corner radius of the patch behind a transition's text.
    static let transitionTextPatchCornerRadius: CGFloat = 3
    /// How much wider than its text the patch behind a transition's text is.
    static let transitionTextPatchExtraWidth: CGFloat = 8

    init(layout: StateDiagramLayout) {
        composites = FlowchartClusterDrawingParts(clusters: layout.composites)
        let rules = CGMutablePath()
        for composite in layout.composites {
            guard let title = composite.title else { continue }
            let band = composite.frame.minY + title.size.height + StateDiagramClusterGraph.titleRoom
            rules.move(to: CGPoint(x: composite.frame.minX, y: band))
            rules.addLine(to: CGPoint(x: composite.frame.maxX, y: band))
        }
        compositeTitleRules = rules
        let dividers = CGMutablePath()
        for divider in layout.regionDividers { dividers.addPath(DiagramEdgeDrawing.path(divider)) }
        regionDividers = dividers
        let transitions = TransitionPaths(transitions: layout.transitions, notes: layout.notes)
        let states = StatePaths(states: layout.states)
        let notes = NotePaths(notes: layout.notes)
        transitionLines = transitions.lines
        noteConnectors = transitions.noteConnectors
        arrows = transitions.arrows
        transitionTextPatches = transitions.textPatches
        transitionTexts = layout.transitions.compactMap(\.text)
        stateFills = states.fills
        stateOutlines = states.outlines
        endRings = states.endRings
        solidMarks = states.solidMarks
        stateTexts = layout.states.flatMap { state in [state.name, state.details].compactMap { text in text } }
        noteSheets = notes.sheets
        noteFolds = notes.folds
        noteTexts = layout.notes.map(\.text)
        title = layout.title
    }

    /// The transitions' lines and arrows, the patches behind their text, and the lines to the notes.
    private struct TransitionPaths {
        let lines = CGMutablePath()
        let noteConnectors = CGMutablePath()
        let arrows = CGMutablePath()
        let textPatches = CGMutablePath()

        init(transitions: [StateDiagramLayoutTransition], notes: [StateDiagramLayoutNote]) {
            // A transition's arrow is only filled: nothing is ever stroked.
            let strokedMarks = CGMutablePath()
            for transition in transitions {
                lines.addPath(DiagramEdgeDrawing.path(transition.path))
                DiagramEdgeDrawing.addMark(transition.arrow, filled: arrows, stroked: strokedMarks)
                if let text = transition.text {
                    let patch = text.frame.insetBy(dx: -ReferenceStateDiagramDrawingParts.transitionTextPatchExtraWidth / 2, dy: 0)
                    textPatches.addPath(CGPath(roundedRect: patch, cornerWidth: ReferenceStateDiagramDrawingParts.transitionTextPatchCornerRadius,
                                               cornerHeight: ReferenceStateDiagramDrawingParts.transitionTextPatchCornerRadius, transform: nil))
                }
            }
            for note in notes { noteConnectors.addPath(DiagramEdgeDrawing.path(note.connector)) }
        }
    }

    /// The states' shapes, by how each part is painted.
    private struct StatePaths {
        let fills = CGMutablePath()
        let outlines = CGMutablePath()
        let endRings = CGMutablePath()
        let solidMarks = CGMutablePath()

        init(states: [StateDiagramLayoutState]) {
            for state in states {
                let frame = state.frame
                switch state.kind {
                case .state:
                    let box = ReferenceStateDiagramShapeDrawing.box(in: frame)
                    fills.addPath(box)
                    outlines.addPath(box)
                    if state.details != nil, let name = state.name { outlines.addPath(ReferenceStateDiagramShapeDrawing.rule(in: frame, below: name)) }
                case .choice:
                    let diamond = ReferenceStateDiagramShapeDrawing.diamond(in: frame)
                    fills.addPath(diamond)
                    outlines.addPath(diamond)
                case .start: solidMarks.addEllipse(in: frame)
                case .end:
                    endRings.addPath(ReferenceStateDiagramShapeDrawing.endRing(in: frame))
                    solidMarks.addPath(ReferenceStateDiagramShapeDrawing.endDot(in: frame))
                case .fork, .join: solidMarks.addPath(ReferenceStateDiagramShapeDrawing.bar(in: frame))
                }
            }
        }
    }

    /// The notes' sheets and folds.
    private struct NotePaths {
        let sheets = CGMutablePath()
        let folds = CGMutablePath()

        init(notes: [StateDiagramLayoutNote]) {
            for note in notes {
                sheets.addPath(ReferenceStateDiagramShapeDrawing.noteSheet(in: note.frame))
                folds.addPath(ReferenceStateDiagramShapeDrawing.noteFold(in: note.frame))
            }
        }
    }
}

/// The outlines of a state diagram's shapes, Pele's, as Core Graphics paths in a frame.
enum ReferenceStateDiagramShapeDrawing {
    /// The largest corner radius of a state's box: Pele's.
    static let boxCornerRadius: CGFloat = 10
    /// The corner radius of a fork's or a join's bar.
    static let barCornerRadius: CGFloat = 2
    /// The radius of an end's inner dot; its ring is half a point inside its frame, so that its stroke stays inside.
    static let endDotRadius: CGFloat = 5
    static let endRingInset: CGFloat = 0.5
    /// How far down and in a note's folded corner reaches.
    static let noteFoldSize: CGFloat = 8
    /// How far below a box's name the line under it is.
    static let ruleGap: CGFloat = 6

    /// A box, rounded at most `boxCornerRadius`.
    static func box(in frame: CGRect) -> CGPath {
        let radius = min(boxCornerRadius, frame.height / 2)
        return CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    static func diamond(in frame: CGRect) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: [CGPoint(x: frame.midX, y: frame.minY), CGPoint(x: frame.maxX, y: frame.midY), CGPoint(x: frame.midX, y: frame.maxY),
                                CGPoint(x: frame.minX, y: frame.midY)])
        path.closeSubpath()
        return path
    }

    static func bar(in frame: CGRect) -> CGPath {
        CGPath(roundedRect: frame, cornerWidth: barCornerRadius, cornerHeight: barCornerRadius, transform: nil)
    }

    static func endRing(in frame: CGRect) -> CGPath {
        CGPath(ellipseIn: frame.insetBy(dx: endRingInset, dy: endRingInset), transform: nil)
    }

    static func endDot(in frame: CGRect) -> CGPath {
        CGPath(ellipseIn: CGRect(x: frame.midX - endDotRadius, y: frame.midY - endDotRadius, width: 2 * endDotRadius, height: 2 * endDotRadius),
               transform: nil)
    }

    /// A note's sheet, its top right corner cut off where it folds.
    static func noteSheet(in frame: CGRect) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: [CGPoint(x: frame.minX, y: frame.minY), CGPoint(x: frame.maxX - noteFoldSize, y: frame.minY),
                                CGPoint(x: frame.maxX, y: frame.minY + noteFoldSize), CGPoint(x: frame.maxX, y: frame.maxY),
                                CGPoint(x: frame.minX, y: frame.maxY)])
        path.closeSubpath()
        return path
    }

    /// The fold of a note's top right corner.
    static func noteFold(in frame: CGRect) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: [CGPoint(x: frame.maxX - noteFoldSize, y: frame.minY), CGPoint(x: frame.maxX - noteFoldSize, y: frame.minY + noteFoldSize),
                                CGPoint(x: frame.maxX, y: frame.minY + noteFoldSize)])
        return path
    }

    /// The line across a box under its name, above its other descriptions.
    static func rule(in frame: CGRect, below name: DiagramTextBlock) -> CGPath {
        let path = CGMutablePath()
        let ruleHeight = name.frame.maxY + ruleGap
        path.move(to: CGPoint(x: frame.minX, y: ruleHeight))
        path.addLine(to: CGPoint(x: frame.maxX, y: ruleHeight))
        return path
    }
}
