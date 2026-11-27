/**
 * File: EntityRelationshipRankedPlacement.swift
 * ---------------------------------------------
 * Layer: Core
 * Description: The relationships of an entity relationship diagram laid out in ranks placed along their routes: ends
 *              spread along their boxes' sides, each route straightened and given its straight runs in a list of the
 *              thread's arena, then drawn into the layout's segments.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 26/11/2026
 */

import CoreGraphics
import Foundation

extension EntityRelationshipPageAssembly {
    /// The relationships between two different entities, along their routes. `layeredIndices[i]` is the relationship of
    /// the flat layout's `i`-th edge, whose route runs from its first entity's center to its second's through its
    /// path's inner points.
    mutating func placeRelationships(layeredIndices: ScratchSpan<Int>, nodes: ScratchSpan<LayeredFlatNode>, edges laidOut: ScratchSpan<LayeredSpanEdge>,
                                     points: ScratchSpan<CGPoint>) {
        let routes = EntityRelationshipRankedRoutes(nodes: nodes, edges: laidOut, points: points)
        let ends = rankedEnds(layeredIndices: layeredIndices, routes: routes)
        let boxSizes: ScratchSpan<CGSize> = arena.uninitializedSpan(count: measured.boxes.count)
        var longest = 2
        for box in 0..<measured.boxes.count { boxSizes[box] = measured.boxes[box].size }
        for layeredIndex in 0..<layeredIndices.count { longest = max(longest, routes.count(of: layeredIndex)) }
        let ports = EntityRelationshipEdgePorts(ends: ends, relationshipCount: relationshipRecords.count, boxCenters: boxCenters, boxSizes: boxSizes,
                                                arena: arena)
        // Room for a route and the two straight runs' points `relationship(at:along:)` adds.
        let routed: ScratchSpan<CGPoint> = arena.uninitializedSpan(count: longest + 2)
        for layeredIndex in 0..<layeredIndices.count {
            let index = layeredIndices[layeredIndex]
            guard ports.isFirstPlaced[index], ports.isSecondPlaced[index] else { continue }
            let start = ports.firstEntityPoints[index]
            let end = ports.secondEntityPoints[index]
            let count = routes.count(of: layeredIndex)
            routed[0] = start
            for pointIndex in 1..<(count - 1) { routed[pointIndex] = axes.pagePoint(routes.point(pointIndex, count: count, of: layeredIndex)) }
            routed[count - 1] = end
            let edge = laidOut[layeredIndex]
            let labelCenter = edge.labelWidth > 0 ? axes.pagePoint(edge.labelCenter) : CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
            placeRouted(at: index, routed: routed, count: count, leaving: EntityRelationshipEdgePorts.outward(from: ends[2 * layeredIndex].side),
                        arriving: EntityRelationshipEdgePorts.outward(from: ends[2 * layeredIndex + 1].side), labelCenter: labelCenter)
        }
    }

    /// The two ends of each route on the sides of their boxes facing it, the first entity's then the second's.
    private func rankedEnds(layeredIndices: ScratchSpan<Int>, routes: EntityRelationshipRankedRoutes) -> ScratchSpan<EntityRelationshipEdgePorts.End> {
        let ends: ScratchSpan<EntityRelationshipEdgePorts.End> = arena.uninitializedSpan(count: 2 * layeredIndices.count)
        for layeredIndex in 0..<layeredIndices.count {
            let index = layeredIndices[layeredIndex]
            let count = routes.count(of: layeredIndex)
            let first = routes.point(0, count: count, of: layeredIndex)
            let second = routes.point(1, count: count, of: layeredIndex)
            let beforeLast = routes.point(count - 2, count: count, of: layeredIndex)
            let last = routes.point(count - 1, count: count, of: layeredIndex)
            let relationship = relationshipRecords[index]
            ends[2 * layeredIndex] = EntityRelationshipEdgePorts.End(relationshipIndex: Int32(index), isFirstEntityEnd: true, entity: relationship.firstEntityIndex,
                                                                     side: second.y > first.y ? axes.downstreamSide : axes.upstreamSide, neighborAcross: second.x)
            ends[2 * layeredIndex + 1] = EntityRelationshipEdgePorts.End(relationshipIndex: Int32(index), isFirstEntityEnd: false,
                                                                         entity: relationship.secondEntityIndex,
                                                                         side: beforeLast.y < last.y ? axes.upstreamSide : axes.downstreamSide,
                                                                         neighborAcross: beforeLast.x)
        }
        return ends
    }

    /// A relationship along the first `count` points of `routed`, from the first box's side to the second's. `leaving`
    /// and `arriving` point out of the two boxes; the line runs along them for a mark's length before it curves, so that
    /// each mark sits on a straight run. The route is straightened and given its straight runs where it stands, in the
    /// room `routed` keeps beyond `count`.
    private mutating func placeRouted(at index: Int, routed: ScratchSpan<CGPoint>, count: Int, leaving: CGVector, arriving: CGVector, labelCenter: CGPoint) {
        let first = routed[0]
        let last = routed[count - 1]
        var keptCount = Self.straighten(routed, count: count)
        let isDirect = keptCount == 2 && (EntityRelationshipRouteSegments.isInLine(first, last)
            || hypot(last.x - first.x, last.y - first.y) <= Self.shortestRouteWithStraightRuns)
        if !isDirect {
            let straight = EntityRelationshipCardinalityMark.length
            // The kept points from the second on move one along for the first straight run's end; the last moves two.
            var position = keptCount - 1
            while position >= 1 {
                routed[position + 1] = routed[position]
                position -= 1
            }
            routed[1] = CGPoint(x: first.x + leaving.dx * straight, y: first.y + leaving.dy * straight)
            keptCount += 1
            routed[keptCount] = routed[keptCount - 1]
            routed[keptCount - 1] = CGPoint(x: last.x + arriving.dx * straight, y: last.y + arriving.dy * straight)
            keptCount += 1
        }
        setRelationship(at: index, along: routed.part(0..<keptCount), segmentAxes: nil, labelCenter: labelCenter)
    }

    /// The route without each point that lies between its neighbours on one straight vertical or horizontal run, so
    /// that a relationship whose route runs straight is one straight line; the points kept move to the front, and their
    /// count is returned. A point is compared with the last one kept and with the next one, as yet unmoved.
    private static func straighten(_ points: ScratchSpan<CGPoint>, count: Int) -> Int {
        var keptCount = 1
        for index in 1..<count {
            let point = points[index]
            if index + 1 < count {
                let previous = points[keptCount - 1]
                let next = points[index + 1]
                let isOnVerticalRun = abs(previous.x - point.x) < 0.01 && abs(point.x - next.x) < 0.01
                let isOnHorizontalRun = abs(previous.y - point.y) < 0.01 && abs(point.y - next.y) < 0.01
                if isOnVerticalRun || isOnHorizontalRun { continue }
            }
            points[keptCount] = point
            keptCount += 1
        }
        return keptCount
    }
}

/// The flat layout's routes in flow space, each from its first entity's center to its second's through its path's
/// inner points.
struct EntityRelationshipRankedRoutes {
    let nodes: ScratchSpan<LayeredFlatNode>
    let edges: ScratchSpan<LayeredSpanEdge>
    let points: ScratchSpan<CGPoint>

    func count(of layeredIndex: Int) -> Int {
        let edge = edges[layeredIndex]
        return edge.pointStart >= 0 && edge.pointCount > 2 ? edge.pointCount : 2
    }

    /// The route's point `index`, of `count`: the centers at its ends, the path's inner points between.
    func point(_ index: Int, count: Int, of layeredIndex: Int) -> CGPoint {
        let edge = edges[layeredIndex]
        if index == 0 { return CGPoint(x: nodes[edge.tail].x, y: nodes[edge.tail].y) }
        if index == count - 1 { return CGPoint(x: nodes[edge.head].x, y: nodes[edge.head].y) }
        return points[edge.pointStart + index]
    }
}
