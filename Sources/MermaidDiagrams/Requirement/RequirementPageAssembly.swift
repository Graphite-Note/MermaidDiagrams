/**
 * File: RequirementPageAssembly.swift
 * -----------------------------------
 * Layer: Core
 * Description: Puts a placed requirement diagram on its page: the boxes at their centers, the relations from side to
 *              side through their passing points and the loops beside their boxes, each written once where the page has
 *              it, with its marks and text, into the layout's lists; the boxes' texts placed last.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics

/// Puts a placed requirement diagram on the page: the boxes at their centers, the relations from side to side through
/// their passing points with their marks and texts, the loops beside their boxes, everything moved inside the padding
/// below the title (`RequirementPageFrame`) as it is written. Every point is found around the layout's origin and moved
/// as `translated(by:)` moves it, so that each is the number the layout moved after placing gave. The centers and the
/// relations' places are spans of the thread's arena; the segments and the relations are the layout's own lists.
struct RequirementPageAssembly {
    let measured: RequirementMeasurement
    let axes: FlowchartFlowAxes
    let frame: RequirementPageFrame
    /// The boxes' centers around the layout's origin, by box.
    let centers: ScratchSpan<CGPoint>
    /// By the measurement's edge index, each relation placed, where `isPlaced` says.
    private let relations: ScratchSpan<RequirementPlacedRelation>
    private let isPlaced: ScratchSpan<Bool>
    private var segments: [DiagramPathSegment] = []

    init(measured: RequirementMeasurement, axes: FlowchartFlowAxes, flowNodes: ScratchSpan<LayeredFlatNode>, frame: RequirementPageFrame,
         arena: DiagramScratchArena) {
        self.measured = measured
        self.axes = axes
        self.frame = frame
        centers = arena.uninitializedSpan(count: flowNodes.count)
        for node in 0..<flowNodes.count { centers[node] = axes.pagePoint(CGPoint(x: flowNodes[node].x, y: flowNodes[node].y)) }
        relations = arena.uninitializedSpan(count: measured.edges.count)
        isPlaced = arena.span(count: measured.edges.count, repeating: false)
        segments.reserveCapacity(3 * measured.edges.count)
    }

    /// The relations between two boxes, along their routes; `layeredEdgeIndices[i]` is the edge of the flat layout's
    /// `i`-th edge, whose route runs from its source's center to its target's through its path's inner points.
    mutating func placeRelations(layeredEdgeIndices: ScratchSpan<Int>, nodes: ScratchSpan<LayeredFlatNode>, edges laidOut: ScratchSpan<LayeredSpanEdge>,
                                 points: ScratchSpan<CGPoint>, arena: DiagramScratchArena) {
        let routes = RankedRoutes(nodes: nodes, edges: laidOut, points: points, axes: axes)
        let ends: ScratchSpan<RequirementEdgePorts.End> = arena.uninitializedSpan(count: 2 * layeredEdgeIndices.count)
        var longest = 2
        for layeredIndex in 0..<layeredEdgeIndices.count {
            let edgeIndex = layeredEdgeIndices[layeredIndex]
            let count = routes.count(of: layeredIndex)
            longest = max(longest, count)
            let edge = measured.edges[edgeIndex]
            ends[2 * layeredIndex] = end(of: edgeIndex, isSourceEnd: true, box: Int(edge.source), at: routes.point(0, count: count, of: layeredIndex),
                                         next: routes.point(1, count: count, of: layeredIndex))
            ends[2 * layeredIndex + 1] = end(of: edgeIndex, isSourceEnd: false, box: Int(edge.target), at: routes.point(count - 1, count: count, of: layeredIndex),
                                             next: routes.point(count - 2, count: count, of: layeredIndex))
        }
        let sizes: ScratchSpan<CGSize> = arena.uninitializedSpan(count: measured.boxes.count)
        for box in 0..<measured.boxes.count { sizes[box] = measured.boxes[box].size }
        let ports = RequirementEdgePorts(ends: ends, edgeCount: measured.edges.count, centers: centers, sizes: sizes, arena: arena)
        let routePoints: ScratchSpan<CGPoint> = arena.uninitializedSpan(count: longest)
        for layeredIndex in 0..<layeredEdgeIndices.count {
            let edgeIndex = layeredEdgeIndices[layeredIndex]
            guard ports.isSourcePlaced[edgeIndex], ports.isTargetPlaced[edgeIndex] else { continue }
            let count = routes.count(of: layeredIndex)
            let route = routePoints.part(0..<count)
            route[0] = ports.sourcePoints[edgeIndex]
            for index in 1..<(count - 1) { route[index] = routes.point(index, count: count, of: layeredIndex) }
            route[count - 1] = ports.targetPoints[edgeIndex]
            let laidOutEdge = laidOut[layeredIndex]
            let textCenter = laidOutEdge.labelWidth > 0 ? axes.pagePoint(laidOutEdge.labelCenter)
                : CGPoint(x: (route[0].x + route[count - 1].x) / 2, y: (route[0].y + route[count - 1].y) / 2)
            placeRelation(edgeIndex, along: route, textCenter: textCenter)
        }
    }

    /// Relation `edgeIndex` along `route`, from its source's port to its target's: its line written into the segments,
    /// its mark at the end it has one, its text at `textCenter`, all moved onto the page.
    private mutating func placeRelation(_ edgeIndex: Int, along route: ScratchSpan<CGPoint>, textCenter: CGPoint) {
        let edge = measured.edges[edgeIndex]
        let sourcePort = route[0]
        let targetPort = route[route.count - 1]
        let firstSegment = segments.count
        let drawn = RequirementRouteSegments.append(through: route, flowIsVertical: axes.flowIsVertical,
                                                    startTrim: edge.isContainment ? 2 * RequirementLayoutEngine.containmentRadius : 0, offset: frame.offset,
                                                    into: &segments)
        let mark: RequirementRelationMark = edge.isContainment
            ? .containment(point: sourcePort, towardBox: CGVector(dx: -drawn.startDirection.dx, dy: -drawn.startDirection.dy))
            : .arrow(tip: targetPort, direction: drawn.endDirection)
        relations[edgeIndex] = RequirementPlacedRelation(kind: edge.kind, start: drawn.start, firstSegment: Int32(firstSegment),
                                                         segmentCount: Int32(segments.count - firstSegment), mark: mark.translated(by: frame.offset),
                                                         text: edge.text.centered(at: textCenter).translated(by: frame.offset))
        isPlaced[edgeIndex] = true
    }

    /// The flat layout's routes on the page, each from its source's center to its target's through its path's inner points.
    private struct RankedRoutes {
        let nodes: ScratchSpan<LayeredFlatNode>
        let edges: ScratchSpan<LayeredSpanEdge>
        let points: ScratchSpan<CGPoint>
        let axes: FlowchartFlowAxes

        func count(of layeredIndex: Int) -> Int {
            let edge = edges[layeredIndex]
            return edge.pointStart >= 0 && edge.pointCount > 2 ? edge.pointCount : 2
        }

        /// The route's point `index` on the page, of `count`: the centers at its ends, the path's inner points between.
        func point(_ index: Int, count: Int, of layeredIndex: Int) -> CGPoint {
            let edge = edges[layeredIndex]
            let node = index == 0 ? edge.tail : index == count - 1 ? edge.head : -1
            return axes.pagePoint(node >= 0 ? CGPoint(x: nodes[node].x, y: nodes[node].y) : points[edge.pointStart + index])
        }
    }

    /// An end of a route on the side of its box that faces the route's next point along the flow, at the side's middle.
    private func end(of edgeIndex: Int, isSourceEnd: Bool, box: Int, at point: CGPoint, next: CGPoint) -> RequirementEdgePorts.End {
        let side: DiagramSide = axes.flowIsVertical ? (next.y > point.y ? .bottom : .top) : (next.x > point.x ? .right : .left)
        return RequirementEdgePorts.End(edgeIndex: Int32(edgeIndex), isSourceEnd: isSourceEnd, box: Int32(box), side: side,
                                        toward: side.isHorizontal ? next.x : next.y)
    }

    /// The loops of every box that has relations to itself, each the `loopIndex`-th of its box.
    mutating func placeSelfLoops() {
        for edgeIndex in 0..<measured.edges.count where measured.edges[edgeIndex].loopIndex >= 0 {
            let edge = measured.edges[edgeIndex]
            let box = Int(edge.source)
            let loop = RequirementSelfLoops.loop(center: centers[box], boxSize: measured.boxes[box].size, loopIndex: Int(edge.loopIndex),
                                                 flowIsVertical: axes.flowIsVertical,
                                                 startTrim: edge.isContainment ? 2 * RequirementLayoutEngine.containmentRadius : 0, textSize: edge.text.size)
            let mark: RequirementRelationMark = edge.isContainment ? .containment(point: loop.leave, towardBox: loop.intoBox)
                                                                   : .arrow(tip: loop.back, direction: loop.intoBox)
            segments.append(Self.translated(loop.curve, by: frame.offset))
            relations[edgeIndex] = RequirementPlacedRelation(kind: edge.kind, start: loop.start.translated(by: frame.offset),
                                                             firstSegment: Int32(segments.count - 1), segmentCount: 1, mark: mark.translated(by: frame.offset),
                                                             text: edge.text.centered(at: loop.textCenter).translated(by: frame.offset))
            isPlaced[edgeIndex] = true
        }
    }

    /// `segment` with each of its points moved by `offset`, as `DiagramPath.translate(by:)` moves them.
    private static func translated(_ segment: DiagramPathSegment, by offset: CGVector) -> DiagramPathSegment {
        switch segment {
        case .line(let end): .line(to: end.translated(by: offset))
        case .curve(let end, let firstControl, let secondControl):
            .curve(to: end.translated(by: offset), control1: firstControl.translated(by: offset), control2: secondControl.translated(by: offset))
        }
    }

    /// The finished layout: the boxes with their texts, the relations placed in their order, and the title.
    func finished(font: DiagramFont, title: DiagramMeasuredText?, source: [UInt8]) -> RequirementLayout {
        var boxes: [RequirementPlacedBox] = []
        boxes.reserveCapacity(measured.boxes.count)
        var fieldTexts: [DiagramMeasuredText] = []
        fieldTexts.reserveCapacity(2 * measured.rows.count)
        for box in 0..<measured.boxes.count {
            boxes.append(RequirementPlacedBoxes.placed(measured.boxes[box], at: centers[box], offset: frame.offset, measured: measured, fieldTexts: &fieldTexts))
        }
        var placedCount = 0
        for edgeIndex in 0..<isPlaced.count where isPlaced[edgeIndex] { placedCount += 1 }
        let placedRelations = [RequirementPlacedRelation](unsafeUninitializedCapacity: placedCount) { buffer, count in
            for edgeIndex in 0..<isPlaced.count where isPlaced[edgeIndex] {
                buffer.initializeElement(at: count, to: relations[edgeIndex])
                count += 1
            }
        }
        return RequirementLayout(size: frame.size, font: font, lines: measured.lines, source: source, placedBoxes: boxes, fieldTexts: fieldTexts,
                                 placedRelations: placedRelations, segments: segments, placedTitle: frame.placedTitle(title),
                                 unappliedStatementCount: measured.unappliedStatementCount)
    }
}
