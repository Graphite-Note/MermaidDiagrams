/**
 * File: StateDiagramBoxedLayout.swift
 * -----------------------------------
 * Layer: Core
 * Description: A state diagram with composite states laid out as nested boxes in the scratch arena: the compound
 *              layout's spans read on the page with no placement made in between.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.3
 * Date: 25/11/2026
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
        guard let compound = clustered.graph.laidOut(spacing: StateDiagramLayoutEngine.clusterSpacing, maximumPointCount: maximumPointCount,
                                                     arena: arena) else {
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
        let nodeCount = clustered.graph.nodeCount
        frames = arena.uninitializedSpan(count: clustered.graph.boxCount)
        for cluster in 0..<frames.count { frames[cluster] = compound.nodes[nodeCount + cluster].frame }
    }

    /// The center of layout node `node`.
    @inline(__always)
    func center(of node: Int) -> CGPoint { CGPoint(x: compound.nodes[node].x, y: compound.nodes[node].y) }

    /// The points of laid-out edge `edge`'s route, with `border` before them (`isFirst`) or after them, and each
    /// segment's flow, the border's segment's `runsVertically`, written over `segmentsRunVertically`.
    func route(of edge: Int, border: (point: CGPoint, isFirst: Bool, runsVertically: Bool)?, segmentsRunVertically axes: inout [Bool]) -> [CGPoint] {
        let range = compound.routeRange(of: edge)
        var points: [CGPoint] = []
        points.reserveCapacity(range.count + 1)
        axes.removeAll(keepingCapacity: true)
        if let border, border.isFirst {
            points.append(border.point)
            axes.append(border.runsVertically)
        }
        for index in range {
            let point = compound.routePoints[index]
            points.append(point.point)
            if index > range.lowerBound { axes.append(!point.runsHorizontally) }
        }
        if let border, !border.isFirst {
            points.append(border.point)
            axes.append(border.runsVertically)
        }
        return points
    }

    /// The center of laid-out edge `edge`'s text, or nil for an edge without text (but one between a box and what it
    /// holds, which has its middle).
    func labelCenter(of edge: Int) -> CGPoint? { compound.labelCenter(of: edge) }
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
            return StateDiagramRouteEnds.attached(end, next: next, center: boxes.center(of: node), layoutSize: clustered.layoutSizes[node],
                                                  drawnSize: measured.stateSizes[state], isBar: kind == .fork || kind == .join)
        }
        // Each segment's flow, in one list kept from transition to transition; each route's points in a list of its own,
        // which its path takes.
        var segmentAxes: [Bool] = []
        for (layoutIndex, transitionIndex) in clustered.layoutTransitionIndices.enumerated() {
            let range = boxes.compound.routeRange(of: layoutIndex)
            guard range.count >= 2 else { continue }
            let firstLaidOut = boxes.compound.routePoints[range.lowerBound].point
            let secondLaidOut = boxes.compound.routePoints[range.lowerBound + 1].point
            let lastLaidOut = boxes.compound.routePoints[range.upperBound - 1].point
            let beforeLastLaidOut = boxes.compound.routePoints[range.upperBound - 2].point
            let border = Self.border(of: transitionIndex, boxes: boxes, firstPoint: firstLaidOut, lastPoint: lastLaidOut)
            let transition = diagram.transitions[transitionIndex]
            let sourcePoint = border?.isFirst == true ? border?.point ?? firstLaidOut
                : attached(firstLaidOut, next: secondLaidOut, state: transition.sourceIndex)
            let targetPoint = border?.isFirst == false ? border?.point ?? lastLaidOut
                : attached(lastLaidOut, next: beforeLastLaidOut, state: transition.targetIndex)
            var points = boxes.route(of: layoutIndex, border: border, segmentsRunVertically: &segmentAxes)
            points[0] = sourcePoint
            points[points.count - 1] = targetPoint
            Self.removePointsOnTheEnds(&points, segmentsRunVertically: &segmentAxes)
            let drawn = DiagramRouteDrawing.path(through: points, segmentsRunVertically: segmentAxes, startTrim: 0,
                                                 endTrim: DiagramEdgeMark.lineTrim(for: .arrow))
            let textCenter = boxes.labelCenter(of: layoutIndex)
                ?? CGPoint(x: (sourcePoint.x + targetPoint.x) / 2, y: (sourcePoint.y + targetPoint.y) / 2)
            transitions[transitionIndex] = StateDiagramLayoutTransition(
                path: drawn.path, arrow: DiagramEdgeMark(arrowhead: .arrow, tip: targetPoint, direction: drawn.endDirection),
                text: Self.centered(measured.transitionTexts[transitionIndex], at: textCenter))
        }
    }

    /// A transition between a composite and a state inside it is drawn on to the composite's border, before its route
    /// (`isFirst`) when it leaves the composite and after it when it arrives, the border's segment along the composite's
    /// flow; nil for the other transitions. `firstPoint` and `lastPoint` are the ends of its laid-out route.
    private static func border(of transitionIndex: Int, boxes: StateDiagramPlacedBoxes, firstPoint: CGPoint,
                               lastPoint: CGPoint) -> (point: CGPoint, isFirst: Bool, runsVertically: Bool)? {
        let clustered = boxes.clustered
        guard transitionIndex < clustered.anchors.count, let anchor = clustered.anchors[transitionIndex]?.anchor else { return nil }
        let direction = clustered.compositeDirections[anchor.compositeIndex]
        let point = border(of: anchor, at: anchor.isInward ? firstPoint : lastPoint, frame: boxes.frames[anchor.compositeIndex], direction: direction,
                           title: clustered.titles[anchor.compositeIndex])
        return (point, anchor.isInward, !direction.runsAcross)
    }

    /// Where a transition between a composite and a state inside it meets the composite's border, from its point inside
    /// the composite: below the title on the side the box's flow starts from when it leaves the composite, on the side
    /// its flow ends at when it arrives, as Pele draws it.
    private static func border(of anchor: StateDiagramCompositeAnchor, at anchorPoint: CGPoint, frame: CGRect, direction: FlowchartDirection,
                               title: DiagramTextBlock?) -> CGPoint {
        let titleBand = title.map { title in title.size.height + 12 } ?? 0
        switch (direction, anchor.isInward) {
        case (.topToBottom, true), (.bottomToTop, false): return CGPoint(x: anchorPoint.x, y: frame.minY + titleBand)
        case (.topToBottom, false), (.bottomToTop, true): return CGPoint(x: anchorPoint.x, y: frame.maxY)
        case (.leftToRight, true), (.rightToLeft, false): return CGPoint(x: frame.minX, y: anchorPoint.y)
        case (.leftToRight, false), (.rightToLeft, true): return CGPoint(x: frame.maxX, y: anchorPoint.y)
        }
    }

    /// The route without a passing point that lies on its end, where it stands: where an unseen box around a composite
    /// has no room above or below it, the point where a transition crosses that box's border is where it meets the
    /// composite.
    private static func removePointsOnTheEnds(_ points: inout [CGPoint], segmentsRunVertically axes: inout [Bool]) {
        func coincide(_ first: CGPoint, _ second: CGPoint) -> Bool { abs(first.x - second.x) < 0.01 && abs(first.y - second.y) < 0.01 }
        while points.count > 2, axes.count > 1, coincide(points[points.count - 2], points[points.count - 1]) {
            points.remove(at: points.count - 2)
            axes.removeLast()
        }
        while points.count > 2, axes.count > 1, coincide(points[0], points[1]) {
            points.remove(at: 1)
            axes.removeFirst()
        }
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
