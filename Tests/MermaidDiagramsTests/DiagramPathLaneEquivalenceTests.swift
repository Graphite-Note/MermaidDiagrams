/**
 * File: DiagramPathLaneEquivalenceTests.swift
 * -------------------------------------------
 * Layer: Tests
 * Description: Path lanes give Core Graphics' elements, bounds and current point to the bit: rectangles, rounded
 *              rectangles, ellipses and arcs added to empty lanes and after other elements, through transforms, curves'
 *              bounds, paths added to paths with and without a transform, and a glyph's outline moved and scaled, over
 *              large seeded random sets; and the constants the lanes take in place of the system's trigonometry.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
import Darwin
import XCTest
@testable import MermaidDiagrams

final class DiagramPathLaneEquivalenceTests: XCTestCase {
    private static let sampleCount = 40_000

    /// Runs `body` in a recording of the thread's workspace, as a scene records.
    private func recording(_ body: (DiagramSceneWorkspace) -> Void) {
        DiagramSceneWorkspace.withRecording { workspace in body(workspace) }
    }

    func testRoundedRectanglesAreCoreGraphicsOwn() {
        var samples = DiagramPathLaneSamples(seed: 0x52_52)
        for _ in 0..<Self.sampleCount {
            let rect = samples.rectangle(), cornerWidth = samples.radius()
            let cornerHeight = samples.next() % 2 == 0 ? cornerWidth : samples.radius()
            let prefix = samples.next()
            recording { workspace in
                let reference = CGMutablePath()
                let lane = workspace.makeLane()
                samples.addPrefix(kind: prefix, to: reference, lane)
                reference.addRoundedRect(in: rect, cornerWidth: cornerWidth, cornerHeight: cornerHeight)
                lane.addRoundedRect(in: rect, cornerWidth: cornerWidth, cornerHeight: cornerHeight)
                assertSameAsCoreGraphics(lane, reference, "\(rect) \(cornerWidth) \(cornerHeight) after \(prefix % 5)")
                let made = CGPath(roundedRect: rect, cornerWidth: max(0, min(cornerWidth, abs(rect.size.width) / 2)),
                                  cornerHeight: max(0, min(cornerHeight, abs(rect.size.height) / 2)), transform: nil)
                let madeLane = workspace.roundedRectangle(rect, cornerWidth: cornerWidth, cornerHeight: cornerHeight)
                assertSameAsCoreGraphics(madeLane, made, "\(rect)")
                reference.addPath(made)
                lane.addPathOfRoundedRect(rect, cornerWidth: cornerWidth, cornerHeight: cornerHeight)
                assertSameAsCoreGraphics(lane, reference, "\(rect) added as a path")
                reference.addPath(made)
                lane.addPath(madeLane)
                assertSameAsCoreGraphics(lane, reference, "\(rect) added as a lane")
            }
        }
    }

    func testRectanglesAndEllipsesAreCoreGraphicsOwn() {
        var samples = DiagramPathLaneSamples(seed: 0xE1_11)
        for _ in 0..<Self.sampleCount {
            let rect = samples.rectangle()
            let prefix = samples.next()
            let end = samples.point()
            recording { workspace in
                let ellipseReference = CGMutablePath(), rectangleReference = CGMutablePath()
                let ellipse = workspace.makeLane(), rectangle = workspace.makeLane()
                samples.addPrefix(kind: prefix, to: ellipseReference, ellipse)
                samples.addPrefix(kind: prefix, to: rectangleReference, rectangle)
                ellipseReference.addEllipse(in: rect)
                ellipse.addEllipse(in: rect)
                rectangleReference.addRect(rect)
                rectangle.addRect(rect)
                assertSameAsCoreGraphics(ellipse, ellipseReference, "ellipse \(rect) after \(prefix % 5)")
                assertSameAsCoreGraphics(rectangle, rectangleReference, "rectangle \(rect) after \(prefix % 5)")
                ellipseReference.addLine(to: end)
                ellipse.addLine(to: end)
                assertSameAsCoreGraphics(ellipse, ellipseReference, "ellipse \(rect) then a line")
                assertSameAsCoreGraphics(workspace.rectangle(rect), CGPath(rect: rect, transform: nil), "rectangle path \(rect)")
                assertSameAsCoreGraphics(workspace.ellipse(in: rect), CGPath(ellipseIn: rect, transform: nil), "ellipse path \(rect)")
            }
        }
    }

    func testArcsAreCoreGraphicsOwn() {
        var samples = DiagramPathLaneSamples(seed: 0xA2_C5)
        for _ in 0..<Self.sampleCount {
            let center = samples.point(), radius = abs(samples.radius()).truncatingRemainder(dividingBy: 500)
            let start = samples.angle()
            let end = samples.next() % 4 == 0 ? start + samples.angle() : samples.angle()
            let clockwise = samples.next() % 2 == 0
            guard Self.coreGraphicsAccepts(start: start, end: end, clockwise: clockwise) else { continue }
            let prefix = samples.next()
            let next = samples.point()
            recording { workspace in
                let reference = CGMutablePath()
                let lane = workspace.makeLane()
                samples.addPrefix(kind: prefix, to: reference, lane)
                reference.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: clockwise)
                lane.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: clockwise)
                let description = "\(center) \(radius) \(start) \(end) \(clockwise) after \(prefix % 5)"
                assertSameAsCoreGraphics(lane, reference, description)
                reference.addLine(to: next)
                lane.addLine(to: next)
                assertSameAsCoreGraphics(lane, reference, description + " then a line")
            }
        }
    }

    /// Whether Core Graphics' `add_arc` keeps its own assertion that the end lies past the start once whole turns are
    /// added; for angles where rounding breaks it, Core Graphics stops the process.
    private static func coreGraphicsAccepts(start: CGFloat, end: CGFloat, clockwise: Bool) -> Bool {
        let fullTurn = 2 * CGFloat.pi
        if clockwise {
            guard start < end else { return true }
            return start.addingProduct(((start - end) / -fullTurn).rounded(.up), fullTurn) >= end
        }
        guard end < start else { return true }
        return end.addingProduct(((end - start) / -fullTurn).rounded(.up), fullTurn) >= start
    }

    func testTransformedShapesAreCoreGraphicsOwn() {
        var samples = DiagramPathLaneSamples(seed: 0x7F_A5)
        for _ in 0..<Self.sampleCount / 2 {
            let rect = samples.rectangle(), cornerRadius = samples.radius(), prefix = samples.next()
            let turn = CGAffineTransform(translationX: samples.coordinate(), y: samples.coordinate()).rotated(by: samples.angle())
                .translatedBy(x: samples.coordinate(), y: samples.coordinate())
            let scale = CGAffineTransform(a: abs(samples.coordinate()) + 1, b: 0, c: 0, d: abs(samples.coordinate()) + 1,
                                          tx: samples.coordinate(), ty: samples.coordinate())
            let clockwise = samples.next() % 2 == 0
            recording { workspace in
                let reference = CGMutablePath()
                let lane = workspace.makeLane()
                samples.addPrefix(kind: prefix, to: reference, lane)
                reference.addRoundedRect(in: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: turn)
                lane.addRoundedRect(in: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: turn)
                assertSameAsCoreGraphics(lane, reference, "\(rect) \(cornerRadius) turned \(turn)")
                let halfEllipse = CGMutablePath()
                let halfEllipseLane = workspace.makeLane()
                samples.addPrefix(kind: prefix, to: halfEllipse, halfEllipseLane)
                halfEllipse.addArc(center: .zero, radius: 1, startAngle: .pi / 2, endAngle: 3 * .pi / 2, clockwise: clockwise, transform: scale)
                halfEllipseLane.addArc(center: .zero, radius: 1, startAngle: .pi / 2, endAngle: 3 * .pi / 2, clockwise: clockwise, transform: scale)
                assertSameAsCoreGraphics(halfEllipseLane, halfEllipse, "half ellipse through \(scale)")
            }
        }
    }

    func testCurvesAreBoundedAsCoreGraphicsBoundsThem() {
        var samples = DiagramPathLaneSamples(seed: 0xB0_C0)
        for _ in 0..<Self.sampleCount {
            recording { workspace in
                let reference = CGMutablePath()
                let lane = workspace.makeLane()
                let start = samples.point()
                reference.move(to: start)
                lane.move(to: start)
                for _ in 0..<(samples.next() % 4 + 1) {
                    let first = samples.point(), second = samples.point(), third = samples.point()
                    if samples.next() % 3 == 0 {
                        reference.addQuadCurve(to: second, control: first)
                        lane.addQuadCurve(to: second, control: first)
                    } else {
                        reference.addCurve(to: third, control1: first, control2: second)
                        lane.addCurve(to: third, control1: first, control2: second)
                    }
                    if samples.next() % 4 == 0 {
                        reference.closeSubpath()
                        lane.closeSubpath()
                    }
                }
                assertSameAsCoreGraphics(lane, reference, "curves from \(start)")
            }
        }
    }

    func testPathsAddedToPathsAreCoreGraphicsOwn() {
        var samples = DiagramPathLaneSamples(seed: 0xAD_D0)
        for _ in 0..<Self.sampleCount {
            let rect = samples.rectangle(), kind = samples.next()
            recording { workspace in
                let other = CGMutablePath(), target = CGMutablePath()
                let otherLane = workspace.makeLane(), targetLane = workspace.makeLane()
                samples.addPrefix(kind: kind &+ 1, to: other, otherLane)
                Self.addShape(kind: kind, rect: rect, to: other, otherLane)
                samples.addPrefix(kind: kind >> 3, to: target, targetLane)
                target.addPath(other)
                targetLane.addPath(otherLane)
                assertSameAsCoreGraphics(targetLane, target, "\(rect) kind \(kind % 3) after \((kind >> 3) % 5)")
                target.addPath(target)
                targetLane.addPath(targetLane)
                assertSameAsCoreGraphics(targetLane, target, "\(rect) kind \(kind % 3) added to itself")
            }
        }
    }

    /// An ellipse, a rounded rectangle or an arc by `kind`.
    private static func addShape(kind: UInt64, rect: CGRect, to reference: CGMutablePath, _ lane: DiagramPathLane) {
        switch kind % 3 {
        case 0:
            reference.addEllipse(in: rect)
            lane.addEllipse(in: rect)
        case 1:
            reference.addRoundedRect(in: rect, cornerWidth: 4, cornerHeight: 4)
            lane.addRoundedRect(in: rect, cornerWidth: 4, cornerHeight: 4)
        default:
            reference.addArc(center: rect.origin, radius: 5, startAngle: 0.3, endAngle: 2.2, clockwise: false)
            lane.addArc(center: rect.origin, radius: 5, startAngle: 0.3, endAngle: 2.2, clockwise: false)
        }
    }

    func testPathsAddedThroughATransformAreCoreGraphicsOwn() {
        var samples = DiagramPathLaneSamples(seed: 0x7A_DD)
        for _ in 0..<Self.sampleCount / 2 {
            let rect = samples.rectangle(), kind = samples.next()
            let side = abs(samples.coordinate()) / 24 + 0.01
            let move = CGAffineTransform(translationX: samples.coordinate(), y: samples.coordinate()).scaledBy(x: side, y: side)
            let turn = CGAffineTransform(rotationAngle: samples.angle()).translatedBy(x: samples.coordinate(), y: samples.coordinate())
            for transform in [move, turn] {
                recording { workspace in
                    let other = CGMutablePath(), target = CGMutablePath()
                    let otherLane = workspace.makeLane(), targetLane = workspace.makeLane()
                    samples.addPrefix(kind: kind &+ 1, to: other, otherLane)
                    Self.addShape(kind: kind, rect: rect, to: other, otherLane)
                    samples.addPrefix(kind: kind >> 3, to: target, targetLane)
                    target.addPath(other, transform: transform)
                    targetLane.addPath(otherLane, transform: transform)
                    assertSameAsCoreGraphics(targetLane, target, "\(rect) kind \(kind % 3) after \((kind >> 3) % 5) through \(transform)")
                }
            }
        }
    }

    func testMovedAndScaledGlyphsAreCoreGraphicsOwn() {
        var samples = DiagramPathLaneSamples(seed: 0x61_7F)
        for _ in 0..<Self.sampleCount {
            let start = samples.point(), control = samples.point(), end = samples.point()
            let side = abs(samples.coordinate()) / 24 + 0.01
            var move = CGAffineTransform(translationX: samples.coordinate(), y: samples.coordinate()).scaledBy(x: side, y: side)
            recording { workspace in
                let glyph = CGMutablePath()
                let lane = workspace.makeLane()
                glyph.move(to: start)
                glyph.addQuadCurve(to: end, control: control)
                glyph.addLine(to: control)
                glyph.closeSubpath()
                lane.move(to: start)
                lane.addQuadCurve(to: end, control: control)
                lane.addLine(to: control)
                lane.closeSubpath()
                let reference = glyph.copy(using: &move) ?? glyph
                let moved = workspace.makeLane()
                moved.addPath(lane, transform: move)
                assertSameAsCoreGraphics(moved, reference, "glyph through \(move)")
            }
        }
    }

    /// A Core Graphics path read into a lane gives its elements back as they were, a move after a move included.
    func testPathsReadFromCoreGraphicsGiveTheirElementsBack() {
        var samples = DiagramPathLaneSamples(seed: 0x0C_6A)
        for _ in 0..<Self.sampleCount / 4 {
            let rect = samples.rectangle(), kind = samples.next()
            recording { workspace in
                let reference = CGMutablePath()
                let ignored = workspace.makeLane()
                samples.addPrefix(kind: kind, to: reference, ignored)
                Self.addShape(kind: kind, rect: rect, to: reference, ignored)
                reference.move(to: rect.origin)
                reference.move(to: CGPoint(x: rect.maxX, y: rect.minY))
                let lane = workspace.makeLane()
                lane.appendElements(of: reference)
                XCTAssertTrue(DiagramPathLaneElements(lane).matches(DiagramPathLaneElements(reference)), "\(rect) \(kind % 5)")
                XCTAssertTrue(DiagramPathLaneElements(lane.makePath()).matches(DiagramPathLaneElements(reference)), "\(rect) made again")
            }
        }
    }
}
