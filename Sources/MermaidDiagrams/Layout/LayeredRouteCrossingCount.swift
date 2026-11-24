/**
 * File: LayeredRouteCrossingCount.swift
 * -------------------------------------
 * Layer: Core
 * Description: Counts the pairs of route pieces that cross, band by band down the page, for Pele's compound layout.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

import Foundation

extension LayeredRouteCrossings {
    /// The pieces in about the square root of their count of bands down the page, each pair counted only in the first
    /// band both are in; within a band, the pieces sorted by their left ends, so that the pairs to try are those that
    /// overlap across.
    static func countCrossings(_ segments: LayeredRouteSegments, nodes: [LayeredCompoundNode], edges: [LayeredCompoundEdge], runs: LayeredRouteEndRuns,
                               arena: DiagramScratchArena) -> Int {
        let count = segments.count
        let hasHeight = segments.bottom > segments.top
        let bands = hasHeight ? Int((Double(count).squareRoot() + 0.5).rounded(.down)) : 1
        let scale = hasHeight ? Double(bands) / (segments.bottom - segments.top) : 0
        func band(of along: Double) -> Int {
            let scaled = ((along - segments.top) * scale).rounded(.down)
            return scaled.isFinite ? max(0, min(bands - 1, Int(scaled))) : 0
        }
        let firstBand = arena.span(count: count, repeating: 0)
        let bandStart = arena.span(count: bands + 1, repeating: 0)
        for segment in 0..<count {
            firstBand[segment] = band(of: segments.low[segment])
            for index in firstBand[segment]...max(firstBand[segment], band(of: segments.high[segment])) { bandStart[index + 1] += 1 }
        }
        for index in 0..<bands { bandStart[index + 1] += bandStart[index] }
        let fill = arena.copy(of: bandStart.part(0..<bands))
        let inBand = arena.span(count: bandStart[bands], repeating: 0)
        for segment in 0..<count {
            for index in firstBand[segment]...max(firstBand[segment], band(of: segments.high[segment])) {
                inBand[fill[index]] = segment
                fill[index] += 1
            }
        }
        var total = 0
        for index in 0..<bands {
            // Each band's members sorted in place: the band's list is read by no other band.
            let members = inBand.part(bandStart[index]..<bandStart[index + 1])
            let startX = segments.startX
            members.sortStably(in: arena) { first, second in
                (startX[first] != startX[second] ? startX[first] - startX[second] : Double(first - second)) < 0
            }
            total += crossingsInBand(members, band: index, firstBand: firstBand, segments: segments, nodes: nodes, edges: edges, runs: runs)
        }
        return total
    }

    private static func crossingsInBand(_ members: ScratchSpan<Int>, band: Int, firstBand: ScratchSpan<Int>, segments: LayeredRouteSegments,
                                        nodes: [LayeredCompoundNode], edges: [LayeredCompoundEdge], runs: LayeredRouteEndRuns) -> Int {
        var total = 0
        for (position, first) in members.enumerated() {
            let isHere = firstBand[first] == band
            for second in members.part((position + 1)..<members.count) {
                if segments.startX[second] > segments.endX[first] { break }
                if segments.high[second] < segments.low[first] || segments.low[second] > segments.high[first] || segments.owner[first] == segments.owner[second]
                    || (!isHere && firstBand[second] != band) { continue }
                if crosses(first, second, segments: segments, nodes: nodes, edges: edges, runs: runs) { total += 1 }
            }
        }
        return total
    }

    /// Whether two pieces cross, points on a line counted on one side; not where two edges fan in or out at a node
    /// they share (near it, at their first or last pieces, or on the runs of their ends).
    private static func crosses(_ first: Int, _ second: Int, segments: LayeredRouteSegments, nodes: [LayeredCompoundNode],
                                edges: [LayeredCompoundEdge], runs: LayeredRouteEndRuns) -> Bool {
        let deltaX = segments.endX[first] - segments.startX[first]
        let deltaY = segments.endY[first] - segments.startY[first]
        let side1 = deltaX * (segments.startY[second] - segments.startY[first]) - deltaY * (segments.startX[second] - segments.startX[first])
        let side2 = deltaX * (segments.endY[second] - segments.startY[first]) - deltaY * (segments.endX[second] - segments.startX[first])
        if (side1 > 0) == (side2 > 0) { return false }
        let otherX = segments.endX[second] - segments.startX[second]
        let otherY = segments.endY[second] - segments.startY[second]
        let side3 = otherX * (segments.startY[first] - segments.startY[second]) - otherY * (segments.startX[first] - segments.startX[second])
        let side4 = otherX * (segments.endY[first] - segments.startY[second]) - otherY * (segments.endX[first] - segments.startX[second])
        if (side3 > 0) == (side4 > 0) { return false }
        let at = side3 / (side3 - side4)
        let x = segments.startX[first] + at * deltaX
        let y = segments.startY[first] + at * deltaY
        let firstEdge = edges[segments.owner[first]]
        let secondEdge = edges[segments.owner[second]]
        func fans(at node: Int, _ firstEnd: UInt8, _ secondEnd: UInt8) -> Bool {
            (segments.ends[first] & firstEnd != 0 && segments.ends[second] & secondEnd != 0)
                || (abs(x - nodes[node].x) < nodes[node].width / 2 + LayeredCompoundConstants.fanDistance
                    && abs(y - nodes[node].y) < nodes[node].height / 2 + LayeredCompoundConstants.fanDistance)
                || (isOnRun(runs, edge: segments.owner[first], end: firstEnd, x: x, y: y)
                    && isOnRun(runs, edge: segments.owner[second], end: secondEnd, x: x, y: y))
        }
        if firstEdge.source == secondEdge.source && fans(at: firstEdge.source, 1, 1) { return false }
        if firstEdge.source == secondEdge.target && fans(at: firstEdge.source, 1, 2) { return false }
        if firstEdge.target == secondEdge.source && fans(at: firstEdge.target, 2, 1) { return false }
        if firstEdge.target == secondEdge.target && fans(at: firstEdge.target, 2, 2) { return false }
        return true
    }
}
