/**
 * File: DiagramRouteDrawingSpanTests.swift
 * ----------------------------------------
 * Layer: Tests
 * Description: Checks that the route drawings and the fill placement read a span of a scratch arena as they read an
 *              array: random routes that turn and do not, with their axes, drawn both ways to the bit, and the placement of
 *              random lines among random boxes.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams
import XCTest

final class DiagramRouteDrawingSpanTests: XCTestCase {
    private var state: UInt64 = 0x5BA_7E

    private func next(_ bound: Int) -> Int {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Int((state >> 33) % UInt64(bound))
    }

    /// A route of right-angled and slanted steps on a coarse grid, so that points fall in line often.
    private func route() -> (points: [CGPoint], axes: [Bool]) {
        var points = [CGPoint(x: CGFloat(next(20) * 10), y: CGFloat(next(20) * 10))]
        for _ in 0..<(1 + next(6)) {
            let last = points[points.count - 1]
            switch next(3) {
            case 0: points.append(CGPoint(x: last.x + CGFloat(next(9) * 10 - 40), y: last.y))
            case 1: points.append(CGPoint(x: last.x, y: last.y + CGFloat(next(9) * 10 - 40)))
            default: points.append(CGPoint(x: last.x + CGFloat(next(9) * 7 - 28), y: last.y + CGFloat(next(9) * 11 - 44)))
            }
        }
        return (points, (1..<points.count).map { _ in next(2) == 0 })
    }

    /// `values` in a span of memory of its own, given to `body`.
    private func withSpan<Value: BitwiseCopyable, Result>(_ values: [Value], _ body: (ScratchSpan<Value>) -> Result) -> Result {
        let memory = UnsafeMutablePointer<Value>.allocate(capacity: max(values.count, 1))
        defer { memory.deallocate() }
        memory.initialize(from: values, count: values.count)
        return body(ScratchSpan(start: memory, count: values.count))
    }

    func testRoutesDrawnFromSpansAreTheRoutesDrawnFromArrays() {
        for _ in 0..<3_000 {
            let (points, axes) = route()
            let trims = (CGFloat(next(3) * 4), CGFloat(next(3) * 5))
            let reach: CGFloat? = next(2) == 0 ? nil : CGFloat(next(30))
            let turning = DiagramTurningRouteDrawing.path(through: points, segmentsRunVertically: axes, startTrim: trims.0, endTrim: trims.1, startReach: reach)
            let straight = DiagramRouteDrawing.path(through: points, flowIsVertical: axes[0], startTrim: trims.0, endTrim: trims.1)
            let flowing = DiagramRouteDrawing.path(through: points, segmentsRunVertically: axes, startTrim: trims.0, endTrim: trims.1)
            withSpan(points) { pointSpan in
                withSpan(axes) { axisSpan in
                    let fromSpans = DiagramTurningRouteDrawing.path(through: pointSpan, segmentsRunVertically: axisSpan, startTrim: trims.0, endTrim: trims.1,
                                                                    startReach: reach)
                    XCTAssertEqual(fromSpans.path, turning.path)
                    XCTAssertEqual(fromSpans.startDirection, turning.startDirection)
                    XCTAssertEqual(fromSpans.endDirection, turning.endDirection)
                    XCTAssertEqual(DiagramRouteDrawing.path(through: pointSpan, flowIsVertical: axes[0], startTrim: trims.0, endTrim: trims.1).path, straight.path)
                    XCTAssertEqual(DiagramRouteDrawing.path(through: pointSpan, segmentsRunVertically: axisSpan, startTrim: trims.0, endTrim: trims.1).path,
                                   flowing.path)
                }
            }
        }
    }

    func testFillPlacementOfSpansIsThePlacementOfArrays() {
        var placements: Set<String> = []
        for _ in 0..<2_000 {
            let (points, axes) = route()
            let path = DiagramRouteDrawing.path(through: points, segmentsRunVertically: axes, startTrim: 0, endTrim: 0).path
            let frames = (0..<next(5)).map { _ in
                CGRect(x: CGFloat(next(20) * 10 - 20), y: CGFloat(next(20) * 10 - 20), width: CGFloat(20 + next(30) * 10), height: CGFloat(20 + next(30) * 10))
            }
            let tips = [points[0], points[points.count - 1]]
            let expected = DiagramFillPlacement.placement(of: path, tips: tips, among: frames)
            placements.insert("\(expected)")
            withSpan(tips) { tipSpan in
                withSpan(frames) { frameSpan in XCTAssertEqual(DiagramFillPlacement.placement(of: path, tips: tipSpan, among: frameSpan), expected) }
            }
        }
        XCTAssertGreaterThanOrEqual(placements.count, 4, "lines on none, across a border and inside boxes")
    }
}
