/**
 * File: EntityRelationshipClusterPlacement.swift
 * ----------------------------------------------
 * Layer: Core
 * Description: Puts an entity relationship diagram laid out in its groups' boxes on the page: boxes, relationships,
 *              groups, each route read where the compound layout keeps it and given its straight runs in a list of the
 *              thread's arena.
 *
 * Authors: Bahey Shalash
 * Version: 0.8
 * Date: 26/11/2026
 */

import CoreGraphics
import Foundation

extension EntityRelationshipPageAssembly {
    /// The entities at their centers on the page; an entity that stands for a group at the center of the group's box.
    mutating func placeBoxes(clustered: EntityRelationshipClusterGraph, nesting: EntityRelationshipNesting, compound: LayeredCompoundLayout) {
        representedSubgraphs = nesting.representedSubgraphs
        let nodeCount = clustered.graph.nodeCount
        representedBoxSizes = arena.uninitializedSpan(count: entityCount)
        boxCenters = arena.uninitializedSpan(count: entityCount)
        for entity in 0..<entityCount {
            let subgraph = Int(representedSubgraphs[entity])
            if subgraph >= 0 {
                let frame = compound.nodes[nodeCount + subgraph].frame
                representedBoxSizes[entity] = frame.size
                boxCenters[entity] = CGPoint(x: frame.midX, y: frame.midY)
            } else {
                let node = compound.nodes[max(Int(clustered.layoutNodeIndices[entity]), 0)]
                boxCenters[entity] = CGPoint(x: node.x, y: node.y)
            }
        }
    }

    /// The relationships along their routes on the page: each end on the side of its box (or group's box) its route
    /// leaves or arrives by, spread along it with the others there, running straight for a mark's length; a
    /// relationship between a group and an entity inside it straight from one center to the other, as Pele draws it.
    mutating func placeRelationships(clustered: EntityRelationshipClusterGraph, compound: LayeredCompoundLayout) {
        let layoutCount = clustered.layoutRelationshipIndices.count
        var longest = 2
        for layoutIndex in 0..<layoutCount { longest = max(longest, compound.routeRange(of: layoutIndex).count) }
        let ports = routedPorts(clustered: clustered, compound: compound)
        let points: ScratchSpan<CGPoint> = arena.uninitializedSpan(count: longest + 2)
        let segmentAxes: ScratchSpan<Bool> = arena.uninitializedSpan(count: longest + 1)
        relationshipPoints.reserveCapacity(2 * layoutCount)
        for layoutIndex in 0..<layoutCount {
            let index = clustered.layoutRelationshipIndices[layoutIndex]
            let range = compound.routeRange(of: layoutIndex)
            let labelCenter = compound.labelCenter(of: layoutIndex)
            guard !compound.isStray(layoutIndex) else {
                placeStrayRelationship(at: index, route: range, of: compound, labelCenter: labelCenter ?? compound.routePoints[range.lowerBound].point,
                                       points: points, segmentAxes: segmentAxes)
                continue
            }
            guard ports.isFirstPlaced[index], ports.isSecondPlaced[index] else { continue }
            let start = ports.firstEntityPoints[index]
            let end = ports.secondEntityPoints[index]
            relationshipPoints.append(start)
            for position in (range.lowerBound + 1)..<(range.upperBound - 1) { relationshipPoints.append(compound.routePoints[position].point) }
            relationshipPoints.append(end)
            let count = Self.stubbed(range, of: compound, start: start, startSide: ports.firstSides[index], end: end, endSide: ports.secondSides[index],
                                     points: points, segmentAxes: segmentAxes)
            setRelationship(at: index, along: points.part(0..<count), segmentAxes: segmentAxes.part(0..<(count - 1)),
                            labelCenter: labelCenter ?? CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2))
        }
    }

    /// The ends of the routes between two boxes (not a group's and what it holds) on their boxes' sides, spread along them.
    private func routedPorts(clustered: EntityRelationshipClusterGraph, compound: LayeredCompoundLayout) -> EntityRelationshipEdgePorts {
        let layoutCount = clustered.layoutRelationshipIndices.count
        var ends = arena.list(capacity: 2 * layoutCount, of: EntityRelationshipEdgePorts.End.self)
        for layoutIndex in 0..<layoutCount where !compound.isStray(layoutIndex) {
            let index = clustered.layoutRelationshipIndices[layoutIndex]
            let relationship = relationshipRecords[index]
            ends.append(Self.routeEnd(of: layoutIndex, in: compound, relationshipIndex: index, isFirstEntityEnd: true, entity: relationship.firstEntityIndex))
            ends.append(Self.routeEnd(of: layoutIndex, in: compound, relationshipIndex: index, isFirstEntityEnd: false, entity: relationship.secondEntityIndex))
        }
        let nodeCount = clustered.graph.nodeCount
        let sizes: ScratchSpan<CGSize> = arena.uninitializedSpan(count: entityCount)
        for entity in 0..<entityCount {
            let subgraph = Int(representedSubgraphs[entity])
            sizes[entity] = subgraph >= 0 ? compound.nodes[nodeCount + subgraph].frame.size : measured.boxes[entity].size
        }
        return EntityRelationshipEdgePorts(ends: ends.elements, relationshipCount: relationshipRecords.count, boxCenters: boxCenters, boxSizes: sizes,
                                           arena: arena)
    }

    /// A route through boxes from `start` to `end` through its inner points, running straight out of each box for a
    /// mark's length, written into `points`, and each segment's flow into `segmentAxes`: the straight runs' across their
    /// sides, the others the route's. Returns how many points it has.
    private static func stubbed(_ range: Range<Int>, of compound: LayeredCompoundLayout, start: CGPoint, startSide: DiagramSide, end: CGPoint,
                                endSide: DiagramSide, points: ScratchSpan<CGPoint>, segmentAxes: ScratchSpan<Bool>) -> Int {
        let straight = EntityRelationshipCardinalityMark.length
        let leaving = EntityRelationshipEdgePorts.outward(from: startSide)
        let arriving = EntityRelationshipEdgePorts.outward(from: endSide)
        var count = 0
        points[count] = start
        points[count + 1] = CGPoint(x: start.x + leaving.dx * straight, y: start.y + leaving.dy * straight)
        count += 2
        for position in (range.lowerBound + 1)..<(range.upperBound - 1) {
            points[count] = compound.routePoints[position].point
            count += 1
        }
        points[count] = CGPoint(x: end.x + arriving.dx * straight, y: end.y + arriving.dy * straight)
        points[count + 1] = end
        count += 2
        var axisCount = 0
        segmentAxes[axisCount] = startSide.isHorizontal
        axisCount += 1
        for position in (range.lowerBound + 1)..<range.upperBound {
            segmentAxes[axisCount] = !compound.routePoints[position].runsHorizontally
            axisCount += 1
        }
        segmentAxes[axisCount] = endSide.isHorizontal
        return count
    }

    /// A relationship between a group and an entity inside it, from one center to the other as Pele's compound layout
    /// routes it, an S down the page: unless the ends are in line or close, it runs straight down or up for a mark's
    /// length at each end before it curves, as Pele's renderer stubs every relationship, so that each mark sits on a straight run.
    private mutating func placeStrayRelationship(at index: Int, route range: Range<Int>, of compound: LayeredCompoundLayout, labelCenter: CGPoint,
                                                 points: ScratchSpan<CGPoint>, segmentAxes: ScratchSpan<Bool>) {
        for position in range { points[position - range.lowerBound] = compound.routePoints[position].point }
        guard range.count == 2 else {
            let axisCount = max(range.count - 1, 1)
            for position in 0..<axisCount { segmentAxes[position] = true }
            setRelationship(at: index, along: points.part(0..<range.count), segmentAxes: segmentAxes.part(0..<axisCount), labelCenter: labelCenter)
            return
        }
        let start = points[0]
        let end = points[1]
        let isDirect = abs(start.x - end.x) < 0.01 || abs(start.y - end.y) < 0.01 || hypot(end.x - start.x, end.y - start.y) <= Self.shortestRouteWithStraightRuns
        guard !isDirect else {
            segmentAxes[0] = true
            setRelationship(at: index, along: points.part(0..<2), segmentAxes: segmentAxes.part(0..<1), labelCenter: labelCenter)
            return
        }
        let down: CGFloat = end.y >= start.y ? 1 : -1
        let straight = EntityRelationshipCardinalityMark.length
        points[1] = CGPoint(x: start.x, y: start.y + down * straight)
        points[2] = CGPoint(x: end.x, y: end.y - down * straight)
        points[3] = end
        for position in 0..<3 { segmentAxes[position] = true }
        setRelationship(at: index, along: points.part(0..<4), segmentAxes: segmentAxes.part(0..<3), labelCenter: labelCenter)
    }

    /// An end of laid-out edge `layoutIndex`'s route through boxes: the side of its box its first or last segment leaves or
    /// arrives by, along that segment's flow, and where across that side the route goes next.
    private static func routeEnd(of layoutIndex: Int, in compound: LayeredCompoundLayout, relationshipIndex: Int, isFirstEntityEnd: Bool,
                                 entity: Int32) -> EntityRelationshipEdgePorts.End {
        let range = compound.routeRange(of: layoutIndex)
        let end = compound.routePoints[isFirstEntityEnd ? range.lowerBound : range.upperBound - 1].point
        let next = compound.routePoints[isFirstEntityEnd ? range.lowerBound + 1 : range.upperBound - 2].point
        let runsVertically = !compound.routePoints[isFirstEntityEnd ? range.lowerBound + 1 : range.upperBound - 1].runsHorizontally
        let side: DiagramSide = runsVertically ? (next.y > end.y ? .bottom : .top) : (next.x > end.x ? .right : .left)
        return EntityRelationshipEdgePorts.End(relationshipIndex: Int32(relationshipIndex), isFirstEntityEnd: isFirstEntityEnd, entity: entity, side: side,
                                               neighborAcross: side.isHorizontal ? next.x : next.y)
    }

    /// The groups' boxes, each title along its box's top where the relationships leave it room; Pele's titles are never
    /// struck through.
    mutating func placeSubgraphs(clustered: EntityRelationshipClusterGraph, nesting: EntityRelationshipNesting, compound: LayeredCompoundLayout) {
        // The points the relationships pass, sorted down the page once, as the route point index sorts them.
        let crossings = relationshipPoints.elements
        var sortedBuffer = crossings.buffer
        sortedBuffer.sort { first, second in first.y < second.y }
        let nodeCount = clustered.graph.nodeCount
        subgraphBoxes = (0..<clustered.graph.boxCount).map { index in
            let frame = compound.nodes[nodeCount + index].frame
            let title = clustered.titles[index].map { title in FlowchartClusterTitles.placed(title, in: frame, sortedPoints: crossings).title }
            return FlowchartLayoutCluster(frame: frame, title: title, depth: nesting.depths[index], isTitleCrossed: false)
        }
    }
}
