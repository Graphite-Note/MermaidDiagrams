/**
 * File: ReferenceQuadrantChartPointStyleSyntax.swift
 * --------------------------------------------------
 * Layer: Tests
 * Description: MermaidDiagrams 0.7.0's quadrant reader (its point style syntax), frozen as main dad6fb8 had it: the
 *              reference the quadrant reader is proven against (QuadrantChartReaderEquivalenceTests).
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

@testable import MermaidDiagrams

/// Reads the styles a quadrant chart's point or `classDef` writes, as Mermaid's quadrant database does: `radius: 10`
/// (whole points), `color: #ff3300` and `stroke-color: #10f0f0` (six or three hexadecimal digits, the `#` optional) and
/// `stroke-width: 5px`. Another name, or a value of the wrong form, is an error, as in Mermaid.
enum ReferenceQuadrantChartPointStyleSyntax {
    /// The styles `styles` give, each read as `name: value`; a later style of a name replaces an earlier one.
    static func style(from styles: [String], line: Int) throws(MermaidDiagramReadError) -> QuadrantChartPointStyle {
        var style = QuadrantChartPointStyle()
        for written in styles {
            let (name, value) = nameAndValue(written)
            var invalid: MermaidDiagramReadError { .invalidSyntax(line: line, problem: .invalidPointStyleValue(name: name, value: value)) }
            switch name {
            case radiusName:
                guard let radius = wholeNumber(value) else { throw invalid }
                style.radius = radius
            case colorName:
                guard let color = color(value) else { throw invalid }
                style.color = color
            case strokeColorName:
                guard let color = color(value) else { throw invalid }
                style.strokeColor = color
            case strokeWidthName:
                guard value.hasSuffix(pixelUnit), let width = wholeNumber(String(value.dropLast(pixelUnit.count))) else { throw invalid }
                style.strokeWidth = width
            default:
                throw .invalidSyntax(line: line, problem: .unsupportedPointStyle(name: name))
            }
        }
        return style
    }

    /// The name before the first colon and the value after it up to a second colon, without the spaces around them;
    /// `undefined` as the value when there is no colon, as Mermaid's split leaves it.
    static func nameAndValue(_ written: String) -> (name: String, value: String) {
        let trimmed = spaceTrimmed(written[...])
        guard let colon = trimmed.utf8.firstIndex(of: MermaidByte.colon) else { return (String(trimmed), missingValue) }
        let rest = trimmed[trimmed.utf8.index(after: colon)...]
        let value = rest.utf8.firstIndex(of: MermaidByte.colon).map { nextColon in rest[..<nextColon] } ?? rest
        return (String(spaceTrimmed(trimmed[..<colon])), String(spaceTrimmed(value)))
    }

    /// `text` without the spaces, tabs, vertical tabs and form feeds at its ends: the only white space a style's
    /// tokens hold.
    private static func spaceTrimmed(_ text: Substring) -> Substring {
        let bytes = text.utf8
        // In ASCII each byte is a character of its own, so the bytes are trimmed; beyond it, a blank may begin or end a
        // character with more in it, and the characters are dropped.
        if bytes.allSatisfy({ byte in byte < 0x80 }) {
            var start = bytes.startIndex
            var end = bytes.endIndex
            while start < end, isSpace(bytes[start]) { start = bytes.index(after: start) }
            while start < end, isSpace(bytes[bytes.index(before: end)]) { end = bytes.index(before: end) }
            return text[start..<end]
        }
        var trimmed = text
        while let first = trimmed.utf8.first, isSpace(first) { trimmed = trimmed.dropFirst() }
        while let last = trimmed.utf8.last, isSpace(last) { trimmed = trimmed.dropLast() }
        return trimmed
    }

    private static func isSpace(_ byte: UInt8) -> Bool {
        MermaidByte.isSpace(byte) || byte == verticalTab || byte == formFeed
    }

    /// Digits only, as a number of points; a number too large for an integer is the largest one.
    private static func wholeNumber(_ text: String) -> Double? {
        guard !text.isEmpty, text.utf8.allSatisfy(MermaidByte.isDigit) else { return nil }
        return Double(text)
    }

    /// Six or three hexadecimal digits, the `#` before them optional; three stand for each one doubled.
    private static func color(_ text: String) -> QuadrantChartColor? {
        let digits = text.hasPrefix("#") ? text.utf8.dropFirst() : text.utf8[...]
        guard digits.count == 6 || digits.count == 3 else { return nil }
        // The digits' values, in lanes of a vector rather than an array.
        var values = SIMD8<UInt8>()
        var lane = 0
        for digit in digits {
            guard let value = hexadecimalValue(digit) else { return nil }
            values[lane] = value
            lane += 1
        }
        if lane == 3 {
            return QuadrantChartColor(red: values[0] * shortDigitScale, green: values[1] * shortDigitScale, blue: values[2] * shortDigitScale)
        }
        return QuadrantChartColor(red: values[0] * 16 + values[1], green: values[2] * 16 + values[3], blue: values[4] * 16 + values[5])
    }

    private static func hexadecimalValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): byte - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): byte - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): byte - UInt8(ascii: "A") + 10
        default: nil
        }
    }

    /// A short color's digit stands for itself twice: `f` for `ff`, 15 × 17 = 255.
    private static let shortDigitScale: UInt8 = 17
    private static let radiusName = "radius"
    private static let colorName = "color"
    private static let strokeColorName = "stroke-color"
    private static let strokeWidthName = "stroke-width"
    private static let pixelUnit = "px"
    private static let missingValue = "undefined"
    private static let verticalTab: UInt8 = 0x0B
    private static let formFeed: UInt8 = 0x0C
}
