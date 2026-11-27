/**
 * File: DiagramRouteSegments.swift
 * --------------------------------
 * Layer: Core
 * Description: The path through an edge's route as DiagramRouteDrawing draws it, its segments appended to a layout's
 *              one list of segments instead of a list of their own, read from any list of points without copying it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics
import Foundation

/// A path of a layout whose segments are a run of the layout's one list of segments (`DiagramRouteSegments`).
struct DiagramSegmentRun: Equatable, Sendable {
    var start: CGPoint
    var firstSegment: Int32
    var segmentCount: Int32

    var segmentIndices: Range<Int> { Int(firstSegment)..<Int(firstSegment + segmentCount) }

    /// The run as a path of its own, for a host that reads the layout's public paths.
    func path(in segments: [DiagramPathSegment]) -> DiagramPath {
        DiagramPath(start: start, segments: Array(segments[segmentIndices]))
    }
}

/// A route of two points, a straight line or one S, as a list that is no allocation.
struct DiagramPointPair: RandomAccessCollection {
    let first: CGPoint
    let second: CGPoint

    init(_ first: CGPoint, _ second: CGPoint) {
        self.first = first
        self.second = second
    }

    var startIndex: Int { 0 }
    var endIndex: Int { 2 }

    subscript(position: Int) -> CGPoint {
        precondition(position == 0 || position == 1, "a pair has two points")
        return position == 0 ? first : second
    }
}

/// `DiagramRouteDrawing.path(through:segmentsRunVertically:startTrim:endTrim:)`, the same arithmetic in the same
/// order, writing its segments at the end of a list a layout keeps for all its paths: the route is read where it lies,
/// its two ends trimmed as they are read.
enum DiagramRouteSegments {
    /// The path through `points`, whose segments all follow one flow, appended to `segments`.
    static func append<Points: RandomAccessCollection<CGPoint>>(through points: Points, flowIsVertical: Bool, startTrim: CGFloat, endTrim: CGFloat,
                                                                into segments: inout [DiagramPathSegment])
        -> (run: DiagramSegmentRun, startDirection: CGVector, endDirection: CGVector) where Points.Index == Int {
        append(through: points, segmentsRunVertically: repeatElement(flowIsVertical, count: points.count - 1), startTrim: startTrim, endTrim: endTrim,
               into: &segments)
    }

    /// The path through `points`, at least two of them, each segment following the flow `segmentsRunVertically` gives
    /// it, appended to `segments`.
    static func append<Points: RandomAccessCollection<CGPoint>, Axes: RandomAccessCollection<Bool>>(
        through points: Points, segmentsRunVertically: Axes, startTrim: CGFloat, endTrim: CGFloat, into segments: inout [DiagramPathSegment]
    ) -> (run: DiagramSegmentRun, startDirection: CGVector, endDirection: CGVector) where Points.Index == Int, Axes.Index == Int {
        precondition(points.count >= 2 && segmentsRunVertically.count >= points.count - 1, "a route of two points or more, an axis for each segment")
        let base = points.startIndex
        let axisBase = segmentsRunVertically.startIndex
        let last = points.count - 1
        let firstAxis = segmentsRunVertically[axisBase]
        let lastAxis = segmentsRunVertically[segmentsRunVertically.endIndex - 1]
        let startDirection = direction(from: points[base], to: points[base + 1], flowIsVertical: firstAxis)
        let endDirection = direction(from: points[base + last - 1], to: points[base + last], flowIsVertical: lastAxis)
        let first = points[base]
        let start = CGPoint(x: first.x + startDirection.dx * startTrim, y: first.y + startDirection.dy * startTrim)
        let final = points[base + last]
        let end = CGPoint(x: final.x - endDirection.dx * endTrim, y: final.y - endDirection.dy * endTrim)
        let firstSegment = segments.count
        var from = start
        for index in 1...last {
            let to = index == last ? end : points[base + index]
            if isInLine(from, to) {
                segments.append(.line(to: to))
            } else if segmentsRunVertically[axisBase + index - 1] {
                let half = (to.y - from.y) / 2
                segments.append(.curve(to: to, control1: CGPoint(x: from.x, y: from.y + half), control2: CGPoint(x: to.x, y: to.y - half)))
            } else {
                let half = (to.x - from.x) / 2
                segments.append(.curve(to: to, control1: CGPoint(x: from.x + half, y: from.y), control2: CGPoint(x: to.x - half, y: to.y)))
            }
            from = to
        }
        let run = DiagramSegmentRun(start: start, firstSegment: Int32(firstSegment), segmentCount: Int32(segments.count - firstSegment))
        return (run, startDirection, endDirection)
    }

    /// `DiagramRouteDrawing`'s direction from `from` to `to`: along the flow when an S joins them, straight at the
    /// other otherwise.
    private static func direction(from: CGPoint, to: CGPoint, flowIsVertical: Bool) -> CGVector {
        if !isInLine(from, to) {
            return flowIsVertical ? CGVector(dx: 0, dy: to.y >= from.y ? 1 : -1) : CGVector(dx: to.x >= from.x ? 1 : -1, dy: 0)
        }
        let length = max(hypot(to.x - from.x, to.y - from.y), 0.0001)
        return CGVector(dx: (to.x - from.x) / length, dy: (to.y - from.y) / length)
    }

    /// Two points are in line when they share a coordinate, to a hundredth of a point.
    private static func isInLine(_ first: CGPoint, _ second: CGPoint) -> Bool {
        abs(first.x - second.x) < 0.01 || abs(first.y - second.y) < 0.01
    }

    /// Every point of the segments moved by `offset`, where they lie.
    static func translate(_ segments: inout [DiagramPathSegment], by offset: CGVector) {
        translate(&segments, segments.indices, by: offset)
    }

    /// Every point of the segments at `indices` moved by `offset`, where they lie.
    static func translate(_ segments: inout [DiagramPathSegment], _ indices: Range<Int>, by offset: CGVector) {
        for index in indices {
            switch segments[index] {
            case .line(let end): segments[index] = .line(to: end.translated(by: offset))
            case .curve(let end, let firstControl, let secondControl):
                segments[index] = .curve(to: end.translated(by: offset), control1: firstControl.translated(by: offset),
                                         control2: secondControl.translated(by: offset))
            }
        }
    }

    /// `bounds` grown to hold the run's start and every point of its segments, in their order.
    static func union(_ bounds: CGRect, _ run: DiagramSegmentRun, in segments: [DiagramPathSegment]) -> CGRect {
        var bounds = bounds.union(CGRect(origin: run.start, size: .zero))
        for index in run.segmentIndices {
            switch segments[index] {
            case .line(let end): bounds = bounds.union(CGRect(origin: end, size: .zero))
            case .curve(let end, let firstControl, let secondControl):
                bounds = bounds.union(CGRect(origin: end, size: .zero)).union(CGRect(origin: firstControl, size: .zero))
                    .union(CGRect(origin: secondControl, size: .zero))
            }
        }
        return bounds
    }

    /// The run recorded into `drawn` as `DiagramEdgeDrawing.record(_:into:)` records a path.
    static func record<Path: DiagramPathRecording>(_ run: DiagramSegmentRun, of segments: [DiagramPathSegment], into drawn: Path) {
        drawn.move(to: run.start)
        for index in run.segmentIndices {
            switch segments[index] {
            case .line(let end): drawn.addLine(to: end)
            case .curve(let end, let firstControl, let secondControl): drawn.addCurve(to: end, control1: firstControl, control2: secondControl)
            }
        }
    }
}
