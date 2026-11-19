/**
 * File: GanttTodayLineStyle.swift
 * -------------------------------
 * Layer: Core
 * Description: The style a Gantt chart's `todayMarker` declarations give today's line, as Pele reads them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// How `todayMarker stroke:red,stroke-width:3px` restyles today's line, as Pele's `resolveStyle(…).line` reads the declarations
/// (split at commas): a property of a shape other than its fill (`stroke`, `stroke-width`, `stroke-dasharray`,
/// `stroke-dashoffset`, `stroke-linecap`, `stroke-linejoin`, `stroke-opacity`, `opacity`, `rx`, `ry`) with a value that is
/// not empty or unsafe (`url(`, `expression(`, `javascript:`, `<`, `>`, `{`, `}`, `;`, `\`, `@import`, `image-set`, `/*`)
/// makes the line a styled one: Pele then leaves out the small triangle on top of it. A color, width, dashes, caps, joins and
/// opacities that read are applied to the line; the others (a dash offset, rounded corners, a color form not read) change
/// nothing.
public struct GanttTodayLineStyle: Equatable, Sendable {
    public internal(set) var color: DiagramColor?
    public internal(set) var lineWidth: CGFloat?
    public internal(set) var dashLengths: [CGFloat]?
    public internal(set) var lineCap: CGLineCap?
    public internal(set) var lineJoin: CGLineJoin?
    /// The line's own opacity, from `opacity` and `stroke-opacity` together.
    public internal(set) var opacity: CGFloat?

    /// The properties of a line: a shape's but its fill.
    private static let lineProperties: Set<String> = ["stroke", "stroke-width", "stroke-dasharray", "stroke-dashoffset", "stroke-linecap",
                                                      "stroke-linejoin", "stroke-opacity", "opacity", "rx", "ry"]
    private static let unsafeFragments = ["url(", "expression(", "javascript:", "<", ">", "{", "}", ";", "\\", "@import", "image-set", "/*"]
    /// The widest a line may be styled.
    private static let largestLineWidth: CGFloat = 16

    /// The style the declarations write, or nil when none of them is for a line (the standard line is then drawn, with its
    /// triangle).
    init?(declarations: String) {
        var isStyled = false
        for declaration in declarations.split(separator: ",", omittingEmptySubsequences: false) {
            guard let colon = declaration.firstIndex(of: ":"), colon != declaration.startIndex else { continue }
            let property = declaration[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            var value = declaration[declaration.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            while let importance = value.range(of: "!important", options: .caseInsensitive) { value.removeSubrange(importance) }
            value = value.trimmingCharacters(in: .whitespaces)
            let lowered = value.lowercased()
            guard Self.lineProperties.contains(property), !value.isEmpty, !Self.unsafeFragments.contains(where: { fragment in lowered.contains(fragment) }) else { continue }
            isStyled = true
            apply(property, value)
        }
        guard isStyled else { return nil }
    }

    private mutating func apply(_ property: String, _ value: String) {
        switch property {
        case "stroke": color = DiagramColor(cssText: value)
        case "stroke-width": lineWidth = Self.length(value).map { width in min(width, Self.largestLineWidth) }
        case "stroke-dasharray": dashLengths = Self.dashes(value)
        case "stroke-linecap": lineCap = ["butt": CGLineCap.butt, "round": .round, "square": .square][value.lowercased()]
        case "stroke-linejoin": lineJoin = ["miter": CGLineJoin.miter, "round": .round, "bevel": .bevel][value.lowercased()]
        case "stroke-opacity", "opacity":
            if let opacity = Double(value), opacity.isFinite { self.opacity = (self.opacity ?? 1) * CGFloat(min(1, max(0, opacity))) }
        default: break
        }
    }

    /// `3px` or `3`, in points, not negative.
    private static func length(_ text: String) -> CGFloat? {
        let digits = text.hasSuffix("px") ? String(text.dropLast(2)) : text
        guard let number = Double(digits.trimmingCharacters(in: .whitespaces)), number.isFinite, number >= 0 else { return nil }
        return CGFloat(number)
    }

    /// `4 3`, `4px, 3px`: dashes and gaps; `none` is a solid line. A list that is empty, too long, or whose lengths do not
    /// read or add up to under 2 points is not applied.
    private static func dashes(_ text: String) -> [CGFloat]? {
        if text.lowercased() == "none" { return [] }
        let parts = text.split(whereSeparator: { character in character == " " || character == "\t" || character == "," })
        guard (1...16).contains(parts.count) else { return nil }
        let lengths = parts.compactMap { part in length(String(part)) }
        guard lengths.count == parts.count, lengths.allSatisfy({ length in length <= 1_000 }), lengths.reduce(0, +) >= 2 else { return nil }
        return lengths
    }
}
