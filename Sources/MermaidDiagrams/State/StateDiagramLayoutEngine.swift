/**
 * File: StateDiagramLayoutEngine.swift
 * ------------------------------------
 * Layer: Core
 * Description: Lays a state diagram out in Pele's style, its composite states as nested boxes, and from the top down
 *              for a narrow container as Pele turns it.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.7
 * Date: 26/11/2026
 */

import CoreGraphics

/// Lays a state diagram out in Pele's style: boxes sized around their names, wrapped at 200 points, and the small
/// marks of starts, ends, choices, forks and joins; the states in ranks along the diagram's direction, 40 points apart
/// in a rank and 44 points between ranks, starts first and the others in the order transitions first name them;
/// transitions as S curves that spread along the sides of boxes; transitions to a state itself as loops beside it;
/// notes beside their states across the flow; and the title above.
public enum StateDiagramLayoutEngine {
    static let spacing = LayeredSpacing(nodeSeparation: 40, edgeSeparation: 16, rankSeparation: 44, borderSeparation: 20,
                                        routing: LayeredRouting(headRoom: DiagramEdgeMark.arrowLength - 1))
    /// The gaps of a diagram with composite states: a border point of a box is 20 points from the rank next to it, as in
    /// a flowchart's boxes.
    static let clusterSpacing = spacing
    /// Around the whole diagram.
    static let padding: CGFloat = 8
    /// The widest a line of a state's or a transition's text is before it wraps.
    static let wrappingWidth: CGFloat = 200
    /// The widest a line of a note is before it wraps.
    static let noteWrappingWidth: CGFloat = 320
    /// The room a transition's text takes beyond its lines, for the patch drawn behind it.
    static let transitionTextRoom = CGSize(width: 12, height: 4)
    /// Between the title and the diagram.
    static let titleGap: CGFloat = 12

    public static func layout(_ diagram: StateDiagram, typography: DiagramTypography,
                              limits: MermaidDiagramLimits) throws(StateDiagramLayoutError) -> StateDiagramLayout {
        try layout(diagram, nameText: typography.nodeText, smallText: typography.edgeText, font: typography.font, limits: limits)
    }

    /// The diagram for a container `availableWidth` wide (nil for none), as Pele fits it (state/render.ts): one whose own
    /// direction runs across is laid out from the top down, its composites keeping their directions, when it does not
    /// fit a container under 640 points and that is narrower (`turnToFit`).
    public static func layout(_ diagram: StateDiagram, typography: DiagramTypography, limits: MermaidDiagramLimits,
                              availableWidth: CGFloat?) throws(StateDiagramLayoutError) -> StateDiagramLayout {
        guard let turned = diagram.turnedTopToBottom else { return try layout(diagram, typography: typography, limits: limits) }
        return try DiagramWidthFitting.turnToFit(availableWidth: availableWidth, width: { (layout: StateDiagramLayout) in layout.size.width }) { isDown throws(StateDiagramLayoutError) in
            try layout(isDown ? turned : diagram, typography: typography, limits: limits)
        }
    }

    static func layout<Measurer: DiagramTextMeasuring>(_ diagram: StateDiagram, nameText: Measurer, smallText: Measurer, font: DiagramFont,
                                                       limits: MermaidDiagramLimits) throws(StateDiagramLayoutError) -> StateDiagramLayout {
        let flowAxes = FlowchartFlowAxes(direction: diagram.direction, alongExtent: 0)
        var measured = StateDiagramMeasurement(diagram: diagram, nameText: nameText, smallText: smallText, flowIsVertical: flowAxes.flowIsVertical,
                                               wrappingWidth: wrappingWidth, noteWrappingWidth: noteWrappingWidth)
        let title = diagram.title.map { title in
            DiagramFlatTextMeasuring.measure(DiagramLabel(title), measurer: DiagramFlatMeasurer(nameText), maximumWidth: .greatestFiniteMagnitude,
                                             into: &measured.lines)
        }
        let surroundings = StateDiagramSurroundings(diagram: diagram, measured: measured, axes: flowAxes)
        let laidOut = DiagramScratchArena.withCurrentThread { arena -> Result<StateDiagramLayout?, StateDiagramLayoutError> in
            guard !diagram.composites.isEmpty else {
                return .success(StateDiagramRankedLayout.layout(diagram, measured: measured, surroundings: surroundings, title: title, font: font,
                                                                maximumPointCount: limits.maximumLayoutPointCount, arena: arena))
            }
            // Each composite a box laid out on its own and placed in the box around it, its concurrent regions boxes side by
            // side inside it; what is not laid out fails with `compositeStatesNotLaidOut`.
            let clustered: StateDiagramClusterGraph
            do throws(StateDiagramLayoutError) {
                clustered = try StateDiagramClusterGraph(diagram: diagram, measured: measured, surroundings: surroundings,
                                                         flowIsVertical: flowAxes.flowIsVertical, titleText: nameText, arena: arena)
            } catch {
                return .failure(error)
            }
            return .success(StateDiagramBoxedLayout.layout(diagram, clustered: clustered, measured: measured, surroundings: surroundings, title: title,
                                                           font: font, maximumPointCount: limits.maximumLayoutPointCount, arena: arena))
        }
        guard let layout = try laidOut.get() else { throw .tooManyLayoutPoints(limit: limits.maximumLayoutPointCount) }
        return layout
    }

    /// The states in the order the layout takes them, Pele's: starts first, then the others in the order transitions
    /// first name them, then those no transition names, each group in the diagram's order. A state declared before
    /// the transitions does not become the top of the flow.
    static func flowOrder(of diagram: StateDiagram) -> [Int] {
        var firstAppearance = [Int](repeating: .max, count: diagram.stateCount)
        var appearanceCount = 0
        for transition in diagram.model.transitions {
            for state in [transition.sourceIndex, transition.targetIndex] where firstAppearance[state] == .max {
                firstAppearance[state] = appearanceCount
                appearanceCount += 1
            }
        }
        let states = diagram.model.states
        return states.indices.sorted { first, second in
            (states[first].kind.isStart ? 0 : 1, firstAppearance[first], first) < (states[second].kind.isStart ? 0 : 1, firstAppearance[second], second)
        }
    }
}

extension StateDiagramStateKind {
    /// Whether the layout takes the state before the others in its order.
    var isStart: Bool {
        switch self {
        case .start: true
        case .state, .end, .choice, .fork, .join: false
        }
    }
}
