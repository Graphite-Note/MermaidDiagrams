/**
 * File: DiagramRouteSegmentsTests.swift
 * -------------------------------------
 * Layer: Tests
 * Description: Paths appended to a layout's one list of segments (DiagramRouteSegments) against the paths
 *              DiagramRouteDrawing makes of the same routes, to the bit: random routes of two to nine points, in line
 *              and not, one flow or a flow for each segment, with and without trims, written after one another.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics
import XCTest
@testable import MermaidDiagrams

final class DiagramRouteSegmentsTests: XCTestCase {
    func testRoutesAppendedToOneListAreThePathsOfTheirOwnToTheBit() {
        var state: UInt64 = 0x5EED_0F_5E6
        func next(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(bound))
        }
        func coordinate() -> CGFloat { CGFloat(next(4_000)) / 7 - 200 }
        var segments: [DiagramPathSegment] = [.line(to: CGPoint(x: -1, y: -1))]
        var compared = 0
        for round in 0..<4_000 {
            let count = 2 + next(8)
            var points: [CGPoint] = [CGPoint(x: coordinate(), y: coordinate())]
            for _ in 1..<count {
                let last = points[points.count - 1]
                // Some points in line with the one before, some within a hundredth of a point of it, the others anywhere.
                switch next(4) {
                case 0: points.append(CGPoint(x: last.x, y: coordinate()))
                case 1: points.append(CGPoint(x: coordinate(), y: last.y + CGFloat(next(3)) / 1_000))
                default: points.append(CGPoint(x: coordinate(), y: coordinate()))
                }
            }
            let axes = (0..<(count - 1)).map { _ in next(2) == 0 }
            let startTrim = next(3) == 0 ? 0 : CGFloat(next(90)) / 10
            let endTrim = next(3) == 0 ? 0 : CGFloat(next(90)) / 10
            let expected = round % 2 == 0
                ? DiagramRouteDrawing.path(through: points, flowIsVertical: axes[0], startTrim: startTrim, endTrim: endTrim)
                : DiagramRouteDrawing.path(through: points, segmentsRunVertically: axes, startTrim: startTrim, endTrim: endTrim)
            let appended = round % 2 == 0
                ? DiagramRouteSegments.append(through: points, flowIsVertical: axes[0], startTrim: startTrim, endTrim: endTrim, into: &segments)
                : DiagramRouteSegments.append(through: points, segmentsRunVertically: axes, startTrim: startTrim, endTrim: endTrim, into: &segments)
            XCTAssertEqual(appended.run.path(in: segments), expected.path)
            XCTAssertEqual(Self.bits(appended.run.path(in: segments)), Self.bits(expected.path))
            XCTAssertEqual([appended.startDirection.dx, appended.startDirection.dy, appended.endDirection.dx, appended.endDirection.dy].map(\.bitPattern),
                           [expected.startDirection.dx, expected.startDirection.dy, expected.endDirection.dx, expected.endDirection.dy].map(\.bitPattern))
            if count == 2 {
                let pair = DiagramRouteSegments.append(through: DiagramPointPair(points[0], points[1]), flowIsVertical: axes[0], startTrim: startTrim,
                                                       endTrim: endTrim, into: &segments)
                XCTAssertEqual(Self.bits(pair.run.path(in: segments)),
                               Self.bits(DiagramRouteDrawing.path(through: points, flowIsVertical: axes[0], startTrim: startTrim, endTrim: endTrim).path))
            }
            compared += 1
        }
        XCTAssertEqual(segments[0], .line(to: CGPoint(x: -1, y: -1)))
        XCTAssertEqual(compared, 4_000)
    }

    /// Every coordinate of a path as its bits, so that 0 and -0 differ.
    private static func bits(_ path: DiagramPath) -> [UInt] {
        var bits = [path.start.x.bitPattern, path.start.y.bitPattern]
        for segment in path.segments {
            switch segment {
            case .line(let end): bits += [0, end.x.bitPattern, end.y.bitPattern]
            case .curve(let end, let first, let second):
                bits += [1, end.x.bitPattern, end.y.bitPattern, first.x.bitPattern, first.y.bitPattern, second.x.bitPattern, second.y.bitPattern]
            }
        }
        return bits
    }
}
