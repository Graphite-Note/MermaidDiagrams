/**
 * File: DiagramRouteDrawingRecording.swift
 * ----------------------------------------
 * Layer: Core
 * Description: The path through an edge's route as Pele draws it, written straight into a layout's list of segments and
 *              moved onto the page as it is written, the route's ends trimmed where they lie in its span: no list of the
 *              route's points and no path of its own are made.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics

extension DiagramRouteDrawing {
    /// The segments of the path `path(through:segmentsRunVertically:startTrim:endTrim:)` draws through `points`, each
    /// point of them moved by `offset` as `DiagramPath.translated(by:)` moves it, appended to `segments`. `points` holds
    /// at least two points; its first and last are trimmed where they lie, so a caller that needs the route's ends reads
    /// them first.
    /// - Returns: The path's start, moved by `offset`, and the unit directions the edge leaves its source and arrives at
    ///   its target in.
    static func appendPath<Axes: RandomAccessCollection<Bool>>(through points: ScratchSpan<CGPoint>, segmentsRunVertically: Axes, startTrim: CGFloat,
                                                               endTrim: CGFloat, offset: CGVector, to segments: inout ScratchList<DiagramPathSegment>)
        -> (start: CGPoint, startDirection: CGVector, endDirection: CGVector) where Axes.Index == Int {
        precondition(points.count >= 2 && !segmentsRunVertically.isEmpty, "a route of at least two points, and its segments' axes")
        let firstAxis = segmentsRunVertically[segmentsRunVertically.startIndex]
        let lastAxis = segmentsRunVertically[segmentsRunVertically.endIndex - 1]
        let startDirection = direction(from: points[0], to: points[1], flowIsVertical: firstAxis)
        let endDirection = direction(from: points[points.count - 2], to: points[points.count - 1], flowIsVertical: lastAxis)
        points[0] = CGPoint(x: points[0].x + startDirection.dx * startTrim, y: points[0].y + startDirection.dy * startTrim)
        let last = points.count - 1
        points[last] = CGPoint(x: points[last].x - endDirection.dx * endTrim, y: points[last].y - endDirection.dy * endTrim)
        for index in 1..<points.count {
            let from = points[index - 1]
            let to = points[index]
            if isInLine(from, to) {
                segments.append(.line(to: to.translated(by: offset)))
            } else if segmentsRunVertically[segmentsRunVertically.startIndex + index - 1] {
                let half = (to.y - from.y) / 2
                segments.append(.curve(to: to.translated(by: offset), control1: CGPoint(x: from.x, y: from.y + half).translated(by: offset),
                                       control2: CGPoint(x: to.x, y: to.y - half).translated(by: offset)))
            } else {
                let half = (to.x - from.x) / 2
                segments.append(.curve(to: to.translated(by: offset), control1: CGPoint(x: from.x + half, y: from.y).translated(by: offset),
                                       control2: CGPoint(x: to.x - half, y: to.y).translated(by: offset)))
            }
        }
        return (points[0].translated(by: offset), startDirection, endDirection)
    }

    /// The segments of `path` moved by `offset`, appended to `segments`; returns its start, moved.
    static func appendSegments(of path: DiagramPath, offset: CGVector, to segments: inout ScratchList<DiagramPathSegment>) -> CGPoint {
        for segment in path.segments {
            switch segment {
            case .line(let end): segments.append(.line(to: end.translated(by: offset)))
            case .curve(let end, let firstControl, let secondControl):
                segments.append(.curve(to: end.translated(by: offset), control1: firstControl.translated(by: offset),
                                       control2: secondControl.translated(by: offset)))
            }
        }
        return path.start.translated(by: offset)
    }
}
