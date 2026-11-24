/**
 * File: ReferenceDiagramElementStyle.swift
 * ----------------------------------------
 * Layer: Tests
 * Description: MermaidDiagrams 0.7.0's reading of a list of style declarations (DiagramElementStyle.reading), frozen
 *              as the reference: through the list's characters, each color read by the frozen color reader.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
import Foundation
@testable import MermaidDiagrams

/// The style a list of declarations writes, as 0.7.0 read it.
enum ReferenceDiagramElementStyle {
    /// The properties set so far.
    private struct Style {
        var fill: DiagramColor?
        var stroke: DiagramColor?
        var strokeWidth: CGFloat?
        var strokeDashLengths: [CGFloat]?
        var textColor: DiagramColor?

        var read: DiagramElementStyle {
            DiagramElementStyle(fill: fill, stroke: stroke, strokeWidth: strokeWidth, strokeDashLengths: strokeDashLengths, textColor: textColor)
        }

        /// Sets the property to the value written; false when the property or the value is not read.
        mutating func set(_ property: String, to value: String) -> Bool {
            switch property {
            case "fill":
                guard let color = ReferenceDiagramColor.color(cssText: value) else { return false }
                fill = color
            case "stroke":
                guard let color = ReferenceDiagramColor.color(cssText: value) else { return false }
                stroke = color
            case "color":
                guard let color = ReferenceDiagramColor.color(cssText: value) else { return false }
                textColor = color
            case "stroke-width":
                guard let width = ReferenceDiagramElementStyle.length(value), width >= 0, width <= DiagramElementStyle.largestStrokeWidth else { return false }
                strokeWidth = width
            case "stroke-dasharray":
                guard let lengths = ReferenceDiagramElementStyle.lengths(value) else { return false }
                strokeDashLengths = lengths
            default:
                return false
            }
            return true
        }
    }

    /// The style a list of declarations writes (`fill:#f9f,stroke:#333,stroke-width:4px,color:#fff,stroke-dasharray: 5 5`), and
    /// whether some declaration was not applied: a property this look has no place for (`font-size`) or a value not read.
    static func reading(_ declarations: String) -> (style: DiagramElementStyle, hasUnappliedDeclaration: Bool) {
        var style = Style()
        var hasUnappliedDeclaration = false
        for (property, written) in propertiesAndValues(declarations) {
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
        return (style.read, hasUnappliedDeclaration)
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

    /// `4px` or `4`, in points.
    fileprivate static func length(_ text: String) -> CGFloat? {
        let digits = text.hasSuffix("px") ? String(text.dropLast(2)) : text
        guard let number = Double(digits.trimmingCharacters(in: .whitespaces)), number.isFinite else { return nil }
        return CGFloat(number)
    }

    /// `5 5`, `5px 3px`: dashes and gaps. `none` is a solid line (no dashes); a list with a nonpositive length or only zeros is not one,
    /// and neither is one past the bounds above.
    fileprivate static func lengths(_ text: String) -> [CGFloat]? {
        if text.lowercased() == "none" { return [] }
        let parts = text.split(whereSeparator: { character in character == " " || character == "\t" })
        guard parts.count <= DiagramElementStyle.largestDashLengthCount else { return nil }
        let lengths = parts.compactMap { part in length(String(part)) }
        let allAreUsable = lengths.count == parts.count && lengths.allSatisfy { length in length >= 0 && length <= DiagramElementStyle.largestDashLength }
        guard allAreUsable, lengths.reduce(0, +) >= DiagramElementStyle.shortestDashPattern else { return nil }
        return lengths
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
