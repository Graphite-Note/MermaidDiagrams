/**
 * File: ReferenceStateDiagramPageAssembly.swift
 * ---------------------------------------------
 * Layer: Tests
 * Description: The 0.7.0 StateDiagramPageAssembly kept as the reference the 0.8.0 layout is checked against:
 *              puts a placed state diagram on the page: states, transitions, loops, notes and composite boxes.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// Puts a placed state diagram on the page: states at their centers, transitions from one state's side to the other's
/// through their passing points, loops beside their states, notes beside theirs with their dashed lines, then
/// everything moved inside the padding below the title.
struct ReferenceStateDiagramPageAssembly {
    let diagram: StateDiagram
    let measured: ReferenceStateDiagramMeasurement
    let surroundings: ReferenceStateDiagramSurroundings
    let axes: FlowchartFlowAxes
    private(set) var stateCenters: [CGPoint] = []
    /// By transition index; nil until the transition is placed.
    private var transitions: [StateDiagramLayoutTransition?]
    /// A diagram with composite states: which states are boxes, the boxes drawn, and the dashed lines between regions.
    private var clustered: ReferenceStateDiagramClusterGraph?
    private var composites: [FlowchartLayoutCluster] = []
    private var regionDividers: [DiagramPath] = []
    /// The composites' boxes, by composite index, for a diagram laid out in boxes.
    private var compositeFrames: [CGRect] = []
    /// The centers of the notes beside composites, by note index.
    private var compositeNoteCenters: [Int: CGPoint] = [:]

    init(diagram: StateDiagram, measured: ReferenceStateDiagramMeasurement, surroundings: ReferenceStateDiagramSurroundings, axes: FlowchartFlowAxes) {
        self.diagram = diagram
        self.measured = measured
        self.surroundings = surroundings
        self.axes = axes
        transitions = Array(repeating: nil, count: diagram.transitions.count)
    }

    mutating func placeStates(flowCenters: [CGPoint]) {
        stateCenters = flowCenters.map(axes.pagePoint)
    }

    /// The transitions between two different states, along their routes. `layeredTransitionIndices[i]` is the
    /// transition of the placement's `i`-th route. Each end is where Pele's layout spread and settled it on its state's
    /// place, moved onto the state's own box (`ReferenceStateDiagramRouteEnds`), as Pele's state diagram draws it.
    mutating func placeTransitions(layeredTransitionIndices: [Int], placement: LayeredPlacement) {
        for (layeredIndex, transitionIndex) in layeredTransitionIndices.enumerated() {
            let route = placement.edgeRoutes[layeredIndex]
            let path = placement.edgePaths[layeredIndex].map(axes.pagePoint)
            let transition = diagram.transitions[transitionIndex]
            guard path.count >= 2, route.count >= 2 else { continue }
            let sourcePoint = attachedEnd(path[0], next: path[1], state: transition.sourceIndex)
            let targetPoint = attachedEnd(path[path.count - 1], next: path[path.count - 2], state: transition.targetIndex)
            let points = [sourcePoint] + route.dropFirst().dropLast().map(axes.pagePoint) + [targetPoint]
            let drawn = DiagramRouteDrawing.path(through: points, flowIsVertical: axes.flowIsVertical, startTrim: 0,
                                                 endTrim: DiagramEdgeMark.lineTrim(for: .arrow))
            let textCenter = placement.edgeLabelCenters[layeredIndex].map(axes.pagePoint)
                ?? CGPoint(x: (sourcePoint.x + targetPoint.x) / 2, y: (sourcePoint.y + targetPoint.y) / 2)
            transitions[transitionIndex] = StateDiagramLayoutTransition(
                path: drawn.path, arrow: DiagramEdgeMark(arrowhead: .arrow, tip: targetPoint, direction: drawn.endDirection),
                text: centered(measured.transitionTexts[transitionIndex], at: textCenter))
        }
    }

    /// An end of a transition of a diagram laid out without boxes, from its state's place onto its state.
    private func attachedEnd(_ end: CGPoint, next: CGPoint, state: Int) -> CGPoint {
        let place = surroundings.placeSizes[state]
        let layoutSize = axes.flowIsVertical ? CGSize(width: place.across, height: place.along) : CGSize(width: place.along, height: place.across)
        let kind = diagram.states[state].kind
        return ReferenceStateDiagramRouteEnds.attached(end, next: next, center: stateCenters[state], layoutSize: layoutSize, drawnSize: measured.stateSizes[state],
                                              isBar: kind == .fork || kind == .join)
    }

    /// The states of a diagram laid out in boxes at their centers on the page; a composite state at the center of its box.
    mutating func placeStates(clustered: ReferenceStateDiagramClusterGraph, placement: LayeredClusterPlacement) {
        self.clustered = clustered
        compositeFrames = Array(placement.clusterFrames.prefix(diagram.composites.count))
        for (noteIndex, node) in clustered.compositeSurroundings.noteNodes { compositeNoteCenters[noteIndex] = placement.nodeCenters[node] }
        stateCenters = diagram.states.indices.map { state in
            if let compositeIndex = clustered.compositeOfState[state] {
                let frame = placement.clusterFrames[compositeIndex]
                return CGPoint(x: frame.midX, y: frame.midY)
            }
            return placement.nodeCenters[clustered.layoutNodeIndices[state] ?? 0]
        }
    }

    /// The transitions of a diagram laid out in boxes, along their routes: each end where Pele's layout spread and
    /// settled it on its state's place, moved onto the state's own box (`ReferenceStateDiagramRouteEnds`); an end at a composite
    /// stays on the composite's box where the layout left it, as Pele's `attach` leaves a group's; each segment an S
    /// along its own flow.
    mutating func placeTransitions(clustered: ReferenceStateDiagramClusterGraph, placement: LayeredClusterPlacement) {
        func attached(_ end: CGPoint, next: CGPoint, state: Int) -> CGPoint {
            guard clustered.compositeOfState[state] == nil, let node = clustered.layoutNodeIndices[state] else { return end }
            let kind = diagram.states[state].kind
            return ReferenceStateDiagramRouteEnds.attached(end, next: next, center: placement.nodeCenters[node], layoutSize: clustered.graph.nodeSizes[node],
                                                  drawnSize: measured.stateSizes[state], isBar: kind == .fork || kind == .join)
        }
        for (layoutIndex, transitionIndex) in clustered.layoutTransitionIndices.enumerated() {
            let laidOut = placement.edgeRoutes[layoutIndex]
            var route = laidOut
            if let anchored = clustered.anchors[transitionIndex]?.anchor {
                route = Self.anchoredRoute(route, anchor: anchored, frame: placement.clusterFrames[anchored.compositeIndex],
                                           direction: clustered.compositeDirections[anchored.compositeIndex], title: clustered.titles[anchored.compositeIndex])
            }
            let isInward = clustered.anchors[transitionIndex]?.anchor.isInward
            let transition = diagram.transitions[transitionIndex]
            let laidOutPoints = laidOut.points
            guard laidOutPoints.count >= 2, let firstPoint = route.points.first, let lastPoint = route.points.last else { continue }
            let sourcePoint = isInward == true ? firstPoint : attached(laidOutPoints[0], next: laidOutPoints[1], state: transition.sourceIndex)
            let targetPoint = isInward == false ? lastPoint
                : attached(laidOutPoints[laidOutPoints.count - 1], next: laidOutPoints[laidOutPoints.count - 2], state: transition.targetIndex)
            let (points, segmentAxes) = Self.withoutPointsOnTheEnds([sourcePoint] + route.points.dropFirst().dropLast() + [targetPoint],
                                                                    segmentsRunVertically: route.segmentsRunVertically)
            let drawn = DiagramRouteDrawing.path(through: points, segmentsRunVertically: segmentAxes, startTrim: 0,
                                                 endTrim: DiagramEdgeMark.lineTrim(for: .arrow))
            let textCenter = placement.edgeLabelCenters[layoutIndex]
                ?? CGPoint(x: (sourcePoint.x + targetPoint.x) / 2, y: (sourcePoint.y + targetPoint.y) / 2)
            transitions[transitionIndex] = StateDiagramLayoutTransition(
                path: drawn.path, arrow: DiagramEdgeMark(arrowhead: .arrow, tip: targetPoint, direction: drawn.endDirection),
                text: centered(measured.transitionTexts[transitionIndex], at: textCenter))
        }
    }

    /// The route of a transition between a composite and a state inside it, drawn on from its point inside the composite
    /// to the composite's border: below the title on the side the box's flow starts from when it leaves the composite,
    /// on the side its flow ends at when it arrives, as Pele draws it.
    private static func anchoredRoute(_ route: LayeredClusterRoute, anchor: ReferenceStateDiagramCompositeAnchor, frame: CGRect, direction: FlowchartDirection,
                                      title: DiagramTextBlock?) -> LayeredClusterRoute {
        let titleBand = title.map { title in title.size.height + 12 } ?? 0
        let anchorPoint = anchor.isInward ? route.points[0] : route.points[route.points.count - 1]
        let border: CGPoint
        switch (direction, anchor.isInward) {
        case (.topToBottom, true), (.bottomToTop, false): border = CGPoint(x: anchorPoint.x, y: frame.minY + titleBand)
        case (.topToBottom, false), (.bottomToTop, true): border = CGPoint(x: anchorPoint.x, y: frame.maxY)
        case (.leftToRight, true), (.rightToLeft, false): border = CGPoint(x: frame.minX, y: anchorPoint.y)
        case (.leftToRight, false), (.rightToLeft, true): border = CGPoint(x: frame.maxX, y: anchorPoint.y)
        }
        let runsVertically = !direction.runsAcross
        return anchor.isInward
            ? LayeredClusterRoute(points: [border] + route.points, segmentsRunVertically: [runsVertically] + route.segmentsRunVertically)
            : LayeredClusterRoute(points: route.points + [border], segmentsRunVertically: route.segmentsRunVertically + [runsVertically])
    }

    /// The route without a passing point that lies on its end: where an unseen box around a composite has no room above or
    /// below it, the point where a transition crosses that box's border is where it meets the composite.
    private static func withoutPointsOnTheEnds(_ points: [CGPoint], segmentsRunVertically: [Bool]) -> ([CGPoint], [Bool]) {
        var points = points
        var axes = segmentsRunVertically
        func coincide(_ first: CGPoint, _ second: CGPoint) -> Bool { abs(first.x - second.x) < 0.01 && abs(first.y - second.y) < 0.01 }
        while points.count > 2, axes.count > 1, coincide(points[points.count - 2], points[points.count - 1]) {
            points.remove(at: points.count - 2)
            axes.removeLast()
        }
        while points.count > 2, axes.count > 1, coincide(points[0], points[1]) {
            points.remove(at: 1)
            axes.removeFirst()
        }
        return (points, axes)
    }

    /// The composite states' boxes, each name in the band along its box's top, clear of the transitions' bends where it
    /// can be (`ReferenceStateDiagramCompositeTitles`, from the layout's routes as Pele reads them), and a dashed line between
    /// each two concurrent regions of a body.
    mutating func placeComposites(clustered: ReferenceStateDiagramClusterGraph, placement: LayeredClusterPlacement) {
        let titles = ReferenceStateDiagramCompositeTitles(routes: placement.edgeRoutes.map(\.points))
        composites = diagram.composites.indices.map { compositeIndex in
            let frame = placement.clusterFrames[compositeIndex]
            let title = clustered.titles[compositeIndex].map { title in titles.placed(title, in: frame) }
            return FlowchartLayoutCluster(frame: frame, title: title, depth: clustered.depths[compositeIndex], isTitleCrossed: false)
        }
        regionDividers = clustered.regionClusterIndices.flatMap { regionIndices in
            ReferenceStateDiagramRegionDividers.dividers(between: regionIndices.map { region in placement.clusterFrames[region] })
        }
    }

    /// The loops of every state that has transitions to itself.
    mutating func placeSelfLoops() {
        for (state, loopTransitionIndices) in measured.selfLoopTransitionIndices.enumerated() where !loopTransitionIndices.isEmpty {
            // A composite's loops hang off its box, beside it across the flow of the box around it.
            let composite = clustered?.compositeOfState[state]
            let size = composite.map { compositeFrames[$0].size } ?? measured.stateSizes[state]
            let flowIsVertical = composite.map { clustered?.compositeSurroundings.containerRunsVertically[$0] ?? true } ?? axes.flowIsVertical
            let loops = ReferenceStateDiagramSelfLoops.loops(center: stateCenters[state], size: size, flowIsVertical: flowIsVertical,
                                                    textSizes: loopTransitionIndices.map { transitionIndex in measured.transitionTexts[transitionIndex]?.size })
            for (transitionIndex, loop) in zip(loopTransitionIndices, loops) {
                transitions[transitionIndex] = StateDiagramLayoutTransition(
                    path: loop.path, arrow: loop.arrow,
                    text: loop.textCenter.flatMap { center in centered(measured.transitionTexts[transitionIndex], at: center) })
            }
        }
    }

    /// Each note beside its state, with the dashed line from the state's side that faces it.
    func notes() -> [StateDiagramLayoutNote] {
        diagram.notes.enumerated().map { noteIndex, note in
            if let center = compositeNoteCenters[noteIndex], let composite = clustered?.compositeOfState[note.stateIndex] {
                return compositeNote(at: noteIndex, center: center, compositeFrame: compositeFrames[composite])
            }
            return stateNote(at: noteIndex, note: note)
        }
    }

    /// A note laid out beside a composite, with its dashed line from the middle of the composite's side that faces it.
    private func compositeNote(at noteIndex: Int, center: CGPoint, compositeFrame: CGRect) -> StateDiagramLayoutNote {
        let size = measured.noteSizes[noteIndex]
        let frame = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
        let isBeside = frame.maxX <= compositeFrame.minX || frame.minX >= compositeFrame.maxX
        let compositeSide: DiagramSide = isBeside ? (frame.midX < compositeFrame.midX ? .left : .right) : (frame.midY < compositeFrame.midY ? .top : .bottom)
        let compositeCenter = CGPoint(x: compositeFrame.midX, y: compositeFrame.midY)
        let start = ReferenceStateDiagramEdgePorts.sidePoint(center: compositeCenter, size: compositeFrame.size, side: compositeSide, offset: 0)
        let end = ReferenceStateDiagramEdgePorts.sidePoint(center: center, size: size, side: opposite(compositeSide), offset: 0)
        let connector = DiagramRouteDrawing.path(through: [start, end], flowIsVertical: !isBeside, startTrim: 0, endTrim: 0).path
        var text = measured.noteTexts[noteIndex]
        text.center = center
        return StateDiagramLayoutNote(frame: frame, text: text, connector: connector)
    }

    /// A note beside its state, where the state's surroundings put it.
    private func stateNote(at noteIndex: Int, note: StateDiagramNote) -> StateDiagramLayoutNote {
        let stateCenter = stateCenters[note.stateIndex]
        let offset = surroundings.noteOffsets[noteIndex]
        let size = measured.noteSizes[noteIndex]
        let center = CGPoint(x: stateCenter.x + offset.dx, y: stateCenter.y + offset.dy)
        let stateSide = noteSide(note.side)
        let stateSize = measured.stateSizes[note.stateIndex]
        let stackPosition = surroundings.noteStackPositions[noteIndex]
        let offsets = ReferenceStateDiagramEdgePorts.offsets(count: stackPosition.count, placement: diagram.states[note.stateIndex].kind.portPlacement,
                                                    sideLength: stateSide.isHorizontal ? stateSize.width : stateSize.height)
        let start = ReferenceStateDiagramEdgePorts.sidePoint(center: stateCenter, size: stateSize, side: stateSide, offset: offsets[stackPosition.index])
        let end = ReferenceStateDiagramEdgePorts.sidePoint(center: center, size: size, side: opposite(stateSide), offset: 0)
        let connector = DiagramRouteDrawing.path(through: [start, end], flowIsVertical: !axes.flowIsVertical, startTrim: 0, endTrim: 0).path
        var text = measured.noteTexts[noteIndex]
        text.center = center
        return StateDiagramLayoutNote(frame: CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height),
                                      text: text, connector: connector)
    }

    /// The side of a state that faces its notes on `side`: across the flow, before or after it.
    private func noteSide(_ side: StateDiagramNoteSide) -> DiagramSide {
        switch side {
        case .left: axes.flowIsVertical ? .left : .top
        case .right: axes.flowIsVertical ? .right : .bottom
        }
    }

    private func opposite(_ side: DiagramSide) -> DiagramSide {
        switch side {
        case .top: .bottom
        case .bottom: .top
        case .left: .right
        case .right: .left
        }
    }

    private func centered(_ text: DiagramTextBlock?, at center: CGPoint) -> DiagramTextBlock? {
        guard var text else { return nil }
        text.center = center
        return text
    }

    /// The finished layout: everything moved so that the drawing starts `padding` from the top left, below the
    /// title, and centered under the title when the title is wider.
    func finished(font: DiagramFont, title: DiagramTextBlock?, padding: CGFloat, titleGap: CGFloat) -> StateDiagramLayout {
        // A composite state is its box, not a state.
        let states = diagram.states.indices.filter { index in clustered?.compositeOfState[index] == nil }.map { index in placedState(at: index) }
        let placedTransitions = transitions.compactMap { transition in transition }
        let placedNotes = notes()
        var bounds = ReferenceStateDiagramLayoutBounds.union(states: states, transitions: placedTransitions, notes: placedNotes)
        for composite in composites { bounds = bounds.union(composite.frame) }
        let titleSize = title?.size ?? .zero
        let innerWidth = max(bounds.width, titleSize.width)
        let titleHeight = title == nil ? 0 : titleSize.height + titleGap
        let offset = CGVector(dx: padding + (innerWidth - bounds.width) / 2 - bounds.minX, dy: padding + titleHeight - bounds.minY)
        let size = CGSize(width: (innerWidth + 2 * padding).rounded(.up), height: (bounds.height + titleHeight + 2 * padding).rounded(.up))
        var placedTitle = title
        placedTitle?.center = CGPoint(x: size.width / 2, y: padding + titleSize.height / 2)
        return StateDiagramLayout(size: size, font: font, states: states.map { state in state.translated(by: offset) },
                                  transitions: placedTransitions.map { transition in transition.translated(by: offset) },
                                  notes: placedNotes.map { note in note.translated(by: offset) }, title: placedTitle,
                                  composites: composites.map { composite in composite.translated(by: offset) },
                                  regionDividers: regionDividers.map { divider in divider.translated(by: offset) })
    }

    /// A state's frame, its name in the top of a box and its other descriptions below the line under the name.
    private func placedState(at index: Int) -> StateDiagramLayoutState {
        let center = stateCenters[index]
        let size = measured.stateSizes[index]
        let frame = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
        let name = measured.names[index].map { block in
            var placed = block
            placed.center = CGPoint(x: center.x, y: frame.minY + ReferenceStateDiagramMeasurement.verticalPadding + block.size.height / 2)
            return placed
        }
        let details = measured.details[index].map { block in
            var placed = block
            let top = (name?.frame.maxY ?? frame.minY) + ReferenceStateDiagramMeasurement.detailsGap
            placed.center = CGPoint(x: center.x, y: top + block.size.height / 2)
            return placed
        }
        return StateDiagramLayoutState(kind: diagram.states[index].kind, frame: frame, name: name, details: details)
    }
}
