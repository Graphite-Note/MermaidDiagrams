/**
 * File: DiagramElementStyle.swift
 * -------------------------------
 * Layer: Core
 * Description: How a diagram's statements change the look of one node or edge.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 23/11/2026
 */

import CoreGraphics

/// How a diagram's own statements (`classDef`, `class`, `:::class`, `style`, `linkStyle`) change the look of one node or
/// edge: what each property sets, or nil for the diagram's usual look. Colors are the ones written, in any theme.
public struct DiagramElementStyle: Equatable, Sendable {
    /// `fill`: inside a node.
    public internal(set) var fill: DiagramColor?
    /// `stroke`: a node's outline, or an edge's line and marks.
    public internal(set) var stroke: DiagramColor?
    /// `stroke-width`, in points.
    public internal(set) var strokeWidth: CGFloat?
    /// `stroke-dasharray`: the dashes and gaps, in points.
    public internal(set) var strokeDashLengths: [CGFloat]?
    /// `color`: a node's text.
    public internal(set) var textColor: DiagramColor?

    public init(fill: DiagramColor? = nil, stroke: DiagramColor? = nil, strokeWidth: CGFloat? = nil, strokeDashLengths: [CGFloat]? = nil,
                textColor: DiagramColor? = nil) {
        self.fill = fill
        self.stroke = stroke
        self.strokeWidth = strokeWidth
        self.strokeDashLengths = strokeDashLengths
        self.textColor = textColor
    }

    /// Whether it sets nothing.
    public var isEmpty: Bool {
        self == DiagramElementStyle()
    }

    /// This style with what `later` sets over it, property by property: a class's properties, then the node's own `style`.
    func overridden(by later: DiagramElementStyle) -> DiagramElementStyle {
        DiagramElementStyle(fill: later.fill ?? fill, stroke: later.stroke ?? stroke, strokeWidth: later.strokeWidth ?? strokeWidth,
                            strokeDashLengths: later.strokeDashLengths ?? strokeDashLengths, textColor: later.textColor ?? textColor)
    }

    /// The style a list of declarations writes (`fill:#f9f,stroke:#333,stroke-width:4px,color:#fff,stroke-dasharray: 5 5`), and
    /// whether some declaration was not applied: a property this look has no place for (`font-size`) or a value not read.
    static func reading(_ declarations: String) -> (style: DiagramElementStyle, hasUnappliedDeclaration: Bool) {
        var style = DiagramElementStyle()
        var hasUnappliedDeclaration = false
        for (property, written) in asciiPropertiesAndValues(declarations) ?? propertiesAndValues(declarations) {
            guard let property else {
                if !written.isEmpty { hasUnappliedDeclaration = true }
                continue
            }
            var value = written
            if value.utf8.contains(MermaidByte.exclamationMark), let importance = value.range(of: "!important", options: .caseInsensitive) {
                value = value[..<importance.lowerBound].trimmingCharacters(in: .whitespaces)
            }
            if !style.set(property, to: value) { hasUnappliedDeclaration = true }
        }
        return (style, hasUnappliedDeclaration)
    }

    /// Each declaration's property, trimmed and in lower case, and its value, trimmed; a declaration without a colon has
    /// no property and its text trimmed as its value.
    static func propertiesAndValues(_ declarations: String) -> [(property: String?, value: String)] {
        commaSeparated(declarations).map { declaration in
            guard let colon = declaration.firstIndex(of: ":") else { return (nil, declaration.trimmingCharacters(in: .whitespaces)) }
            return (declaration[..<colon].trimmingCharacters(in: .whitespaces).lowercased(),
                    declaration[declaration.index(after: colon)...].trimmingCharacters(in: .whitespaces))
        }
    }

    /// Sets the property to the value written; false when the property or the value is not read.
    private mutating func set(_ property: String, to value: String) -> Bool {
        switch property {
        case "fill":
            guard let color = DiagramColor(cssText: value) else { return false }
            fill = color
        case "stroke":
            guard let color = DiagramColor(cssText: value) else { return false }
            stroke = color
        case "color":
            guard let color = DiagramColor(cssText: value) else { return false }
            textColor = color
        case "stroke-width":
            guard let width = Self.length(value), width >= 0, width <= Self.largestStrokeWidth else { return false }
            strokeWidth = width
        case "stroke-dasharray":
            guard let lengths = Self.lengths(value) else { return false }
            strokeDashLengths = lengths
        default:
            return false
        }
        return true
    }

    /// `4px` or `4`, in points.
    private static func length(_ text: String) -> CGFloat? {
        let digits = text.hasSuffix("px") ? String(text.dropLast(2)) : text
        guard let number = Double(digits.trimmingCharacters(in: .whitespaces)), number.isFinite else { return nil }
        return CGFloat(number)
    }

    /// The widest line a style may ask for: wider, an outline covers its node's text and an edge the nodes it joins.
    static let largestStrokeWidth: CGFloat = 16
    /// The most dashes and gaps a dash pattern may list, and the longest each may be.
    static let largestDashLengthCount = 16
    static let largestDashLength: CGFloat = 1_000
    /// The shortest a whole pattern of dashes and gaps may be: a shorter one would have a line drawn as millions of
    /// dashes, which takes Core Graphics seconds to paint.
    static let shortestDashPattern: CGFloat = 2

    /// `5 5`, `5px 3px`: dashes and gaps. `none` is a solid line (no dashes); a list with a nonpositive length or only zeros is not one,
    /// and neither is one past the bounds above.
    private static func lengths(_ text: String) -> [CGFloat]? {
        if text.lowercased() == "none" { return [] }
        let parts = text.split(whereSeparator: { character in character == " " || character == "\t" })
        guard parts.count <= largestDashLengthCount else { return nil }
        let lengths = parts.compactMap { part in length(String(part)) }
        let allAreUsable = lengths.count == parts.count && lengths.allSatisfy { length in length >= 0 && length <= largestDashLength }
        guard allAreUsable, lengths.reduce(0, +) >= shortestDashPattern else { return nil }
        return lengths
    }

    /// The declarations of an ASCII list read from its bytes, as `propertiesAndValues` reads them from its characters:
    /// in ASCII a character is a byte, `.whitespaces` a space or a tab and lowering a byte's own. Nil for text beyond
    /// ASCII.
    static func asciiPropertiesAndValues(_ declarations: String) -> [(property: String?, value: String)]? {
        var text = declarations
        return text.withUTF8 { bytes -> [(property: String?, value: String)]? in
            guard !bytes.contains(where: { byte in byte >= 0x80 }) else { return nil }
            func trimmed(_ range: Range<Int>, lowered: Bool = false) -> String {
                var start = range.lowerBound
                var end = range.upperBound
                while start < end, bytes[start] == MermaidByte.space || bytes[start] == MermaidByte.tab { start += 1 }
                while end > start, bytes[end - 1] == MermaidByte.space || bytes[end - 1] == MermaidByte.tab { end -= 1 }
                guard lowered else { return String(decoding: UnsafeBufferPointer(rebasing: bytes[start..<end]), as: UTF8.self) }
                return String(decoding: bytes[start..<end].map(MermaidByte.lowercased), as: UTF8.self)
            }
            var read: [(property: String?, value: String)] = []
            var start = 0
            var depth = 0
            for index in 0...bytes.count {
                if index < bytes.count {
                    let byte = bytes[index]
                    if byte == UInt8(ascii: "(") { depth += 1 } else if byte == UInt8(ascii: ")") { depth = max(0, depth - 1) }
                    guard byte == MermaidByte.comma, depth == 0 else { continue }
                }
                if let colon = bytes[start..<index].firstIndex(of: MermaidByte.colon) {
                    read.append((trimmed(start..<colon, lowered: true), trimmed((colon + 1)..<index)))
                } else {
                    read.append((nil, trimmed(start..<index)))
                }
                start = index + 1
            }
            return read
        }
    }

    /// The text split at commas outside parentheses, so `rgb(1, 2, 3)` stays whole.
    private static func commaSeparated(_ text: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0
        for character in text {
            if character == "(" { depth += 1 } else if character == ")" { depth = max(0, depth - 1) }
            if character == ",", depth == 0 {
                parts.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        parts.append(current)
        return parts
    }
}
