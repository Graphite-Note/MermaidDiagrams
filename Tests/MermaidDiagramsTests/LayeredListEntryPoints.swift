/**
 * File: LayeredListEntryPoints.swift
 * ----------------------------------
 * Layer: Tests
 * Description: The layered layouts on lists rather than on spans of the scratch arena: the flat layout, the ranking,
 *              the compound layout and the route crossings, each copying its lists into the calling thread's arena,
 *              running there and copying back, for the tests that build their graphs as lists.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

extension LayeredFlatLayout {
    /// Lays `nodes` and `edges` out in place as `layout(nodes:edges:points:...)` does, with the calling thread's arena:
    /// each edge laid out gets its route as a list of its own.
    static func layout(nodes: inout [LayeredFlatNode], edges: inout [LayeredFlatEdge], options: LayeredFlatOptions,
                       maximumVertexCount: Int = .max) -> LayeredFlatResult? {
        DiagramScratchArena.withCurrentThread { arena in
            let nodeSpan: ScratchSpan<LayeredFlatNode> = arena.uninitializedSpan(count: nodes.count)
            for node in nodes.indices { nodeSpan[node] = nodes[node] }
            let edgeSpan: ScratchSpan<LayeredSpanEdge> = arena.uninitializedSpan(count: edges.count)
            for edgeIndex in edges.indices { edgeSpan[edgeIndex] = LayeredSpanEdge(edges[edgeIndex]) }
            var points = arena.list(capacity: 0, of: CGPoint.self)
            let result = layout(nodes: nodeSpan, edges: edgeSpan, points: &points, options: options, maximumVertexCount: maximumVertexCount,
                                arena: arena)
            for node in nodes.indices { nodes[node] = nodeSpan[node] }
            for edgeIndex in edges.indices {
                let laidOut = edgeSpan[edgeIndex]
                edges[edgeIndex].tailOffset = laidOut.tailOffset
                edges[edgeIndex].headOffset = laidOut.headOffset
                edges[edgeIndex].isReversed = laidOut.isReversed
                edges[edgeIndex].labelCenter = laidOut.labelCenter
                if laidOut.pointStart >= 0 {
                    edges[edgeIndex].points = Array(points.elements.part(laidOut.pointStart..<(laidOut.pointStart + laidOut.pointCount)))
                }
            }
            return result
        }
    }
}

extension LayeredFlatRanking {
    /// `orientAndRank` on lists, with the calling thread's arena.
    static func orientAndRank(nodes: inout [LayeredFlatNode], edges: inout [LayeredFlatEdge], step: Int) {
        DiagramScratchArena.withCurrentThread { arena in
            let nodeSpan: ScratchSpan<LayeredFlatNode> = arena.uninitializedSpan(count: nodes.count)
            for node in nodes.indices { nodeSpan[node] = nodes[node] }
            let edgeSpan: ScratchSpan<LayeredSpanEdge> = arena.uninitializedSpan(count: edges.count)
            for edgeIndex in edges.indices { edgeSpan[edgeIndex] = LayeredSpanEdge(edges[edgeIndex]) }
            orientAndRank(nodes: nodeSpan, edges: edgeSpan, step: step, arena: arena)
            for node in nodes.indices { nodes[node].rank = nodeSpan[node].rank }
            for edgeIndex in edges.indices { edges[edgeIndex].isReversed = edgeSpan[edgeIndex].isReversed }
        }
    }
}

extension LayeredCompoundLayout {
    /// Lays the graph out in place and returns its width and height, or nil when a level would need more vertices
    /// than the limit: the lists copied into the calling thread's arena, laid out there, and copied back.
    static func layout(nodes: inout [LayeredCompoundNode], edges: inout [LayeredCompoundEdge], rootDirection: LayeredDirection,
                       options: LayeredFlatOptions, maximumVertexCount: Int = .max) -> (width: Double, height: Double)? {
        DiagramScratchArena.withCurrentThread { arena in
            let nodeSpan: ScratchSpan<LayeredCompoundNode> = arena.uninitializedSpan(count: nodes.count)
            for index in nodes.indices { nodeSpan[index] = nodes[index] }
            let edgeSpan: ScratchSpan<LayeredCompoundSpanEdge> = arena.uninitializedSpan(count: edges.count)
            for index in edges.indices { edgeSpan[index] = LayeredCompoundSpanEdge(edges[index]) }
            var laidOut = LayeredCompoundLayout(nodes: nodeSpan, edges: edgeSpan, rootDirection: rootDirection, options: options,
                                                maximumVertexCount: maximumVertexCount, arena: arena)
            guard let size = layout(&laidOut) else { return nil }
            for index in nodes.indices { nodes[index] = nodeSpan[index] }
            for index in edges.indices {
                let edge = edgeSpan[index]
                edges[index].source = edge.source
                edges[index].target = edge.target
                edges[index].labelCenter = edge.labelCenter
                edges[index].route = Array(laidOut.routePoints[laidOut.routeRange(of: index)])
            }
            return size
        }
    }
}

extension LayeredRouteCrossings {
    /// `count` of edges whose routes are lists of their own, with the calling thread's arena.
    static func count(nodes: [LayeredCompoundNode], edges: [LayeredCompoundEdge], style: LayeredRouteStyle) -> Int {
        DiagramScratchArena.withCurrentThread { arena in
            let nodeSpan: ScratchSpan<LayeredCompoundNode> = arena.uninitializedSpan(count: nodes.count)
            for index in nodes.indices { nodeSpan[index] = nodes[index] }
            let edgeSpan: ScratchSpan<LayeredCompoundSpanEdge> = arena.uninitializedSpan(count: edges.count)
            var routePoints = arena.list(capacity: 0, of: LayeredRoutePoint.self)
            for (index, edge) in edges.enumerated() {
                edgeSpan[index] = LayeredCompoundSpanEdge(edge)
                edgeSpan[index].routeStart = routePoints.count
                edgeSpan[index].routeCount = edge.route.count
                for point in edge.route { routePoints.append(point) }
            }
            return count(nodes: nodeSpan, edges: edgeSpan, routePoints: routePoints.elements, style: style, arena: arena)
        }
    }
}
