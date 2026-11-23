/**
 * File: DiagramSVGNumberTests.swift
 * ---------------------------------
 * Layer: Tests
 * Description: The SVG buffer writes numbers, escaped text and path data exactly as the String functions of 0.6.1 did,
 *              kept here as the reference: edge values, a seeded sweep of values, every Unicode scalar, and paths.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import CoreGraphics
import Foundation
import XCTest
@testable import MermaidDiagrams

final class DiagramSVGNumberTests: XCTestCase {
    func testEdgeValuesAreWrittenAsTheReferenceWritesThem() {
        let values: [CGFloat] = [
            0, -0.0, 0.004, -0.004, 0.005, -0.005, 0.0049999, 0.015, -0.015, 1.005, 2.675, 0.1, 0.01, 0.5, -0.5, 0.95, 0.995,
            9.995, 12, 12.3, 12.30, 12.05, 12.5, 12.25, -0.25, -3, 10, 100, 1_000, 99.99, 100.001, 123_456.78, -98_765.4,
            999_999_999_999.99, 999_999_999_999.994, -999_999_999_999.99, 1e12, -1e12, 1e13, 1e300, -1e300,
            .nan, -.nan, .infinity, -.infinity, .greatestFiniteMagnitude, -.greatestFiniteMagnitude, .leastNonzeroMagnitude,
            -.leastNonzeroMagnitude, .leastNormalMagnitude, CGFloat(Int32.max), CGFloat(Int32.min), 1e11, 9.999_999_999_99e11
        ]
        for value in values {
            XCTAssertEqual(DiagramSVGSyntax.number(value), Self.referenceNumber(value), "\(value)")
        }
        XCTAssertEqual(DiagramSVGSyntax.number(-0.004), "0")
        XCTAssertEqual(DiagramSVGSyntax.number(12.30), "12.3")
        XCTAssertEqual(DiagramSVGSyntax.number(12.05), "12.05")
        XCTAssertEqual(DiagramSVGSyntax.number(1e12), "0")
        XCTAssertEqual(DiagramSVGSyntax.number(.nan), "0")
    }

    func testASeededSweepOfValuesIsWrittenAsTheReferenceWritesThem() {
        var generator = SeededGenerator(seed: 0x5EED_0F_5_7A1)
        for _ in 0..<200_000 {
            let exponent = Double(Int.random(in: -4...13, using: &generator))
            let mantissa = Double.random(in: -10...10, using: &generator)
            let value = CGFloat(mantissa * pow(10, exponent))
            XCTAssertEqual(DiagramSVGSyntax.number(value), Self.referenceNumber(value), "\(value)")
            // Values on and next to half hundredths, where rounding decides.
            let half = CGFloat(Int.random(in: -1_000_000...1_000_000, using: &generator)) / 100 + 0.005
            for nearby in [half, half.nextUp, half.nextDown] {
                XCTAssertEqual(DiagramSVGSyntax.number(nearby), Self.referenceNumber(nearby), "\(nearby)")
            }
        }
    }

    func testEveryUnicodeScalarIsEscapedAsTheReferenceEscapesIt() {
        var every = String.UnicodeScalarView()
        for value in UInt32(0)...0x10FFFF {
            if let scalar = Unicode.Scalar(value) { every.append(scalar) }
        }
        let text = String(every)
        XCTAssertEqual(DiagramSVGSyntax.escaped(text), Self.referenceEscaped(text))
    }

    func testTextIsEscapedAsTheReferenceEscapesIt() {
        let samples = [
            "", "plain label", "a & b", "<script>alert(\"x\")</script>", "it's", "tab\tline\nreturn\r\n", "\u{0}\u{1}\u{8}\u{B}\u{C}\u{1F}\u{7F}",
            "before\u{FFFE}middle\u{FFFF}after", "\u{FFFD}\u{FEFF}\u{FFFC}\u{EFFFF}", "\u{85}\u{9F}", "café ﬁ 日本語 🧭 e\u{301}",
            "\u{FFFF}", "\u{FFFE}x", "x\u{FFFF}", "ï\u{EF}", "]]> <!-- -->", String(repeating: "long label without anything ", count: 40)
        ]
        for sample in samples {
            XCTAssertEqual(DiagramSVGSyntax.escaped(sample), Self.referenceEscaped(sample), sample.debugDescription)
            let bridged = NSString(string: sample) as String
            XCTAssertEqual(DiagramSVGSyntax.escaped(bridged), Self.referenceEscaped(sample), "bridged \(sample.debugDescription)")
        }
        XCTAssertEqual(DiagramSVGSyntax.escaped("a\u{0}b\u{1B}c\u{FFFE}d\te\u{FFFD}"), "abcd\te\u{FFFD}")
    }

    func testPathDataIsWrittenAsTheReferenceWritesIt() {
        var generator = SeededGenerator(seed: 0xC0FFEE)
        for _ in 0..<500 {
            let path = CGMutablePath()
            func point() -> CGPoint {
                CGPoint(x: CGFloat.random(in: -2_000...2_000, using: &generator), y: CGFloat.random(in: -2_000...2_000, using: &generator))
            }
            path.move(to: point())
            for _ in 0..<Int.random(in: 0...12, using: &generator) {
                switch Int.random(in: 0...4, using: &generator) {
                case 0: path.addLine(to: point())
                case 1: path.addQuadCurve(to: point(), control: point())
                case 2: path.addCurve(to: point(), control1: point(), control2: point())
                case 3: path.closeSubpath()
                default: path.move(to: point())
                }
            }
            XCTAssertEqual(DiagramSVGSyntax.pathData(path), Self.referencePathData(path))
        }
        let rounded = CGPath(roundedRect: CGRect(x: 0.004, y: -0.005, width: 1e12, height: 12.30), cornerWidth: 3, cornerHeight: 3, transform: nil)
        XCTAssertEqual(DiagramSVGSyntax.pathData(rounded), Self.referencePathData(rounded))
        XCTAssertEqual(DiagramSVGSyntax.pathData(CGMutablePath()), "")
    }

    func testAStrokeWithDashesAndAnOpacityIsWrittenAsTheReferenceWritesIt() {
        var buffer = DiagramSVGBuffer()
        buffer.appendNumbers([4, 2.5, 0.004, 12.05])
        buffer.appendOpacity(0.4, attribute: "fill-opacity")
        buffer.appendOpacity(1, attribute: "fill-opacity")
        buffer.appendOpacity(-0.2, attribute: "stroke-opacity")
        XCTAssertEqual(buffer.text, "4 2.5 0 12.05 fill-opacity=\"0.4\" stroke-opacity=\"0\"")
    }

    // MARK: The functions of 0.6.1, as the reference

    /// `DiagramSVGSyntax.number` as 0.6.1 wrote it.
    private static func referenceNumber(_ value: CGFloat) -> String {
        guard value.isFinite, abs(value) < 1e12 else { return "0" }
        let hundredths = Int((value * 100).rounded())
        guard hundredths != 0 else { return "0" }
        let magnitude = abs(hundredths)
        let whole = magnitude / 100
        let fraction = magnitude % 100
        let sign = hundredths < 0 ? "-" : ""
        switch fraction {
        case 0: return "\(sign)\(whole)"
        case let tenths where tenths.isMultiple(of: 10): return "\(sign)\(whole).\(tenths / 10)"
        case ..<10: return "\(sign)\(whole).0\(fraction)"
        default: return "\(sign)\(whole).\(fraction)"
        }
    }

    /// `DiagramSVGSyntax.escaped` as 0.6.1 wrote it.
    private static func referenceEscaped(_ text: String) -> String {
        func isAllowedInXML(_ scalar: Unicode.Scalar) -> Bool {
            switch scalar.value {
            case 0x9, 0xA, 0xD: true
            case 0x0...0x1F, 0x7F, 0xFFFE, 0xFFFF: false
            default: true
            }
        }
        func needsEscaping(_ scalar: Unicode.Scalar) -> Bool {
            switch scalar {
            case "&", "<", ">", "\"", "'": true
            default: !isAllowedInXML(scalar)
            }
        }
        guard text.unicodeScalars.contains(where: needsEscaping) else { return text }
        var escaped = ""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "&": escaped += "&amp;"
            case "<": escaped += "&lt;"
            case ">": escaped += "&gt;"
            case "\"": escaped += "&quot;"
            case "'": escaped += "&#39;"
            default: if isAllowedInXML(scalar) { escaped.unicodeScalars.append(scalar) }
            }
        }
        return escaped
    }

    /// `DiagramSVGSyntax.pathData` as 0.6.1 wrote it.
    private static func referencePathData(_ path: CGPath) -> String {
        func pair(_ point: CGPoint) -> String {
            referenceNumber(point.x) + " " + referenceNumber(point.y)
        }
        var data = ""
        path.applyWithBlock { element in
            let points = element.pointee.points
            switch element.pointee.type {
            case .moveToPoint: data += "M" + pair(points[0])
            case .addLineToPoint: data += "L" + pair(points[0])
            case .addQuadCurveToPoint: data += "Q" + pair(points[0]) + " " + pair(points[1])
            case .addCurveToPoint: data += "C" + pair(points[0]) + " " + pair(points[1]) + " " + pair(points[2])
            case .closeSubpath: data += "Z"
            @unknown default: break
            }
        }
        return data
    }
}

/// SplitMix64: the same values on every run.
private struct SeededGenerator: RandomNumberGenerator {
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
}
