/**
 * File: StateDiagramMeasurement.swift
 * -----------------------------------
 * Layer: Core
 * Description: A state diagram's text measured from its records into one list of lines and its shapes sized, Pele's,
 *              with the spans its transitions spread along.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.6
 * Date: 26/11/2026
 */

import CoreGraphics

/// A state's texts measured and its shape sized.
struct StateDiagramMeasuredState {
    /// The name, or nil for a start, an end, a choice, a fork or a join.
    let name: DiagramMeasuredText?
    /// A box's descriptions after the first, or nil.
    let details: DiagramMeasuredText?
    /// The drawn size on the page.
    let size: CGSize
}

/// A state diagram's text measured and its shapes sized, Pele's: what the layout needs before it places anything.
final class StateDiagramMeasurement {
    static let horizontalPadding: CGFloat = 16
    static let verticalPadding: CGFloat = 10
    static let minimumBoxWidth: CGFloat = 56
    /// From the bottom of a box's name to the top of its other descriptions; the line between them is 6 points below
    /// the name.
    static let detailsGap: CGFloat = 14
    static let startDiameter: CGFloat = 14
    static let endDiameter: CGFloat = 18
    static let choiceSize: CGFloat = 30
    static let barThickness: CGFloat = 8
    /// A fork or a join is this long for each transition on its busier side, plus `barExtraLength`, within
    /// `barLengths`.
    static let barLengthPerTransition: CGFloat = 40
    static let barExtraLength: CGFloat = 16
    static let barLengths: ClosedRange<CGFloat> = 72...320
    /// The room around a note's text.
    static let notePadding = CGSize(width: 24, height: 16)

    /// The lines of every text measured here, which the measured texts index.
    var lines = DiagramMeasuredLines()
    /// Each state's texts and drawn size on the page.
    let states: [StateDiagramMeasuredState]
    /// Each transition's text, or nil.
    let transitionTexts: [DiagramMeasuredText?]
    let noteTexts: [DiagramMeasuredText]
    let noteSizes: [CGSize]
    /// For each state, the indexes of its transitions to itself, in their written order.
    let selfLoopTransitionIndices: [[Int]]

    /// How much of each side of a state's box its transitions share out, clear of its corners (Pele's `span`: the box's
    /// side across the flow less 24); 0 for the marks, which keep their transitions at the middle.
    func sideSpan(of state: Int, in diagram: StateDiagram, flowIsVertical: Bool) -> CGFloat {
        guard diagram.model.states[state].kind == .state else { return 0 }
        return max(0, (flowIsVertical ? states[state].size.width : states[state].size.height) - Self.spanCornerClearance)
    }

    /// What `sideSpan` keeps clear of a box's corners, on both sides together.
    static let spanCornerClearance: CGFloat = 24

    init<Measurer: DiagramTextMeasuring>(diagram: StateDiagram, nameText: Measurer, smallText: Measurer, flowIsVertical: Bool,
                                         wrappingWidth: CGFloat, noteWrappingWidth: CGFloat) {
        let model = diagram.model
        let transitionCounts = Self.busierSideTransitionCounts(model)
        var lines = DiagramMeasuredLines()
        lines.reserveCapacity(lines: model.states.count + model.transitions.count + model.notes.count + 1, derivedBytes: 0)
        var states: [StateDiagramMeasuredState] = []
        states.reserveCapacity(model.states.count)
        let measured = model.text.withBytes { source in
            let nameMeasuring = StateDiagramTextMeasuring<Measurer>(source: source, measurer: DiagramFlatMeasurer(nameText))
            let smallMeasuring = StateDiagramTextMeasuring<Measurer>(source: source, measurer: DiagramFlatMeasurer(smallText))
            for (index, state) in model.states.enumerated() {
                switch state.kind {
                case .state:
                    let name = nameMeasuring.measureName(of: index, in: model, maximumWidth: wrappingWidth, into: &lines)
                    let detail = state.descriptionCount < 2 ? nil : Self.details(of: index, in: model, measuring: smallMeasuring, wrappingWidth: wrappingWidth,
                                                                                into: &lines)
                    states.append(StateDiagramMeasuredState(name: name, details: detail, size: Self.boxSize(name: name, details: detail)))
                case .start, .end, .choice, .fork, .join:
                    let size = Self.markSize(of: state.kind, transitionCount: transitionCounts.isEmpty ? 0 : transitionCounts[index], flowIsVertical: flowIsVertical)
                    states.append(StateDiagramMeasuredState(name: nil, details: nil, size: size))
                }
            }
            let transitions = Self.transitionTexts(of: model, measuring: smallMeasuring, wrappingWidth: wrappingWidth, into: &lines)
            let notes = Self.notes(of: model, measuring: smallMeasuring, wrappingWidth: noteWrappingWidth, into: &lines)
            return (transitions, notes)
        }
        self.lines = lines
        self.states = states
        (transitionTexts, selfLoopTransitionIndices) = measured.0
        (noteTexts, noteSizes) = measured.1
    }

    /// Each transition's text, or nil, and each state's loops.
    private static func transitionTexts<Measurer>(of model: StateDiagramModel, measuring: StateDiagramTextMeasuring<Measurer>, wrappingWidth: CGFloat,
                                                  into lines: inout DiagramMeasuredLines)
        -> (texts: [DiagramMeasuredText?], selfLoopTransitionIndices: [[Int]]) {
        var transitionTexts: [DiagramMeasuredText?] = []
        transitionTexts.reserveCapacity(model.transitions.count)
        var selfLoopTransitionIndices = [[Int]](repeating: [], count: model.states.count)
        for (transitionIndex, transition) in model.transitions.enumerated() {
            if transition.label.isNone {
                transitionTexts.append(nil)
            } else {
                let text = measuring.measure(transition.label, in: model, maximumWidth: wrappingWidth, into: &lines)
                transitionTexts.append(text.lineCount == 0 ? nil : text)
            }
            if transition.source == transition.target { selfLoopTransitionIndices[transition.sourceIndex].append(transitionIndex) }
        }
        return (transitionTexts, selfLoopTransitionIndices)
    }

    /// Each note's text and its sheet's size.
    private static func notes<Measurer>(of model: StateDiagramModel, measuring: StateDiagramTextMeasuring<Measurer>, wrappingWidth: CGFloat,
                                        into lines: inout DiagramMeasuredLines) -> (texts: [DiagramMeasuredText], sizes: [CGSize]) {
        var noteTexts: [DiagramMeasuredText] = []
        var noteSizes: [CGSize] = []
        noteTexts.reserveCapacity(model.notes.count)
        noteSizes.reserveCapacity(model.notes.count)
        for note in model.notes {
            let text = measuring.measure(note.text, in: model, maximumWidth: wrappingWidth, into: &lines)
            noteTexts.append(text)
            noteSizes.append(CGSize(width: text.width + notePadding.width, height: text.height + notePadding.height))
        }
        return (noteTexts, noteSizes)
    }

    /// A box's descriptions after the first, in one text of their lines as decoded (`DiagramLabel(lines:)`), or nil when
    /// they hold no line.
    private static func details<Measurer>(of state: Int, in model: StateDiagramModel, measuring: StateDiagramTextMeasuring<Measurer>,
                                          wrappingWidth: CGFloat, into lines: inout DiagramMeasuredLines) -> DiagramMeasuredText? {
        let detailLines = model.states[state].descriptionIndices.dropFirst().flatMap { index in model.label(model.descriptions[index]).lines }
        guard !detailLines.isEmpty else { return nil }
        let text = DiagramFlatTextMeasuring.measure(DiagramLabel(lines: detailLines), measurer: measuring.measurer, maximumWidth: wrappingWidth, into: &lines)
        return text.lineCount == 0 ? nil : text
    }

    /// A box around its name, and its other descriptions under a line.
    private static func boxSize(name: DiagramMeasuredText, details: DiagramMeasuredText?) -> CGSize {
        let textWidth = max(name.size.width, details?.size.width ?? 0)
        let detailsHeight = details.map { text in detailsGap + text.size.height } ?? 0
        return CGSize(width: max(textWidth + 2 * horizontalPadding, minimumBoxWidth), height: name.size.height + 2 * verticalPadding + detailsHeight)
    }

    /// A start, an end, a choice, or a bar across the flow as long as its busier side needs.
    private static func markSize(of kind: StateDiagramStateKind, transitionCount: Int, flowIsVertical: Bool) -> CGSize {
        switch kind {
        case .start: return CGSize(width: startDiameter, height: startDiameter)
        case .end: return CGSize(width: endDiameter, height: endDiameter)
        case .choice: return CGSize(width: choiceSize, height: choiceSize)
        case .fork, .join:
            let length = min(max(barLengthPerTransition * CGFloat(transitionCount) + barExtraLength, barLengths.lowerBound), barLengths.upperBound)
            return flowIsVertical ? CGSize(width: length, height: barThickness) : CGSize(width: barThickness, height: length)
        case .state: return .zero
        }
    }

    /// For each state, the larger of how many transitions leave it and how many arrive.
    /// Empty for a diagram without forks and joins, the only states whose size follows it.
    private static func busierSideTransitionCounts(_ model: StateDiagramModel) -> [Int] {
        guard model.states.contains(where: { state in state.kind == .fork || state.kind == .join }) else { return [] }
        let stateCount = model.states.count
        var counts = [Int](repeating: 0, count: 2 * stateCount)
        for transition in model.transitions {
            counts[transition.sourceIndex] += 1
            counts[stateCount + transition.targetIndex] += 1
        }
        for state in 0..<stateCount { counts[state] = max(counts[state], counts[stateCount + state]) }
        return counts
    }
}
