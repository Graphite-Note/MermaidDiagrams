/**
 * File: ReferenceStateDiagramMeasurement.swift
 * --------------------------------------------
 * Layer: Tests
 * Description: The 0.7.0 StateDiagramMeasurement kept as the reference the 0.8.0 layout is checked against:
 *              a state diagram's text measured and its shapes sized, Pele's, with the spans its transitions spread along.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// A state diagram's text measured and its shapes sized, Pele's: what the layout needs before it places anything.
struct ReferenceStateDiagramMeasurement {
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
        var names: [DiagramTextBlock?] = []
        var details: [DiagramTextBlock?] = []
        var stateSizes: [CGSize] = []
        names.reserveCapacity(diagram.states.count)
        for (index, state) in diagram.states.enumerated() {
            switch state.kind {
            case .state:
                let name = DiagramTextBlock(label: state.name, measurer: nameText, maximumWidth: wrappingWidth)
                let detailLines = state.descriptions.dropFirst().flatMap(\.lines)
                let detail = detailLines.isEmpty ? nil
                    : DiagramTextBlock(label: DiagramLabel(lines: detailLines), measurer: smallText, maximumWidth: wrappingWidth)
                names.append(name)
                details.append(detail.flatMap { block in block.lineCount == 0 ? nil : block })
                stateSizes.append(Self.boxSize(name: name, details: details[index]))
            case .start, .end, .choice, .fork, .join:
                names.append(nil)
                details.append(nil)
                stateSizes.append(Self.markSize(of: state.kind, transitionCount: transitionCounts[index], flowIsVertical: flowIsVertical))
            }
        }
        self.names = names
        self.details = details
        self.stateSizes = stateSizes
        transitionTexts = diagram.transitions.map { transition in
            transition.label.map { label in DiagramTextBlock(label: label, measurer: smallText, maximumWidth: wrappingWidth) }
                .flatMap { text in text.lineCount == 0 ? nil : text }
        }
        noteTexts = diagram.notes.map { note in DiagramTextBlock(label: note.text, measurer: smallText, maximumWidth: noteWrappingWidth) }
        noteSizes = noteTexts.map { text in
            CGSize(width: text.size.width + Self.notePadding.width, height: text.size.height + Self.notePadding.height)
        }
        var selfLoopTransitionIndices = [[Int]](repeating: [], count: diagram.states.count)
        for (transitionIndex, transition) in diagram.transitions.enumerated() where transition.sourceIndex == transition.targetIndex {
            selfLoopTransitionIndices[transition.sourceIndex].append(transitionIndex)
        }
        self.selfLoopTransitionIndices = selfLoopTransitionIndices
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
        var leaving = [Int](repeating: 0, count: diagram.states.count)
        var arriving = [Int](repeating: 0, count: diagram.states.count)
        for transition in diagram.transitions {
            leaving[transition.sourceIndex] += 1
            arriving[transition.targetIndex] += 1
        }
        return zip(leaving, arriving).map { leavingCount, arrivingCount in max(leavingCount, arrivingCount) }
    }
}
