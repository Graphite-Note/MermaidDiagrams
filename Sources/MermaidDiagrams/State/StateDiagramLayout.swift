/**
 * File: StateDiagramLayout.swift
 * ------------------------------
 * Layer: Core
 * Description: A state diagram laid out on the page, kept as placed records over one list of measured lines and one
 *              list of path segments that the scene reads directly; its states, transitions, notes and title made as
 *              blocks and paths of their own only when a host asks.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.3
 * Date: 26/11/2026
 */

import CoreGraphics

/// A state diagram laid out on a page whose origin is the top left corner and whose y runs down, in points. Drawing
/// it needs only colors: every position, path and text measurement is here.
public struct StateDiagramLayout: Sendable {
    public let size: CGSize
    /// The font the states' names were measured in; descriptions, transition text and notes are in the same font at
    /// their own `fontSize`.
    public let font: DiagramFont
    /// The lines of every measured text; a line read as written points into `source`, the others into the lines' own bytes.
    let lines: DiagramMeasuredLines
    let source: MermaidSourceText
    /// Every path's segments: the transitions', then the dashed lines to the notes.
    let segments: [DiagramPathSegment]
    /// The states drawn, in the diagram's order: a composite state is its box, in `composites`.
    let placedStates: [StateDiagramPlacedState]
    /// The transitions placed, in the order they are written.
    let placedTransitions: [StateDiagramPlacedTransition]
    let placedNotes: [StateDiagramPlacedNote]
    let placedTitle: DiagramMeasuredText?
    /// The composite states' boxes, outer ones first, each with its name along its top, drawn as a flowchart's groups
    /// are; a composite state is its box and is not in `states`.
    public let composites: [FlowchartLayoutCluster]
    /// The dashed lines between the concurrent regions of composite states' bodies.
    public let regionDividers: [DiagramPath]

    /// The states in the diagram's order, made from the records.
    public var states: [StateDiagramLayoutState] {
        placedStates.map { state in StateDiagramLayoutState(kind: state.kind, frame: state.frame, name: state.name.map(block(of:)),
                                                            details: state.details.map(block(of:))) }
    }

    /// The transitions in the order they are written, transitions to a state itself included.
    public var transitions: [StateDiagramLayoutTransition] {
        placedTransitions.map { transition in
            StateDiagramLayoutTransition(path: transition.line.path(in: segments), arrow: transition.arrow, text: transition.text.map(block(of:)))
        }
    }

    public var notes: [StateDiagramLayoutNote] {
        placedNotes.map { note in StateDiagramLayoutNote(frame: note.frame, text: block(of: note.text), connector: note.connector.path(in: segments)) }
    }

    /// The diagram's title above it, or nil.
    public var title: DiagramTextBlock? { placedTitle.map(block(of:)) }

    func block(of text: DiagramMeasuredText) -> DiagramTextBlock {
        source.withBytes { source in DiagramTextBlock(text, of: lines, source: source) }
    }

    init(size: CGSize, font: DiagramFont, lines: DiagramMeasuredLines, source: MermaidSourceText, segments: [DiagramPathSegment],
         placedStates: [StateDiagramPlacedState], placedTransitions: [StateDiagramPlacedTransition], placedNotes: [StateDiagramPlacedNote],
         placedTitle: DiagramMeasuredText?, composites: [FlowchartLayoutCluster], regionDividers: [DiagramPath]) {
        self.size = size
        self.font = font
        self.lines = lines
        self.source = source
        self.segments = segments
        self.placedStates = placedStates
        self.placedTransitions = placedTransitions
        self.placedNotes = placedNotes
        self.placedTitle = placedTitle
        self.composites = composites
        self.regionDividers = regionDividers
    }

    /// A layout of states, transitions and notes made as blocks and paths of their own (0.7.0's, which the tests keep):
    /// their texts copied into one list of lines, their paths into one list of segments.
    init(size: CGSize, font: DiagramFont, states: [StateDiagramLayoutState], transitions: [StateDiagramLayoutTransition], notes: [StateDiagramLayoutNote],
         title: DiagramTextBlock?, composites: [FlowchartLayoutCluster] = [], regionDividers: [DiagramPath] = []) {
        var lines = DiagramMeasuredLines()
        var segments: [DiagramPathSegment] = []
        func measured(_ block: DiagramTextBlock) -> DiagramMeasuredText {
            DiagramFlatTextMeasuring.copied(block, into: &lines).centered(at: block.center)
        }
        func run(_ path: DiagramPath) -> DiagramSegmentRun {
            let first = segments.count
            segments += path.segments
            return DiagramSegmentRun(start: path.start, firstSegment: Int32(first), segmentCount: Int32(path.segments.count))
        }
        let placedStates = states.map { state in
            StateDiagramPlacedState(kind: state.kind, frame: state.frame, name: state.name.map(measured), details: state.details.map(measured))
        }
        let placedTransitions = transitions.map { transition in
            StateDiagramPlacedTransition(line: run(transition.path), arrow: transition.arrow, text: transition.text.map(measured))
        }
        let placedNotes = notes.map { note in StateDiagramPlacedNote(frame: note.frame, text: measured(note.text), connector: run(note.connector)) }
        let placedTitle = title.map(measured)
        self.init(size: size, font: font, lines: lines, source: MermaidSourceText(bytes: []), segments: segments, placedStates: placedStates,
                  placedTransitions: placedTransitions, placedNotes: placedNotes, placedTitle: placedTitle, composites: composites,
                  regionDividers: regionDividers)
    }

    /// The same layout with other lines between regions.
    func replacingRegionDividers(with dividers: [DiagramPath]) -> StateDiagramLayout {
        StateDiagramLayout(size: size, font: font, lines: lines, source: source, segments: segments, placedStates: placedStates,
                           placedTransitions: placedTransitions, placedNotes: placedNotes, placedTitle: placedTitle, composites: composites,
                           regionDividers: dividers)
    }

    /// What a screen reader hears of it: the composites' titles, then the drawn states' names, each line joined by a space.
    func spokenNames() -> [String] {
        let compositeNames = composites.compactMap { composite in composite.title?.lines.joined(separator: " ") }
        let stateNames = source.withBytes { source in
            placedStates.compactMap { state in
                state.name.map { name in name.lineIndices.map { line in lines.text(ofLine: line, source: source) }.joined(separator: " ") }
            }
        }
        return compositeNames + stateNames
    }
}

extension StateDiagramLayout: Equatable {
    public static func == (left: StateDiagramLayout, right: StateDiagramLayout) -> Bool {
        left.size == right.size && left.font == right.font && left.states == right.states && left.transitions == right.transitions
            && left.notes == right.notes && left.title == right.title && left.composites == right.composites && left.regionDividers == right.regionDividers
    }
}

/// A state as the layout places it: its frame, and its texts measured, placed.
struct StateDiagramPlacedState: Sendable {
    let kind: StateDiagramStateKind
    let frame: CGRect
    /// The name, in the top of a box; nil for a start, an end, a choice, a fork or a join.
    var name: DiagramMeasuredText?
    /// The descriptions after the first, under a line below the name; nil when there are none.
    var details: DiagramMeasuredText?

    func translated(by offset: CGVector) -> StateDiagramPlacedState {
        StateDiagramPlacedState(kind: kind, frame: frame.offsetBy(dx: offset.dx, dy: offset.dy), name: name?.translated(by: offset),
                                details: details?.translated(by: offset))
    }
}

/// A transition as the layout places it: its line, a run of the layout's segments that stops where the arrow begins,
/// the arrow, and its text, drawn on a patch of the background.
struct StateDiagramPlacedTransition: Sendable {
    var line: DiagramSegmentRun
    var arrow: DiagramEdgeMark
    var text: DiagramMeasuredText?

    mutating func translate(by offset: CGVector) {
        line.start = line.start.translated(by: offset)
        arrow = arrow.translated(by: offset)
        text = text?.translated(by: offset)
    }
}

/// A note as the layout places it: its sheet, its text, and the dashed line from its state, a run of the segments.
struct StateDiagramPlacedNote: Sendable {
    var frame: CGRect
    var text: DiagramMeasuredText
    var connector: DiagramSegmentRun

    mutating func translate(by offset: CGVector) {
        frame = frame.offsetBy(dx: offset.dx, dy: offset.dy)
        text = text.translated(by: offset)
        connector.start = connector.start.translated(by: offset)
    }
}

public struct StateDiagramLayoutState: Equatable, Sendable {
    public let kind: StateDiagramStateKind
    /// The shape's bounding box.
    public let frame: CGRect
    /// The name, in the top of a box; nil for a start, an end, a choice, a fork or a join.
    public let name: DiagramTextBlock?
    /// The descriptions after the first, under a line below the name, in smaller type; nil when there are none.
    public let details: DiagramTextBlock?
}

public struct StateDiagramLayoutTransition: Equatable, Sendable {
    /// The line, which stops where the arrow begins.
    public internal(set) var path: DiagramPath
    public internal(set) var arrow: DiagramEdgeMark
    /// The transition's text, drawn on a patch of the background, or nil.
    public internal(set) var text: DiagramTextBlock?
}

public struct StateDiagramLayoutNote: Equatable, Sendable {
    /// The note's sheet, whose top right corner is folded.
    public internal(set) var frame: CGRect
    public internal(set) var text: DiagramTextBlock
    /// The dashed line from the note's state to the note.
    public internal(set) var connector: DiagramPath
}

extension StateDiagramLayoutState {
    func translated(by offset: CGVector) -> StateDiagramLayoutState {
        StateDiagramLayoutState(kind: kind, frame: frame.offsetBy(dx: offset.dx, dy: offset.dy), name: name?.translated(by: offset),
                                details: details?.translated(by: offset))
    }
}

extension StateDiagramLayoutTransition {
    func translated(by offset: CGVector) -> StateDiagramLayoutTransition {
        StateDiagramLayoutTransition(path: path.translated(by: offset), arrow: arrow.translated(by: offset), text: text?.translated(by: offset))
    }
}

extension StateDiagramLayoutNote {
    func translated(by offset: CGVector) -> StateDiagramLayoutNote {
        StateDiagramLayoutNote(frame: frame.offsetBy(dx: offset.dx, dy: offset.dy), text: text.translated(by: offset),
                               connector: connector.translated(by: offset))
    }
}
