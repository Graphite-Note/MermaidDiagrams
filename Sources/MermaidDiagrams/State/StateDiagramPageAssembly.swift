/**
 * File: StateDiagramPageAssembly.swift
 * ------------------------------------
 * Layer: Core
 * Description: Puts a placed state diagram on the page: states, transitions, loops, notes and composite boxes, read from
 *              the layout's spans, each list of the layout made once and moved into the padding where it stands.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.5
 * Date: 24/11/2026
 */

import CoreGraphics

/// Puts a placed state diagram on the page: states at their centers, transitions from one state's side to the other's
/// through their passing points, loops beside their states, notes beside theirs with their dashed lines, then
/// everything moved inside the padding below the title.
struct StateDiagramPageAssembly {
    let diagram: StateDiagram
    let measured: StateDiagramMeasurement
    let surroundings: StateDiagramSurroundings
    let axes: FlowchartFlowAxes
    private(set) var stateCenters: [CGPoint] = []
    /// By transition index; nil until the transition is placed.
    var transitions: [StateDiagramLayoutTransition?]
    /// A diagram with composite states: which states are boxes, the boxes drawn, and the dashed lines between regions.
    var clustered: StateDiagramClusterGraph?
    var composites: [FlowchartLayoutCluster] = []
    var regionDividers: [DiagramPath] = []
    /// The composites' boxes, by composite index, for a diagram laid out in boxes.
    var compositeFrames: [CGRect] = []
    /// The centers of the notes beside composites, by note index; empty for a diagram without composites.
    var compositeNoteCenters: [CGPoint?] = []

    init(diagram: StateDiagram, measured: StateDiagramMeasurement, surroundings: StateDiagramSurroundings, axes: FlowchartFlowAxes) {
        self.diagram = diagram
        self.measured = measured
        self.surroundings = surroundings
        self.axes = axes
        transitions = Array(repeating: nil, count: diagram.transitions.count)
    }

    /// The states of a diagram laid out in ranks at their nodes' centers; `positionOfState[state]` is the state's node.
    mutating func placeStates(nodes: ScratchSpan<LayeredFlatNode>, positionOfState: ScratchSpan<Int>) {
        stateCenters.reserveCapacity(positionOfState.count)
        for state in 0..<positionOfState.count {
            let node = nodes[positionOfState[state]]
            stateCenters.append(axes.pagePoint(CGPoint(x: node.x, y: node.y)))
        }
    }

    /// The states at the given centers on the page, by state index.
    mutating func placeStates(centers: [CGPoint]) {
        stateCenters = centers
    }

    /// The transitions between two different states, along their routes. `layeredTransitionIndices[i]` is the transition
    /// of the flat layout's `i`-th edge. Each end is where Pele's layout spread and settled it on its state's place,
    /// moved onto the state's own box (`StateDiagramRouteEnds`), as Pele's state diagram draws it.
    mutating func placeTransitions(layeredTransitionIndices: ScratchSpan<Int>, edges: ScratchSpan<LayeredSpanEdge>, points: ScratchSpan<CGPoint>) {
        for layeredIndex in 0..<layeredTransitionIndices.count {
            let edge = edges[layeredIndex]
            guard edge.pointStart >= 0, edge.pointCount >= 2 else { continue }
            let path = points.part(edge.pointStart..<(edge.pointStart + edge.pointCount))
            let transitionIndex = layeredTransitionIndices[layeredIndex]
            let transition = diagram.transitions[transitionIndex]
            let last = path.count - 1
            let sourcePoint = attachedEnd(axes.pagePoint(path[0]), next: axes.pagePoint(path[1]), state: transition.sourceIndex)
            let targetPoint = attachedEnd(axes.pagePoint(path[last]), next: axes.pagePoint(path[last - 1]), state: transition.targetIndex)
            var routePoints: [CGPoint] = []
            routePoints.reserveCapacity(path.count)
            routePoints.append(sourcePoint)
            for index in 1..<last { routePoints.append(axes.pagePoint(path[index])) }
            routePoints.append(targetPoint)
            let drawn = DiagramRouteDrawing.path(through: routePoints, flowIsVertical: axes.flowIsVertical, startTrim: 0,
                                                 endTrim: DiagramEdgeMark.lineTrim(for: .arrow))
            let textCenter = edge.labelWidth > 0 ? axes.pagePoint(edge.labelCenter)
                : CGPoint(x: (sourcePoint.x + targetPoint.x) / 2, y: (sourcePoint.y + targetPoint.y) / 2)
            transitions[transitionIndex] = StateDiagramLayoutTransition(
                path: drawn.path, arrow: DiagramEdgeMark(arrowhead: .arrow, tip: targetPoint, direction: drawn.endDirection),
                text: Self.centered(measured.transitionTexts[transitionIndex], at: textCenter))
        }
    }

    /// An end of a transition of a diagram laid out without boxes, from its state's place onto its state.
    private func attachedEnd(_ end: CGPoint, next: CGPoint, state: Int) -> CGPoint {
        let place = surroundings.placeSizes[state]
        let layoutSize = axes.flowIsVertical ? CGSize(width: place.across, height: place.along) : CGSize(width: place.along, height: place.across)
        let kind = diagram.states[state].kind
        return StateDiagramRouteEnds.attached(end, next: next, center: stateCenters[state], layoutSize: layoutSize, drawnSize: measured.stateSizes[state],
                                              isBar: kind == .fork || kind == .join)
    }

    /// The loops of every state that has transitions to itself.
    mutating func placeSelfLoops() {
        for (state, loopTransitionIndices) in measured.selfLoopTransitionIndices.enumerated() where !loopTransitionIndices.isEmpty {
            // A composite's loops hang off its box, beside it across the flow of the box around it.
            let composite = clustered?.compositeOfState[state]
            let size = composite.map { compositeFrames[$0].size } ?? measured.stateSizes[state]
            let flowIsVertical = composite.map { clustered?.compositeSurroundings.containerRunsVertically[$0] ?? true } ?? axes.flowIsVertical
            let loops = StateDiagramSelfLoops.loops(center: stateCenters[state], size: size, flowIsVertical: flowIsVertical,
                                                    textSizes: loopTransitionIndices.map { transitionIndex in measured.transitionTexts[transitionIndex]?.size })
            for (transitionIndex, loop) in zip(loopTransitionIndices, loops) {
                transitions[transitionIndex] = StateDiagramLayoutTransition(
                    path: loop.path, arrow: loop.arrow,
                    text: loop.textCenter.flatMap { center in Self.centered(measured.transitionTexts[transitionIndex], at: center) })
            }
        }
    }

    static func centered(_ text: DiagramTextBlock?, at center: CGPoint) -> DiagramTextBlock? {
        guard var text else { return nil }
        text.center = center
        return text
    }

    /// The finished layout: everything moved so that the drawing starts `padding` from the top left, below the
    /// title, and centered under the title when the title is wider. Each list is made once and moved where it stands.
    func finished(font: DiagramFont, title: DiagramTextBlock?, padding: CGFloat, titleGap: CGFloat) -> StateDiagramLayout {
        // A composite state is its box, not a state.
        var states: [StateDiagramLayoutState] = []
        states.reserveCapacity(diagram.states.count)
        for index in diagram.states.indices where clustered?.compositeOfState[index] == nil { states.append(placedState(at: index)) }
        var placedTransitions: [StateDiagramLayoutTransition] = []
        placedTransitions.reserveCapacity(transitions.count)
        for transition in transitions { if let transition { placedTransitions.append(transition) } }
        var placedNotes = notes()
        var bounds = StateDiagramLayoutBounds.union(states: states, transitions: placedTransitions, notes: placedNotes)
        for composite in composites { bounds = bounds.union(composite.frame) }
        let titleSize = title?.size ?? .zero
        let innerWidth = max(bounds.width, titleSize.width)
        let titleHeight = title == nil ? 0 : titleSize.height + titleGap
        let offset = CGVector(dx: padding + (innerWidth - bounds.width) / 2 - bounds.minX, dy: padding + titleHeight - bounds.minY)
        let size = CGSize(width: (innerWidth + 2 * padding).rounded(.up), height: (bounds.height + titleHeight + 2 * padding).rounded(.up))
        var placedTitle = title
        placedTitle?.center = CGPoint(x: size.width / 2, y: padding + titleSize.height / 2)
        for index in states.indices { states[index] = states[index].translated(by: offset) }
        for index in placedTransitions.indices { placedTransitions[index].translate(by: offset) }
        for index in placedNotes.indices { placedNotes[index].translate(by: offset) }
        var placedComposites = composites
        for index in placedComposites.indices { placedComposites[index] = placedComposites[index].translated(by: offset) }
        var placedDividers = regionDividers
        for index in placedDividers.indices { placedDividers[index].translate(by: offset) }
        return StateDiagramLayout(size: size, font: font, states: states, transitions: placedTransitions, notes: placedNotes, title: placedTitle,
                                  composites: placedComposites, regionDividers: placedDividers)
    }

    /// A state's frame, its name in the top of a box and its other descriptions below the line under the name.
    private func placedState(at index: Int) -> StateDiagramLayoutState {
        let center = stateCenters[index]
        let size = measured.stateSizes[index]
        let frame = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
        let name = measured.names[index].map { block in
            var placed = block
            placed.center = CGPoint(x: center.x, y: frame.minY + StateDiagramMeasurement.verticalPadding + block.size.height / 2)
            return placed
        }
        let details = measured.details[index].map { block in
            var placed = block
            let top = (name?.frame.maxY ?? frame.minY) + StateDiagramMeasurement.detailsGap
            placed.center = CGPoint(x: center.x, y: top + block.size.height / 2)
            return placed
        }
        return StateDiagramLayoutState(kind: diagram.states[index].kind, frame: frame, name: name, details: details)
    }
}
