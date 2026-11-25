/**
 * File: ReferenceEntityRelationshipClusterPlacement.swift
 * -------------------------------------------------------
 * Layer: Tests
 * Description: The 0.7.0 EntityRelationshipClusterPlacement kept as the reference the 0.8.0 layout is checked against:
 *              puts an entity relationship diagram laid out in its groups' boxes on the page: boxes, relationships, groups.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

extension ReferenceEntityRelationshipPageAssembly {
    /// The entities at their centers on the page; an entity that stands for a group at the center of the group's box.
    mutating func placeBoxes(clustered: ReferenceEntityRelationshipClusterGraph, placement: LayeredClusterPlacement) {
        representedSubgraphs = clustered.representedSubgraphs
        for (entity, subgraph) in clustered.representedSubgraphs.enumerated() {
            if let subgraph { representedBoxSizes[entity] = placement.clusterFrames[subgraph].size }
        }
        boxCenters = diagram.entities.indices.map { entity in
            if let subgraph = clustered.representedSubgraphs[entity] {
                let frame = placement.clusterFrames[subgraph]
                return CGPoint(x: frame.midX, y: frame.midY)
            }
            return placement.nodeCenters[clustered.layoutNodeIndices[entity] ?? 0]
        }
    }

    /// The relationships along their routes on the page: each end on the side of its box (or group's box) its route
    /// leaves or arrives by, spread along it with the others there, running straight for a mark's length; a
    /// relationship between a group and an entity inside it straight from one center to the other, as Pele draws it.
    mutating func placeRelationships(clustered: ReferenceEntityRelationshipClusterGraph, placement: LayeredClusterPlacement) {
        var ends: [ReferenceEntityRelationshipEdgePorts.End] = []
        for (layoutIndex, index) in clustered.layoutRelationshipIndices.enumerated() where !placement.strayEdgeIndices.contains(layoutIndex) {
            let relationship = diagram.relationships[index]
            let route = placement.edgeRoutes[layoutIndex]
            ends.append(Self.routeEnd(of: route, relationshipIndex: index, isFirstEntityEnd: true, entity: relationship.firstEntityIndex))
            ends.append(Self.routeEnd(of: route, relationshipIndex: index, isFirstEntityEnd: false, entity: relationship.secondEntityIndex))
        }
        let sizes = diagram.entities.indices.map { entity in
            clustered.representedSubgraphs[entity].map { subgraph in placement.clusterFrames[subgraph].size } ?? measured.boxes[entity].size
        }
        let ports = ReferenceEntityRelationshipEdgePorts(ends: ends, relationshipCount: diagram.relationships.count, boxCenters: boxCenters, boxSizes: sizes)
        var sidesByEnd: [Int: DiagramSide] = [:]
        for end in ends { sidesByEnd[2 * end.relationshipIndex + (end.isFirstEntityEnd ? 0 : 1)] = end.side }
        for (layoutIndex, index) in clustered.layoutRelationshipIndices.enumerated() {
            let route = placement.edgeRoutes[layoutIndex]
            let labelCenter = placement.edgeLabelCenters[layoutIndex]
            guard !placement.strayEdgeIndices.contains(layoutIndex) else {
                placeStrayRelationship(at: index, along: route.points, labelCenter: labelCenter ?? route.points[0])
                continue
            }
            guard let start = ports.firstEntityPoints[index], let end = ports.secondEntityPoints[index],
                  let startSide = sidesByEnd[2 * index], let endSide = sidesByEnd[2 * index + 1] else { continue }
            let interior = Array(route.points.dropFirst().dropLast())
            relationshipPoints.append([start] + interior + [end])
            let straight = EntityRelationshipCardinalityMark.length
            let leaving = ReferenceEntityRelationshipEdgePorts.outward(from: startSide)
            let arriving = ReferenceEntityRelationshipEdgePorts.outward(from: endSide)
            let points = [start, CGPoint(x: start.x + leaving.dx * straight, y: start.y + leaving.dy * straight)] + interior
                + [CGPoint(x: end.x + arriving.dx * straight, y: end.y + arriving.dy * straight), end]
            let axes = [startSide.isHorizontal] + route.segmentsRunVertically + [endSide.isHorizontal]
            setRelationship(at: index, along: points, segmentsRunVertically: axes,
                            labelCenter: labelCenter ?? CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2))
        }
    }

    /// A relationship between a group and an entity inside it, from one center to the other as Pele's compound layout
    /// routes it, an S down the page: unless the ends are in line or close, it runs straight down or up for a mark's
    /// length at each end before it curves, as Pele's renderer stubs every relationship, so that each mark sits on a straight run.
    private mutating func placeStrayRelationship(at index: Int, along points: [CGPoint], labelCenter: CGPoint) {
        guard let start = points.first, let end = points.last, points.count == 2 else {
            setRelationship(at: index, along: points, segmentsRunVertically: Array(repeating: true, count: max(points.count - 1, 1)), labelCenter: labelCenter)
            return
        }
        let isDirect = abs(start.x - end.x) < 0.01 || abs(start.y - end.y) < 0.01 || hypot(end.x - start.x, end.y - start.y) <= Self.shortestRouteWithStraightRuns
        guard !isDirect else {
            setRelationship(at: index, along: points, segmentsRunVertically: [true], labelCenter: labelCenter)
            return
        }
        let down: CGFloat = end.y >= start.y ? 1 : -1
        let straight = EntityRelationshipCardinalityMark.length
        setRelationship(at: index, along: [start, CGPoint(x: start.x, y: start.y + down * straight), CGPoint(x: end.x, y: end.y - down * straight), end],
                        segmentsRunVertically: [true, true, true], labelCenter: labelCenter)
    }

    /// An end of a route through boxes: the side of its box its first or last segment leaves or arrives by, along that
    /// segment's flow, and where across that side the route goes next.
    private static func routeEnd(of route: LayeredClusterRoute, relationshipIndex: Int, isFirstEntityEnd: Bool, entity: Int) -> ReferenceEntityRelationshipEdgePorts.End {
        let points = route.points
        let end = isFirstEntityEnd ? points[0] : points[points.count - 1]
        let next = isFirstEntityEnd ? points[1] : points[points.count - 2]
        let runsVertically = isFirstEntityEnd ? route.segmentsRunVertically[0] : route.segmentsRunVertically[route.segmentsRunVertically.count - 1]
        let side: DiagramSide = runsVertically ? (next.y > end.y ? .bottom : .top) : (next.x > end.x ? .right : .left)
        return ReferenceEntityRelationshipEdgePorts.End(relationshipIndex: relationshipIndex, isFirstEntityEnd: isFirstEntityEnd, entity: entity, side: side,
                                               neighborAcross: side.isHorizontal ? next.x : next.y)
    }

    /// The groups' boxes, each title along its box's top where the relationships leave it room; Pele's titles are never
    /// struck through.
    mutating func placeSubgraphs(clustered: ReferenceEntityRelationshipClusterGraph, placement: LayeredClusterPlacement) {
        let crossings = FlowchartRoutePointIndex(relationshipPoints)
        subgraphBoxes = placement.clusterFrames.enumerated().map { index, frame in
            let title = clustered.titles[index].map { title in FlowchartClusterTitles.placed(title, in: frame, crossings: crossings).title }
            return FlowchartLayoutCluster(frame: frame, title: title, depth: clustered.depths[index], isTitleCrossed: false)
        }
    }
}
