/**
 * File: ReferenceFlowchartBorderCrossings.swift
 * ---------------------------------------------
 * Layer: Tests
 * Description: The 0.7.0 FlowchartBorderCrossings kept as the reference the 0.8.0 flowchart layout is checked against:
 *              where the edges of a flowchart laid out in boxes cross the boxes' borders, found by sorted search.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// Where edges cross the boxes' borders, by `ReferenceFlowchartEdgePorts.sideKey` of the box (numbered after the nodes, from
/// `firstBoxNode`) and its side, as offsets from the side's middle: an edge that ends at a box keeps clear of them. The
/// points are sorted along each axis once and each border looks up the points on its line, so that a thousand nested
/// boxes crossed by long routes take time in proportion to what lies on their borders, not to every point by every box.
enum ReferenceFlowchartBorderCrossings {
    static let tolerance: CGFloat = 0.01

    static func crossings(routes: [LayeredClusterRoute], frames: [CGRect], firstBoxNode: Int) -> [Int: [CGFloat]] {
        let points = routes.flatMap { route in route.points.dropFirst().dropLast() }
        let byAlong = points.indices.sorted { first, second in points[first].y < points[second].y }
        let byAcross = points.indices.sorted { first, second in points[first].x < points[second].x }
        var pairs: [(point: Int, box: Int)] = []
        for (box, frame) in frames.enumerated() {
            var found = Set<Int>()
            for line in [frame.minY, frame.maxY] { found.formUnion(near(line, in: byAlong) { index in points[index].y }) }
            for line in [frame.minX, frame.maxX] { found.formUnion(near(line, in: byAcross) { index in points[index].x }) }
            pairs += found.map { point in (point, box) }
        }
        pairs.sort { first, second in first.point != second.point ? first.point < second.point : first.box < second.box }
        var crossings: [Int: [CGFloat]] = [:]
        for (pointIndex, box) in pairs {
            let point = points[pointIndex]
            let frame = frames[box]
            guard let side = side(of: frame, at: point) else { continue }
            let offset = side.isHorizontal ? point.x - frame.midX : point.y - frame.midY
            crossings[ReferenceFlowchartEdgePorts.sideKey(node: firstBoxNode + box, side: side), default: []].append(offset)
        }
        return crossings
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

    /// The indices in `sorted` whose `value` is within the tolerance of `line`.
    private static func near(_ line: CGFloat, in sorted: [Int], value: (Int) -> CGFloat) -> [Int] {
        var low = 0
        var high = sorted.count
        while low < high {
            let middle = (low + high) / 2
            if value(sorted[middle]) <= line - tolerance { low = middle + 1 } else { high = middle }
        }
        var found: [Int] = []
        while low < sorted.count && value(sorted[low]) < line + tolerance {
            found.append(sorted[low])
            low += 1
        }
        return found
    }
}
