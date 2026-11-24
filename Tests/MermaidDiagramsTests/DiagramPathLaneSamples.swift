/**
 * File: DiagramPathLaneSamples.swift
 * ----------------------------------
 * Layer: Tests
 * Description: Seeded random coordinates, sizes, radii and angles for comparing path lanes with Core Graphics' paths,
 *              and the comparison itself: every element's kind and points and the bounds, to the bit.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
import XCTest
@testable import MermaidDiagrams

/// Random values of the kinds diagrams draw with, and of kinds they never do: whole and quarter points, fractions,
/// large and negative numbers, zero and negative sizes, radii past half a side, multiples of a quarter turn.
struct DiagramPathLaneSamples {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }

    mutating func fraction() -> CGFloat {
        CGFloat(next() >> 11) / CGFloat(1 << 53)
    }

    mutating func coordinate() -> CGFloat {
        switch next() % 6 {
        case 0: CGFloat(Int(next() % 2_000)) - 500
        case 1: (CGFloat(Int(next() % 8_000)) - 2_000) / 4
        case 2: fraction() * 1_000 - 300
        case 3: CGFloat(Int(next() % 50)) * 0.1
        case 4: fraction() * 3
        default: (fraction() - 0.5) * 1e5
        }
    }

    mutating func point() -> CGPoint {
        CGPoint(x: coordinate(), y: coordinate())
    }

    mutating func length() -> CGFloat {
        switch next() % 7 {
        case 0: 0
        case 1: -coordinate()
        default: abs(coordinate())
        }
    }

    mutating func rectangle() -> CGRect {
        CGRect(x: coordinate(), y: coordinate(), width: length(), height: length())
    }

    mutating func radius() -> CGFloat {
        switch next() % 6 {
        case 0: 0
        case 1: -fraction() * 3
        case 2: 1e9
        case 3: CGFloat(next() % 20)
        default: fraction() * 40
        }
    }

    mutating func angle() -> CGFloat {
        switch next() % 5 {
        case 0: CGFloat(Int(next() % 9) - 4) * .pi / 2
        case 1: CGFloat(Int(next() % 9) - 4) * .pi / 4
        case 2: 0
        default: (fraction() - 0.5) * 20
        }
    }

    /// The same elements added to both paths, so that what follows is added after a move, a line, a rounded rectangle,
    /// a closed subpath or nothing.
    mutating func addPrefix(kind: UInt64, to reference: CGMutablePath, _ lane: DiagramPathLane) {
        switch kind % 5 {
        case 1:
            let start = point()
            reference.move(to: start)
            lane.move(to: start)
        case 2:
            let start = point(), end = point()
            reference.move(to: start)
            reference.addLine(to: end)
            lane.move(to: start)
            lane.addLine(to: end)
        case 3:
            let rect = rectangle(), radius = radius()
            reference.addRoundedRect(in: rect, cornerWidth: radius, cornerHeight: radius)
            lane.addRoundedRect(in: rect, cornerWidth: radius, cornerHeight: radius)
        case 4:
            let start = point()
            reference.move(to: start)
            reference.addLine(to: CGPoint(x: start.x + 3, y: start.y))
            reference.closeSubpath()
            lane.move(to: start)
            lane.addLine(to: CGPoint(x: start.x + 3, y: start.y))
            lane.closeSubpath()
        default:
            break
        }
    }
}

/// The elements a path gives out, as `CGPathApply` gives them.
struct DiagramPathLaneElements: Equatable {
    var verbs: [DiagramPathVerb] = []
    var points: [CGPoint] = []

    init(_ lane: DiagramPathLane) {
        lane.forEachElement { verb, elementPoints in
            verbs.append(verb)
            for index in 0..<verb.pointCount { points.append(elementPoints[index]) }
        }
    }

    init(_ path: CGPath) {
        path.applyWithBlock { element in
            let verb: DiagramPathVerb
            switch element.pointee.type {
            case .moveToPoint: verb = .move
            case .addLineToPoint: verb = .line
            case .addQuadCurveToPoint: verb = .quadraticCurve
            case .addCurveToPoint: verb = .cubicCurve
            default: verb = .close
            }
            verbs.append(verb)
            for index in 0..<verb.pointCount { points.append(element.pointee.points[index]) }
        }
    }

    /// The same kinds, and each point's coordinates equal, NaN equal to NaN.
    func matches(_ other: DiagramPathLaneElements) -> Bool {
        verbs == other.verbs && points.count == other.points.count
            && zip(points, other.points).allSatisfy { first, second in Self.same(first.x, second.x) && Self.same(first.y, second.y) }
    }

    static func same(_ first: CGFloat, _ second: CGFloat) -> Bool {
        first == second || (first.isNaN && second.isNaN)
    }
}

extension XCTestCase {
    /// Fails unless `lane` has `reference`'s elements and bounds, to the bit.
    func assertSameAsCoreGraphics(_ lane: DiagramPathLane, _ reference: CGPath, _ description: @autoclosure () -> String,
                                  file: StaticString = #filePath, line: UInt = #line) {
        let expected = DiagramPathLaneElements(reference)
        let made = DiagramPathLaneElements(lane)
        if !made.matches(expected) {
            XCTFail("elements differ: \(description())\n  Core Graphics \(expected.verbs) \(expected.points)\n  lane \(made.verbs) \(made.points)",
                    file: file, line: line)
        }
        let bounds = lane.boundsOfPath, expectedBounds = reference.boundingBoxOfPath
        let same = DiagramPathLaneElements.same
        if !(same(bounds.origin.x, expectedBounds.origin.x) && same(bounds.origin.y, expectedBounds.origin.y)
            && same(bounds.size.width, expectedBounds.size.width) && same(bounds.size.height, expectedBounds.size.height)) {
            XCTFail("bounds differ: \(description()): Core Graphics \(expectedBounds), lane \(bounds)", file: file, line: line)
        }
        XCTAssertEqual(lane.isEmpty, reference.isEmpty, description(), file: file, line: line)
        let current = lane.currentPoint, expectedCurrent = reference.currentPoint
        if !(same(current.x, expectedCurrent.x) && same(current.y, expectedCurrent.y)) {
            XCTFail("current points differ: \(description()): Core Graphics \(expectedCurrent), lane \(current)", file: file, line: line)
        }
    }
}
