/**
 * File: LanePassVertices.swift
 * ----------------------------
 * Layer: Core
 * Description: The vertices of a lane layout pass on spans of the thread's scratch arena: the ranked boxes, then a
 *              point for each rank an edge passes, crossing lanes evenly, its text on the one in the middle of its span,
 *              and the links between them in the order they are made.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics

/// The items, then each edge's passing points, as Pele's `place` adds them; every link from an upper vertex to a lower
/// one, in the order made, which is the order each vertex's neighbours are averaged in.
struct LanePassVertices {
    let vertexCount: Int
    let rank: ScratchSpan<Int>
    let lane: ScratchSpan<Int>
    let across: ScratchSpan<CGFloat>
    let along: ScratchSpan<CGFloat>
    let isPassingPoint: ScratchSpan<Bool>
    let maximumRank: Int
    let spans: ScratchSpan<Int>
    let firstPassingPoint: ScratchSpan<Int>
    let labelVertex: ScratchSpan<Int>
    let linkUppers: ScratchSpan<Int>
    let linkLowers: ScratchSpan<Int>

    init(setup: LaneLayoutItems, isPlain: ScratchSpan<Bool>, arena: DiagramScratchArena) {
        let edges = setup.edges
        let itemCount = setup.items.count
        let spans: ScratchSpan<Int> = arena.uninitializedSpan(count: edges.count)
        let (vertexCount, linkCount, isDirect) = Self.counts(setup: setup, isPlain: isPlain, spans: spans)
        self.vertexCount = vertexCount
        self.spans = spans
        rank = arena.uninitializedSpan(count: vertexCount)
        lane = arena.uninitializedSpan(count: vertexCount)
        across = arena.uninitializedSpan(count: vertexCount)
        along = arena.uninitializedSpan(count: vertexCount)
        isPassingPoint = arena.span(count: vertexCount, repeating: false)
        rank.part(0..<itemCount).copyElements(from: setup.ranks)
        lane.part(0..<itemCount).copyElements(from: setup.itemLanes)
        across.part(0..<itemCount).copyElements(from: setup.itemAcross)
        along.part(0..<itemCount).copyElements(from: setup.itemAlong)
        var highest = 0
        for item in 0..<itemCount where setup.ranks[item] > highest { highest = setup.ranks[item] }
        maximumRank = highest
        firstPassingPoint = arena.span(count: edges.count, repeating: -1)
        labelVertex = arena.span(count: edges.count, repeating: -1)
        linkUppers = arena.uninitializedSpan(count: linkCount)
        linkLowers = arena.uninitializedSpan(count: linkCount)
        var nextVertex = itemCount
        var nextLink = 0
        for edgeIndex in 0..<edges.count {
            let edge = edges[edgeIndex]
            if isDirect || spans[edgeIndex] < 2 || isPlain[edgeIndex] {
                link(edge.upper, edge.lower, at: &nextLink)
            } else {
                addPassingPoints(of: edgeIndex, edge: edge, step: setup.step, vertex: &nextVertex, link: &nextLink)
            }
        }
    }

    /// Each ranked edge's span, how many vertices and links the pass has, and whether every edge is laid out direct for
    /// want of room for its passing points.
    private static func counts(setup: LaneLayoutItems, isPlain: ScratchSpan<Bool>, spans: ScratchSpan<Int>) -> (vertices: Int, links: Int, isDirect: Bool) {
        let edges = setup.edges
        var passingPointCount = 0
        for edgeIndex in 0..<edges.count {
            spans[edgeIndex] = abs(setup.ranks[edges[edgeIndex].head] - setup.ranks[edges[edgeIndex].tail])
            if !isPlain[edgeIndex] { passingPointCount += spans[edgeIndex] - 1 }
        }
        let isDirect = passingPointCount > LanePass.maximumPassingPointCount
        var vertexCount = setup.items.count
        var linkCount = 0
        for edgeIndex in 0..<edges.count {
            if isDirect || spans[edgeIndex] < 2 || isPlain[edgeIndex] {
                linkCount += 1
            } else {
                vertexCount += spans[edgeIndex] - 1
                linkCount += spans[edgeIndex]
            }
        }
        return (vertexCount, linkCount, isDirect)
    }

    @inline(__always)
    private func link(_ upper: Int, _ lower: Int, at next: inout Int) {
        linkUppers[next] = upper
        linkLowers[next] = lower
        next += 1
    }

    /// A point in each rank between the edge's ends, crossing from its first lane to its last evenly along the way.
    private func addPassingPoints(of edgeIndex: Int, edge: LaneRankedEdge, step: Int, vertex nextVertex: inout Int, link nextLink: inout Int) {
        let upperRank = rank[edge.upper]
        let lowerRank = rank[edge.lower]
        var labelRank = -1
        if edge.hasLabel {
            labelRank = upperRank + (lowerRank - upperRank) / 2
            if step == 2, labelRank.isMultiple(of: 2) { labelRank -= 1 }
        }
        firstPassingPoint[edgeIndex] = nextVertex
        var previous = edge.upper
        for passingRank in (upperRank + 1)..<lowerRank {
            let vertex = nextVertex
            nextVertex += 1
            let share = CGFloat((lane[edge.lower] - lane[edge.upper]) * (passingRank - upperRank)) / CGFloat(lowerRank - upperRank)
            rank[vertex] = passingRank
            lane[vertex] = lane[edge.upper] + Int((share + 0.5).rounded(.down))
            isPassingPoint[vertex] = true
            across[vertex] = passingRank == labelRank ? edge.labelAcross : 0
            along[vertex] = passingRank == labelRank ? edge.labelAlong : 0
            if passingRank == labelRank { labelVertex[edgeIndex] = vertex }
            link(previous, vertex, at: &nextLink)
            previous = vertex
        }
        link(previous, edge.lower, at: &nextLink)
    }
}
