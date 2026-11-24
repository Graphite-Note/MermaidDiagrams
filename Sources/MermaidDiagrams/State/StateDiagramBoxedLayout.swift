/**
 * File: StateDiagramBoxedLayout.swift
 * -----------------------------------
 * Layer: Core
 * Description: A state diagram with composite states laid out as nested boxes in the scratch arena: the compound
 *              layout's spans read on the page with no placement made in between.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics

/// A state diagram with composite states: each composite a box laid out on its own and placed in the box around it, its
/// concurrent regions boxes side by side inside it (`StateDiagramClusterGraph`, `LayeredCompoundLayout`); the compound
/// layout read where it stands in the calling thread's arena.
enum StateDiagramBoxedLayout {
    /// The layout, or nil when the boxes would need more than `maximumPointCount` nodes and passing points.
    static func layout(_ diagram: StateDiagram, clustered: StateDiagramClusterGraph, measured: StateDiagramMeasurement,
                       surroundings: StateDiagramSurroundings, title: DiagramTextBlock?, font: DiagramFont, maximumPointCount: Int,
                       arena: DiagramScratchArena) -> StateDiagramLayout? {
        guard let compound = LayeredClusterLayout.laidOutInCompoundLayout(clustered.graph, spacing: StateDiagramLayoutEngine.clusterSpacing,
                                                                          maximumPointCount: maximumPointCount, arena: arena, isRecorded: true) else {
            return nil
        }
        let boxes = StateDiagramPlacedBoxes(clustered: clustered, compound: compound, arena: arena)
        let axes = FlowchartFlowAxes(direction: diagram.direction, alongExtent: 0)
        var page = StateDiagramPageAssembly(diagram: diagram, measured: measured, surroundings: surroundings, axes: axes)
        page.placeStates(boxes: boxes)
        page.placeTransitions(boxes: boxes)
        page.placeSelfLoops()
        page.placeComposites(boxes: boxes)
        return page.finished(font: font, title: title, padding: StateDiagramLayoutEngine.padding, titleGap: StateDiagramLayoutEngine.titleGap)
    }
}

/// The compound layout of a state diagram's boxes read on the page: each node's center, each box's frame, and each
/// laid-out edge's route, segments and text's center.
struct StateDiagramPlacedBoxes {
    let clustered: StateDiagramClusterGraph
    let compound: LayeredCompoundLayout
    /// Each box's frame, composites first, then regions, then the unseen boxes around composites.
    let frames: ScratchSpan<CGRect>

    init(clustered: StateDiagramClusterGraph, compound: LayeredCompoundLayout, arena: DiagramScratchArena) {
        self.clustered = clustered
        self.compound = compound
        let nodeCount = clustered.graph.nodeSizes.count
        frames = arena.uninitializedSpan(count: clustered.graph.clusters.count)
        for cluster in 0..<frames.count {
            let node = compound.nodes[nodeCount + cluster]
            frames[cluster] = CGRect(x: node.x - node.width / 2, y: node.y - node.height / 2, width: node.width, height: node.height)
        }
    }

    /// The center of layout node `node`.
    @inline(__always)
    func center(of node: Int) -> CGPoint { CGPoint(x: compound.nodes[node].x, y: compound.nodes[node].y) }

    /// The route of laid-out edge `edge`: its points, and for each segment whether the flow it follows runs vertically.
    func route(of edge: Int) -> LayeredClusterRoute {
        let range = compound.routeRange(of: edge)
        var points: [CGPoint] = []
        var segmentsRunVertically: [Bool] = []
        points.reserveCapacity(range.count)
        segmentsRunVertically.reserveCapacity(max(range.count - 1, 0))
        for index in range {
            let point = compound.routePoints[index]
            points.append(point.point)
            if index > range.lowerBound { segmentsRunVertically.append(!point.runsHorizontally) }
        }
        return LayeredClusterRoute(points: points, segmentsRunVertically: segmentsRunVertically)
    }

    /// The center of laid-out edge `edge`'s text, or nil for an edge without text (but one between a box and what it
    /// holds, which has its middle).
    func labelCenter(of edge: Int) -> CGPoint? {
        compound.edges[edge].labelWidth > 0 || compound.isStray(edge) ? compound.edges[edge].labelCenter : nil
    }
}

extension StateDiagramPageAssembly {
    /// The states of a diagram laid out in boxes at their centers on the page; a composite state at the center of its box.
    mutating func placeStates(boxes: StateDiagramPlacedBoxes) {
        let clustered = boxes.clustered
        self.clustered = clustered
        compositeFrames = Array(boxes.frames.part(0..<min(diagram.composites.count, boxes.frames.count)))
        compositeNoteCenters = Array(repeating: nil, count: diagram.notes.count)
        for (noteIndex, node) in clustered.compositeSurroundings.noteNodes { compositeNoteCenters[noteIndex] = boxes.center(of: node) }
        var centers: [CGPoint] = []
        centers.reserveCapacity(diagram.states.count)
        for state in diagram.states.indices {
            if let compositeIndex = clustered.compositeOfState[state] {
                let frame = boxes.frames[compositeIndex]
                centers.append(CGPoint(x: frame.midX, y: frame.midY))
            } else {
                centers.append(boxes.center(of: clustered.layoutNodeIndices[state] ?? 0))
            }
        }
        placeStates(centers: centers)
    }

    /// The transitions of a diagram laid out in boxes, along their routes: each end where Pele's layout spread and
    /// settled it on its state's place, moved onto the state's own box (`StateDiagramRouteEnds`); an end at a composite
    /// stays on the composite's box where the layout left it, as Pele's `attach` leaves a group's; each segment an S
    /// along its own flow.
    mutating func placeTransitions(boxes: StateDiagramPlacedBoxes) {
        let clustered = boxes.clustered
        func attached(_ end: CGPoint, next: CGPoint, state: Int) -> CGPoint {
            guard clustered.compositeOfState[state] == nil, let node = clustered.layoutNodeIndices[state] else { return end }
            let kind = diagram.states[state].kind
            return StateDiagramRouteEnds.attached(end, next: next, center: boxes.center(of: node), layoutSize: clustered.graph.nodeSizes[node],
                                                  drawnSize: measured.stateSizes[state], isBar: kind == .fork || kind == .join)
        }
        for (layoutIndex, transitionIndex) in clustered.layoutTransitionIndices.enumerated() {
            let laidOut = boxes.route(of: layoutIndex)
            var route = laidOut
            let placedAnchor = transitionIndex < clustered.anchors.count ? clustered.anchors[transitionIndex] : nil
            if let anchored = placedAnchor?.anchor {
                route = Self.anchoredRoute(route, anchor: anchored, frame: boxes.frames[anchored.compositeIndex],
                                           direction: clustered.compositeDirections[anchored.compositeIndex], title: clustered.titles[anchored.compositeIndex])
            }
            let isInward = placedAnchor?.anchor.isInward
            let transition = diagram.transitions[transitionIndex]
            let laidOutPoints = laidOut.points
            guard laidOutPoints.count >= 2, let firstPoint = route.points.first, let lastPoint = route.points.last else { continue }
            let sourcePoint = isInward == true ? firstPoint : attached(laidOutPoints[0], next: laidOutPoints[1], state: transition.sourceIndex)
            let targetPoint = isInward == false ? lastPoint
                : attached(laidOutPoints[laidOutPoints.count - 1], next: laidOutPoints[laidOutPoints.count - 2], state: transition.targetIndex)
            var ended: [CGPoint] = []
            ended.reserveCapacity(route.points.count)
            ended.append(sourcePoint)
            if route.points.count > 2 { ended.append(contentsOf: route.points[1..<(route.points.count - 1)]) }
            ended.append(targetPoint)
            let (points, segmentAxes) = Self.withoutPointsOnTheEnds(ended, segmentsRunVertically: route.segmentsRunVertically)
            let drawn = DiagramRouteDrawing.path(through: points, segmentsRunVertically: segmentAxes, startTrim: 0,
                                                 endTrim: DiagramEdgeMark.lineTrim(for: .arrow))
            let textCenter = boxes.labelCenter(of: layoutIndex)
                ?? CGPoint(x: (sourcePoint.x + targetPoint.x) / 2, y: (sourcePoint.y + targetPoint.y) / 2)
            transitions[transitionIndex] = StateDiagramLayoutTransition(
                path: drawn.path, arrow: DiagramEdgeMark(arrowhead: .arrow, tip: targetPoint, direction: drawn.endDirection),
                text: Self.centered(measured.transitionTexts[transitionIndex], at: textCenter))
        }
    }

    /// The route of a transition between a composite and a state inside it, drawn on from its point inside the composite
    /// to the composite's border: below the title on the side the box's flow starts from when it leaves the composite,
    /// on the side its flow ends at when it arrives, as Pele draws it.
    private static func anchoredRoute(_ route: LayeredClusterRoute, anchor: StateDiagramCompositeAnchor, frame: CGRect, direction: FlowchartDirection,
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
    /// can be (`StateDiagramCompositeTitles`, from the layout's routes as Pele reads them), and a dashed line between
    /// each two concurrent regions of a body.
    mutating func placeComposites(boxes: StateDiagramPlacedBoxes) {
        let clustered = boxes.clustered
        let titles = StateDiagramCompositeTitles(compound: boxes.compound)
        composites.reserveCapacity(diagram.composites.count)
        for compositeIndex in diagram.composites.indices {
            let frame = boxes.frames[compositeIndex]
            let title = clustered.titles[compositeIndex].map { title in titles.placed(title, in: frame) }
            composites.append(FlowchartLayoutCluster(frame: frame, title: title, depth: clustered.depths[compositeIndex], isTitleCrossed: false))
        }
        for regionIndices in clustered.regionClusterIndices where !regionIndices.isEmpty {
            regionDividers += StateDiagramRegionDividers.dividers(between: regionIndices.map { region in boxes.frames[region] })
        }
    }
}
