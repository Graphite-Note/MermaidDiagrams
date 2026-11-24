/**
 * File: DiagramScenePathEquivalenceTests.swift
 * --------------------------------------------
 * Layer: Tests
 * Description: Scene paths give Core Graphics' elements and bounds to the bit: rectangles, rounded rectangles, ellipses
 *              and arcs added to empty paths and after other elements, through transforms, curves' bounds, paths added
 *              to paths, and a glyph's outline moved and scaled, over large seeded random sets.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import CoreGraphics
import XCTest
@testable import MermaidDiagrams

final class DiagramScenePathEquivalenceTests: XCTestCase {
    private static let sampleCount = 40_000

    func testRoundedRectanglesAreCoreGraphicsOwn() {
        var samples = DiagramScenePathSamples(seed: 0x52_52)
        for _ in 0..<Self.sampleCount {
            let rect = samples.rectangle(), cornerWidth = samples.radius()
            let cornerHeight = samples.next() % 2 == 0 ? cornerWidth : samples.radius()
            let prefix = samples.next()
            let reference = CGMutablePath()
            var path = DiagramScenePath()
            samples.addPrefix(kind: prefix, to: reference, &path)
            reference.addRoundedRect(in: rect, cornerWidth: cornerWidth, cornerHeight: cornerHeight)
            path.addRoundedRect(in: rect, cornerWidth: cornerWidth, cornerHeight: cornerHeight)
            assertSameAsCoreGraphics(path, reference, "\(rect) \(cornerWidth) \(cornerHeight) after \(prefix % 5)")
            let made = CGPath(roundedRect: rect, cornerWidth: max(0, min(cornerWidth, abs(rect.size.width) / 2)),
                              cornerHeight: max(0, min(cornerHeight, abs(rect.size.height) / 2)), transform: nil)
            assertSameAsCoreGraphics(DiagramScenePath(roundedRect: rect, cornerWidth: cornerWidth, cornerHeight: cornerHeight), made, "\(rect)")
            reference.addPath(made)
            path.addPathOfRoundedRect(rect, cornerWidth: cornerWidth, cornerHeight: cornerHeight)
            assertSameAsCoreGraphics(path, reference, "\(rect) added as a path")
        }
    }

    func testRectanglesAndEllipsesAreCoreGraphicsOwn() {
        var samples = DiagramScenePathSamples(seed: 0xE1_11)
        for _ in 0..<Self.sampleCount {
            let rect = samples.rectangle()
            let prefix = samples.next()
            let ellipseReference = CGMutablePath(), rectangleReference = CGMutablePath()
            var ellipse = DiagramScenePath(), rectangle = DiagramScenePath()
            samples.addPrefix(kind: prefix, to: ellipseReference, &ellipse)
            samples.addPrefix(kind: prefix, to: rectangleReference, &rectangle)
            ellipseReference.addEllipse(in: rect)
            ellipse.addEllipse(in: rect)
            rectangleReference.addRect(rect)
            rectangle.addRect(rect)
            assertSameAsCoreGraphics(ellipse, ellipseReference, "ellipse \(rect) after \(prefix % 5)")
            assertSameAsCoreGraphics(rectangle, rectangleReference, "rectangle \(rect) after \(prefix % 5)")
            let end = samples.point()
            ellipseReference.addLine(to: end)
            ellipse.addLine(to: end)
            assertSameAsCoreGraphics(ellipse, ellipseReference, "ellipse \(rect) then a line")
        }
    }

    func testArcsAreCoreGraphicsOwn() {
        var samples = DiagramScenePathSamples(seed: 0xA2_C5)
        for _ in 0..<Self.sampleCount {
            let center = samples.point(), radius = abs(samples.radius()).truncatingRemainder(dividingBy: 500)
            let start = samples.angle()
            let end = samples.next() % 4 == 0 ? start + samples.angle() : samples.angle()
            let clockwise = samples.next() % 2 == 0
            guard Self.coreGraphicsAccepts(start: start, end: end, clockwise: clockwise) else { continue }
            let prefix = samples.next()
            let reference = CGMutablePath()
            var path = DiagramScenePath()
            samples.addPrefix(kind: prefix, to: reference, &path)
            reference.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: clockwise)
            path.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: clockwise)
            let description = "\(center) \(radius) \(start) \(end) \(clockwise) after \(prefix % 5)"
            assertSameAsCoreGraphics(path, reference, description)
            let next = samples.point()
            reference.addLine(to: next)
            path.addLine(to: next)
            assertSameAsCoreGraphics(path, reference, description + " then a line")
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
        var samples = DiagramScenePathSamples(seed: 0x7F_A5)
        for _ in 0..<Self.sampleCount / 2 {
            let rect = samples.rectangle(), cornerRadius = samples.radius(), prefix = samples.next()
            let turn = CGAffineTransform(translationX: samples.coordinate(), y: samples.coordinate()).rotated(by: samples.angle())
                .translatedBy(x: samples.coordinate(), y: samples.coordinate())
            let reference = CGMutablePath()
            var path = DiagramScenePath()
            samples.addPrefix(kind: prefix, to: reference, &path)
            reference.addRoundedRect(in: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: turn)
            path.addRoundedRect(in: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: turn)
            assertSameAsCoreGraphics(path, reference, "\(rect) \(cornerRadius) turned \(turn)")
            let scale = CGAffineTransform(a: abs(samples.coordinate()) + 1, b: 0, c: 0, d: abs(samples.coordinate()) + 1,
                                          tx: samples.coordinate(), ty: samples.coordinate())
            let clockwise = samples.next() % 2 == 0
            let halfEllipse = CGMutablePath()
            var scenePath = DiagramScenePath()
            samples.addPrefix(kind: prefix, to: halfEllipse, &scenePath)
            halfEllipse.addArc(center: .zero, radius: 1, startAngle: .pi / 2, endAngle: 3 * .pi / 2, clockwise: clockwise, transform: scale)
            scenePath.addArc(center: .zero, radius: 1, startAngle: .pi / 2, endAngle: 3 * .pi / 2, clockwise: clockwise, transform: scale)
            assertSameAsCoreGraphics(scenePath, halfEllipse, "half ellipse through \(scale)")
        }
    }

    func testCurvesAreBoundedAsCoreGraphicsBoundsThem() {
        var samples = DiagramScenePathSamples(seed: 0xB0_C0)
        for _ in 0..<Self.sampleCount {
            let reference = CGMutablePath()
            var path = DiagramScenePath()
            let start = samples.point()
            reference.move(to: start)
            path.move(to: start)
            for _ in 0..<(samples.next() % 4 + 1) {
                let first = samples.point(), second = samples.point(), third = samples.point()
                if samples.next() % 3 == 0 {
                    reference.addQuadCurve(to: second, control: first)
                    path.addQuadCurve(to: second, control: first)
                } else {
                    reference.addCurve(to: third, control1: first, control2: second)
                    path.addCurve(to: third, control1: first, control2: second)
                }
                if samples.next() % 4 == 0 {
                    reference.closeSubpath()
                    path.closeSubpath()
                }
            }
            assertSameAsCoreGraphics(path, reference, "curves from \(start)")
        }
    }

    func testPathsAddedToPathsAreCoreGraphicsOwn() {
        var samples = DiagramScenePathSamples(seed: 0xAD_D0)
        for _ in 0..<Self.sampleCount {
            let rect = samples.rectangle(), kind = samples.next()
            let other = CGMutablePath(), target = CGMutablePath()
            var otherPath = DiagramScenePath(), targetPath = DiagramScenePath()
            samples.addPrefix(kind: kind &+ 1, to: other, &otherPath)
            switch kind % 3 {
            case 0:
                other.addEllipse(in: rect)
                otherPath.addEllipse(in: rect)
            case 1:
                other.addRoundedRect(in: rect, cornerWidth: 4, cornerHeight: 4)
                otherPath.addRoundedRect(in: rect, cornerWidth: 4, cornerHeight: 4)
            default:
                other.addArc(center: rect.origin, radius: 5, startAngle: 0.3, endAngle: 2.2, clockwise: false)
                otherPath.addArc(center: rect.origin, radius: 5, startAngle: 0.3, endAngle: 2.2, clockwise: false)
            }
            samples.addPrefix(kind: kind >> 3, to: target, &targetPath)
            target.addPath(other)
            targetPath.addPath(otherPath)
            assertSameAsCoreGraphics(targetPath, target, "\(rect) kind \(kind % 3) after \((kind >> 3) % 5)")
        }
    }

    func testMovedAndScaledGlyphsAreCoreGraphicsOwn() {
        var samples = DiagramScenePathSamples(seed: 0x61_7F)
        for _ in 0..<Self.sampleCount {
            let glyph = CGMutablePath()
            var path = DiagramScenePath()
            let start = samples.point(), control = samples.point(), end = samples.point()
            glyph.move(to: start)
            glyph.addQuadCurve(to: end, control: control)
            glyph.addLine(to: control)
            glyph.closeSubpath()
            path.move(to: start)
            path.addQuadCurve(to: end, control: control)
            path.addLine(to: control)
            path.closeSubpath()
            let side = abs(samples.coordinate()) / 24 + 0.01
            var move = CGAffineTransform(translationX: samples.coordinate(), y: samples.coordinate()).scaledBy(x: side, y: side)
            let reference = glyph.copy(using: &move) ?? glyph
            assertSameAsCoreGraphics(path.applying(move), reference, "glyph through \(move)")
        }
    }
}
