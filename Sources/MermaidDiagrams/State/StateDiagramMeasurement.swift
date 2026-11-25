/**
 * File: StateDiagramMeasurement.swift
 * -----------------------------------
 * Layer: Core
 * Description: A state diagram's text measured and its shapes sized, Pele's, with the spans its transitions spread along.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.3
 * Date: 24/11/2026
 */

import CoreGraphics

/// A state diagram's text measured and its shapes sized, Pele's: what the layout needs before it places anything.
struct StateDiagramMeasurement {
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

    /// Each state's name, or nil for a start, an end, a choice, a fork or a join.
    let names: [DiagramTextBlock?]
    /// Each box's descriptions after the first, or nil.
    let details: [DiagramTextBlock?]
    /// Each state's drawn size on the page.
    let stateSizes: [CGSize]
    /// Each transition's text, or nil.
    let transitionTexts: [DiagramTextBlock?]
    let noteTexts: [DiagramTextBlock]
    let noteSizes: [CGSize]
    /// For each state, the indexes of its transitions to itself, in their written order.
    let selfLoopTransitionIndices: [[Int]]

    /// How much of each side of a state's box its transitions share out, clear of its corners (Pele's `span`: the box's
    /// side across the flow less 24); 0 for the marks, which keep their transitions at the middle.
    func sideSpan(of state: Int, in diagram: StateDiagram, flowIsVertical: Bool) -> CGFloat {
        guard diagram.states[state].kind == .state else { return 0 }
        return max(0, (flowIsVertical ? stateSizes[state].width : stateSizes[state].height) - Self.spanCornerClearance)
    }

    /// What `sideSpan` keeps clear of a box's corners, on both sides together.
    static let spanCornerClearance: CGFloat = 24

    init<Measurer: DiagramTextMeasuring>(diagram: StateDiagram, nameText: Measurer, smallText: Measurer, flowIsVertical: Bool,
                                         wrappingWidth: CGFloat, noteWrappingWidth: CGFloat) {
        let transitionCounts = Self.busierSideTransitionCounts(diagram)
        let stateCount = diagram.states.count
        var names: [DiagramTextBlock?] = []
        var details: [DiagramTextBlock?] = []
        var stateSizes: [CGSize] = []
        names.reserveCapacity(stateCount)
        details.reserveCapacity(stateCount)
        stateSizes.reserveCapacity(stateCount)
        for (index, state) in diagram.states.enumerated() {
            switch state.kind {
            case .state:
                let name = DiagramTextBlock(label: state.name, measurer: nameText, maximumWidth: wrappingWidth)
                let detail = state.descriptions.count < 2 ? nil
                    : Self.details(of: state, measurer: smallText, wrappingWidth: wrappingWidth).flatMap { block in block.lineCount == 0 ? nil : block }
                names.append(name)
                details.append(detail)
                stateSizes.append(Self.boxSize(name: name, details: detail))
            case .start, .end, .choice, .fork, .join:
                names.append(nil)
                details.append(nil)
                stateSizes.append(Self.markSize(of: state.kind, transitionCount: transitionCounts[index], flowIsVertical: flowIsVertical))
            }
        }
        self.names = names
        self.details = details
        self.stateSizes = stateSizes
        (transitionTexts, selfLoopTransitionIndices) = Self.transitionTexts(of: diagram, measurer: smallText, wrappingWidth: wrappingWidth)
        (noteTexts, noteSizes) = Self.notes(of: diagram, measurer: smallText, wrappingWidth: noteWrappingWidth)
    }

    /// Each transition's text, or nil, and each state's loops.
    private static func transitionTexts<Measurer: DiagramTextMeasuring>(of diagram: StateDiagram, measurer: Measurer, wrappingWidth: CGFloat)
        -> (texts: [DiagramTextBlock?], selfLoopTransitionIndices: [[Int]]) {
        var transitionTexts: [DiagramTextBlock?] = []
        transitionTexts.reserveCapacity(diagram.transitions.count)
        var selfLoopTransitionIndices = [[Int]](repeating: [], count: diagram.states.count)
        for (transitionIndex, transition) in diagram.transitions.enumerated() {
            transitionTexts.append(transition.label.map { label in DiagramTextBlock(label: label, measurer: measurer, maximumWidth: wrappingWidth) }
                .flatMap { text in text.lineCount == 0 ? nil : text })
            if transition.sourceIndex == transition.targetIndex { selfLoopTransitionIndices[transition.sourceIndex].append(transitionIndex) }
        }
        return (transitionTexts, selfLoopTransitionIndices)
    }

    /// Each note's text and its sheet's size.
    private static func notes<Measurer: DiagramTextMeasuring>(of diagram: StateDiagram, measurer: Measurer,
                                                              wrappingWidth: CGFloat) -> (texts: [DiagramTextBlock], sizes: [CGSize]) {
        var noteTexts: [DiagramTextBlock] = []
        var noteSizes: [CGSize] = []
        noteTexts.reserveCapacity(diagram.notes.count)
        noteSizes.reserveCapacity(diagram.notes.count)
        for note in diagram.notes {
            let text = DiagramTextBlock(label: note.text, measurer: measurer, maximumWidth: wrappingWidth)
            noteTexts.append(text)
            noteSizes.append(CGSize(width: text.size.width + notePadding.width, height: text.size.height + notePadding.height))
        }
        return (noteTexts, noteSizes)
    }

    /// A box's descriptions after the first, in one block, or nil when they hold no line.
    private static func details<Measurer: DiagramTextMeasuring>(of state: StateDiagramState, measurer: Measurer,
                                                                wrappingWidth: CGFloat) -> DiagramTextBlock? {
        let detailLines = state.descriptions.dropFirst().flatMap(\.lines)
        return detailLines.isEmpty ? nil : DiagramTextBlock(label: DiagramLabel(lines: detailLines), measurer: measurer, maximumWidth: wrappingWidth)
    }

    /// A box around its name, and its other descriptions under a line.
    private static func boxSize(name: DiagramTextBlock, details: DiagramTextBlock?) -> CGSize {
        let textWidth = max(name.size.width, details?.size.width ?? 0)
        let detailsHeight = details.map { block in detailsGap + block.size.height } ?? 0
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
    private static func busierSideTransitionCounts(_ diagram: StateDiagram) -> [Int] {
        let stateCount = diagram.states.count
        var counts = [Int](repeating: 0, count: 2 * stateCount)
        for transition in diagram.transitions {
            counts[transition.sourceIndex] += 1
            counts[stateCount + transition.targetIndex] += 1
        }
        for state in 0..<stateCount { counts[state] = max(counts[state], counts[stateCount + state]) }
        return counts
    }
}
