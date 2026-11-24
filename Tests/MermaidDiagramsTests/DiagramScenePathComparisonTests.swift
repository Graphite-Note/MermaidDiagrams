/**
 * File: DiagramScenePathComparisonTests.swift
 * -------------------------------------------
 * Layer: Tests
 * Description: Seeded random coordinates, sizes, radii and angles for comparing scene paths with Core Graphics' paths,
 *              the comparison itself (every element's points and the bounds, to the bit), and the constants the scene
 *              paths take in place of the system's trigonometry and color conversion.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import CoreGraphics
import Darwin
import XCTest
@testable import MermaidDiagrams

/// Random values of the kinds diagrams draw with, and of kinds they never do: whole and quarter points, fractions,
/// large and negative numbers, zero and negative sizes, radii past half a side, multiples of a quarter turn.
struct DiagramScenePathSamples {
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
    mutating func addPrefix(kind: UInt64, to reference: CGMutablePath, _ path: inout DiagramScenePath) {
        switch kind % 5 {
        case 1:
            let start = point()
            reference.move(to: start)
            path.move(to: start)
        case 2:
            let start = point(), end = point()
            reference.move(to: start)
            reference.addLine(to: end)
            path.move(to: start)
            path.addLine(to: end)
        case 3:
            let rect = rectangle(), radius = radius()
            reference.addRoundedRect(in: rect, cornerWidth: radius, cornerHeight: radius)
            path.addRoundedRect(in: rect, cornerWidth: radius, cornerHeight: radius)
        case 4:
            let start = point()
            reference.move(to: start)
            reference.addLine(to: CGPoint(x: start.x + 3, y: start.y))
            reference.closeSubpath()
            path.move(to: start)
            path.addLine(to: CGPoint(x: start.x + 3, y: start.y))
            path.closeSubpath()
        default:
            break
        }
    }
}

/// The elements a path gives out, as `CGPathApply` gives them.
struct DiagramScenePathElements: Equatable {
    var kinds: [DiagramScenePathElement] = []
    var points: [CGPoint] = []

    init(_ path: DiagramScenePath) {
        path.forEachElement { kind, elementPoints in
            kinds.append(kind)
            points.append(contentsOf: elementPoints)
        }
    }

    init(_ path: CGPath) {
        self.init(DiagramScenePath(path))
    }

    /// The same kinds, and each point's coordinates equal, NaN equal to NaN.
    func matches(_ other: DiagramScenePathElements) -> Bool {
        kinds == other.kinds && points.count == other.points.count
            && zip(points, other.points).allSatisfy { first, second in Self.same(first.x, second.x) && Self.same(first.y, second.y) }
    }

    static func same(_ first: CGFloat, _ second: CGFloat) -> Bool {
        first == second || (first.isNaN && second.isNaN)
    }
}

extension XCTestCase {
    /// Fails unless `path` has `reference`'s elements and bounds, to the bit.
    func assertSameAsCoreGraphics(_ path: DiagramScenePath, _ reference: CGPath, _ description: @autoclosure () -> String,
                                  file: StaticString = #filePath, line: UInt = #line) {
        let expected = DiagramScenePathElements(reference)
        let made = DiagramScenePathElements(path)
        if !made.matches(expected) {
            XCTFail("elements differ: \(description())\n  Core Graphics \(expected.kinds) \(expected.points)\n  scene path \(made.kinds) \(made.points)",
                    file: file, line: line)
        }
        let bounds = path.boundingBoxOfPath, expectedBounds = reference.boundingBoxOfPath
        let same = DiagramScenePathElements.same
        if !(same(bounds.origin.x, expectedBounds.origin.x) && same(bounds.origin.y, expectedBounds.origin.y)
            && same(bounds.size.width, expectedBounds.size.width) && same(bounds.size.height, expectedBounds.size.height)) {
            XCTFail("bounds differ: \(description()): Core Graphics \(expectedBounds), scene path \(bounds)", file: file, line: line)
        }
    }
}

/// The values the scene paths look up instead of calling the system: they must be the system's own.
final class DiagramScenePathComparisonTests: XCTestCase {
    func testLookedUpSinesAndCosinesAreTheSystems() {
        for angle in [CGFloat.pi / 2, .pi, -CGFloat.pi / 2, -.pi, 0] {
            let looked = DiagramScenePathArithmetic.sineAndCosine(of: angle)
            let system = __sincos_stret(angle)
            XCTAssertEqual(Double(looked.sine).bitPattern, system.__sinval.bitPattern, "\(angle)")
            XCTAssertEqual(Double(looked.cosine).bitPattern, system.__cosval.bitPattern, "\(angle)")
        }
        XCTAssertEqual(DiagramScenePathArithmetic.halfPi, CGFloat.pi / 2)
        XCTAssertEqual(DiagramScenePathArithmetic.quarterPi, CGFloat.pi / 2 * 0.5)
        XCTAssertEqual(DiagramScenePathArithmetic.sine(of: DiagramScenePathArithmetic.quarterPi), sin(CGFloat.pi / 2 * 0.5))
        XCTAssertEqual(DiagramScenePathArithmetic.cosine(of: DiagramScenePathArithmetic.quarterPi), cos(CGFloat.pi / 2 * 0.5))
        var samples = DiagramScenePathSamples(seed: 0x51_4E)
        for _ in 0..<20_000 {
            let angle = samples.angle()
            let looked = DiagramScenePathArithmetic.sineAndCosine(of: angle)
            let system = __sincos_stret(angle)
            XCTAssertEqual(Double(looked.sine).bitPattern, system.__sinval.bitPattern, "\(angle)")
            XCTAssertEqual(Double(looked.cosine).bitPattern, system.__cosval.bitPattern, "\(angle)")
        }
    }

    func testAnglesAlongAnAxisAreAtan2s() {
        let lengths: [CGFloat] = [0, -0.0, 1, -1, 3.5, -1e-300, 1e300, .nan, .infinity, -.infinity, 4.440892098500626e-16]
        for across in lengths {
            for down in lengths {
                let looked = DiagramScenePathArithmetic.angle(across: across, down: down)
                let system = atan2(down, across)
                XCTAssertTrue(looked.bitPattern == system.bitPattern || (looked.isNaN && system.isNaN), "\(across) \(down)")
            }
        }
    }

    func testWrittenColorsAreWrittenAsTheirSRGBConversion() throws {
        var samples = DiagramScenePathSamples(seed: 0xC0_10)
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        for index in 0..<5_000 {
            let channel = { (value: UInt64) -> Double in index.isMultiple(of: 3) ? Double(value % 256) / 255 : Double(value % 10_000) / 9_000 - 0.05 }
            let color = DiagramColor(red: channel(samples.next()), green: channel(samples.next()), blue: channel(samples.next()))
            let converted = try XCTUnwrap(color.cgColor.converted(to: space, intent: .defaultIntent, options: nil))
            XCTAssertEqual(DiagramSVGColors.hexadecimal(color), DiagramSVGColors.hexadecimal(converted), "\(color)")
        }
    }
}
