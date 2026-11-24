/**
 * File: FlowchartBorderCrossings.swift
 * ------------------------------------
 * Layer: Core
 * Description: Where edges cross the boxes' borders, found by search over the route points sorted once, as points the
 *              ends at a box keep clear of, in the scratch arena.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

import CoreGraphics

/// Where edges cross the boxes' borders, by `FlowchartEdgePorts.sideKey` of the box (numbered after the nodes, from
/// `firstBoxNode`) and its side, as offsets from the side's middle: an edge that ends at a box keeps clear of them. The
/// points are sorted along each axis once and each border looks up the points on its line, so that a thousand nested
/// boxes crossed by long routes take time in proportion to what lies on their borders, not to every point by every box.
enum FlowchartBorderCrossings {
    static let tolerance: CGFloat = 0.01

    /// A point found on a box's border, before it is sorted by side.
    private struct Crossing {
        let sideKey: Int
        let point: Int
        let box: Int
        let offset: CGFloat
    }

    /// The crossings sorted by side, each side's in the order of the points' indices along the routes.
    static func crossings(routes: [LayeredClusterRoute], frames: [CGRect], firstBoxNode: Int,
                          arena: DiagramScratchArena) -> ScratchSpan<FlowchartEdgePorts.KeptPoint> {
        let frameSpan: ScratchSpan<CGRect> = arena.uninitializedSpan(count: frames.count)
        for (box, frame) in frames.enumerated() { frameSpan[box] = frame }
        return crossings(innerPoints: innerPoints(of: routes, arena: arena), frames: frameSpan, firstBoxNode: firstBoxNode, arena: arena)
    }

    /// The crossings of the routes passing `points` (between their ends) with the borders of `frames`.
    static func crossings(innerPoints points: ScratchSpan<CGPoint>, frames: ScratchSpan<CGRect>, firstBoxNode: Int,
                          arena: DiagramScratchArena) -> ScratchSpan<FlowchartEdgePorts.KeptPoint> {
        let pointCount = points.count
        let byAlong = sortedIndices(of: points, arena: arena) { first, second in first.y < second.y }
        let byAcross = sortedIndices(of: points, arena: arena) { first, second in first.x < second.x }
        // The box that last found each point, so that a point near two lines of one box counts once.
        let foundBy = arena.span(count: pointCount, repeating: -1)
        var found = arena.list(capacity: 0, of: Crossing.self)
        func add(near line: CGFloat, in sorted: ScratchSpan<Int>, isAlong: Bool, box: Int, frame: CGRect) {
            func value(_ index: Int) -> CGFloat { isAlong ? points[sorted[index]].y : points[sorted[index]].x }
            var low = 0
            var high = sorted.count
            while low < high {
                let middle = (low + high) / 2
                if value(middle) <= line - tolerance { low = middle + 1 } else { high = middle }
            }
            while low < sorted.count && value(low) < line + tolerance {
                let point = sorted[low]
                low += 1
                guard foundBy[point] != box else { continue }
                foundBy[point] = box
                guard let side = side(of: frame, at: points[point]) else { continue }
                let offset = side.isHorizontal ? points[point].x - frame.midX : points[point].y - frame.midY
                found.append(Crossing(sideKey: FlowchartEdgePorts.sideKey(node: firstBoxNode + box, side: side), point: point, box: box, offset: offset))
            }
        }
        for box in 0..<frames.count {
            let frame = frames[box]
            add(near: frame.minY, in: byAlong, isAlong: true, box: box, frame: frame)
            add(near: frame.maxY, in: byAlong, isAlong: true, box: box, frame: frame)
            add(near: frame.minX, in: byAcross, isAlong: false, box: box, frame: frame)
            add(near: frame.maxX, in: byAcross, isAlong: false, box: box, frame: frame)
        }
        var ordered = found.elements.buffer
        ordered.sort { first, second in (first.sideKey, first.point, first.box) < (second.sideKey, second.point, second.box) }
        let kept: ScratchSpan<FlowchartEdgePorts.KeptPoint> = arena.uninitializedSpan(count: found.count)
        for index in 0..<found.count { kept[index] = FlowchartEdgePorts.KeptPoint(sideKey: ordered[index].sideKey, offset: ordered[index].offset) }
        return kept
    }

    /// The points the routes pass between their ends, route after route.
    private static func innerPoints(of routes: [LayeredClusterRoute], arena: DiagramScratchArena) -> ScratchSpan<CGPoint> {
        var pointCount = 0
        for route in routes { pointCount += max(route.points.count - 2, 0) }
        let points: ScratchSpan<CGPoint> = arena.uninitializedSpan(count: pointCount)
        var next = 0
        for route in routes where route.points.count > 2 {
            for index in 1..<(route.points.count - 1) {
                points[next] = route.points[index]
                next += 1
            }
        }
        return points
    }

    /// The indices of `points` in the order `isOrdered` sorts them.
    private static func sortedIndices(of points: ScratchSpan<CGPoint>, arena: DiagramScratchArena,
                                      by isOrdered: (CGPoint, CGPoint) -> Bool) -> ScratchSpan<Int> {
        let indices: ScratchSpan<Int> = arena.uninitializedSpan(count: points.count)
        for index in 0..<points.count { indices[index] = index }
        var buffer = indices.buffer
        buffer.sort { first, second in isOrdered(points[first], points[second]) }
        return indices
    }

    /// The side of `frame` that `point` lies on, strictly between its corners, or nil.
    private static func side(of frame: CGRect, at point: CGPoint) -> DiagramSide? {
        let alongTop = point.x > frame.minX && point.x < frame.maxX
        let alongSide = point.y > frame.minY && point.y < frame.maxY
        if alongTop && abs(point.y - frame.minY) < tolerance { return .top }
        if alongTop && abs(point.y - frame.maxY) < tolerance { return .bottom }
        if alongSide && abs(point.x - frame.minX) < tolerance { return .left }
        if alongSide && abs(point.x - frame.maxX) < tolerance { return .right }
        return nil
    }
}
