/**
 * File: VennAppearance.swift
 * --------------------------
 * Layer: Core
 * Description: What a Venn diagram's `style` statements make of a set, an overlap or a text, as Pele's resolveStyle
 *              splits them between a shape and its text, and the text color Pele's ink picks over a fill.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */

import CoreGraphics
import Foundation

/// The look a Venn diagram's styles give one target: its fill and stroke with their opacities, its text color, and
/// whether any of a shape's properties is written at all (an overlap is outlined only then).
public struct VennAppearance: Equatable, Sendable {
    public internal(set) var fill: DiagramColor?
    public internal(set) var fillOpacity: Double?
    public internal(set) var stroke: DiagramColor?
    public internal(set) var strokeOpacity: Double?
    public internal(set) var strokeWidth: CGFloat?
    public internal(set) var strokeDashLengths: [CGFloat]?
    /// `opacity`: of the shape and of its text.
    public internal(set) var opacity: Double?
    /// `color`: the text's.
    public internal(set) var textColor: DiagramColor?
    /// `font-weight` bold, bolder or from 600, and `font-style` italic: the text's, as Pele's `resolveStyle` reads them.
    public internal(set) var isBold = false
    public internal(set) var isItalic = false
    /// Whether a property of the shape is written with a value (`style.shape !== ''` in Pele), read here or not.
    public internal(set) var hasShapeDeclaration = false
    /// Whether `fill-opacity` is written, read or not.
    public internal(set) var writesFillOpacity = false
    /// Whether `color` is written, read or not: a text that writes one keeps it over the color picked for its fill.
    public internal(set) var writesTextColor = false
    /// Whether `fill-opacity` or `opacity` is written as something other than a plain number, which may still be low.
    public internal(set) var writesUnreadOpacity = false

    /// The properties of a shape, as Pele's `SHAPE_PROPS`.
    static let shapeProperties: Set<String> = ["fill", "fill-opacity", "stroke", "stroke-width", "stroke-dasharray", "stroke-dashoffset",
                                               "stroke-linecap", "stroke-linejoin", "stroke-opacity", "opacity", "rx", "ry"]

    /// The look of `declarations` in order, a later one of a property winning: `fill`, `stroke`, `stroke-width`,
    /// `stroke-dasharray` and `color` as a flowchart's are read, the opacities as numbers from 0 to 1 or percentages.
    init(_ declarations: [VennStyleDeclaration]) {
        for declaration in declarations {
            let property = declaration.property.lowercased()
            let value = Self.valueWithoutImportance(declaration.value)
            guard !value.isEmpty, !Self.isUnsafe(value) else { continue }
            if Self.shapeProperties.contains(property) { hasShapeDeclaration = true }
            if property == "fill-opacity" { writesFillOpacity = true }
            if property == "color" { writesTextColor = true }
            apply(property, value)
        }
    }

    init() {}

    private mutating func apply(_ property: String, _ value: String) {
        switch property {
        case "fill-opacity":
            fillOpacity = Self.amount(value)
            if fillOpacity == nil { writesUnreadOpacity = true }
        case "stroke-opacity": strokeOpacity = Self.amount(value)
        case "opacity":
            opacity = Self.amount(value)
            if opacity == nil { writesUnreadOpacity = true }
        case "fill", "stroke", "stroke-width", "stroke-dasharray", "color":
            let style = DiagramElementStyle.reading(property + ":" + value).style
            switch property {
            case "fill": fill = style.fill ?? Self.functionColor(value)
            case "stroke": stroke = style.stroke ?? Self.functionColor(value)
            case "stroke-width": strokeWidth = style.strokeWidth
            case "stroke-dasharray": strokeDashLengths = style.strokeDashLengths
            default: textColor = style.textColor ?? Self.functionColor(value)
            }
        case "font-weight": isBold = value == "bold" || value == "bolder" || (Double(value).map { weight in weight >= Self.boldWeight } ?? false)
        case "font-style": isItalic = value == "italic"
        default: break
        }
    }

    /// Whether the declaration is drawn as Pele draws it: its property is one read here and its value is of its form, or
    /// its value is one Pele leaves out too.
    static func applies(_ declaration: VennStyleDeclaration) -> Bool {
        let property = declaration.property.lowercased()
        let value = valueWithoutImportance(declaration.value)
        if isUnsafe(value) { return true }
        switch property {
        case "fill-opacity", "stroke-opacity", "opacity": return amount(value) != nil
        case "fill", "stroke", "color":
            return !DiagramElementStyle.reading(property + ":" + value).hasUnappliedDeclaration || functionColor(value) != nil
        case "stroke-width", "stroke-dasharray":
            return !DiagramElementStyle.reading(property + ":" + value).hasUnappliedDeclaration
        case "font-weight": return ["bold", "bolder", "normal", "400"].contains(value) || (Double(value).map { weight in weight >= boldWeight } ?? false)
        case "font-style": return value == "italic" || value == "normal"
        default: return false
        }
    }

    /// Whether Pele leaves the value out of a style as if it were not written (its `RE_UNSAFE` and `RE_INVALID_XML`): a
    /// `url(`, `expression(`, `javascript:`, `@import` or `image-set`, a comment, one of `<>{};\`, or a control character
    /// that XML does not allow.
    static func isUnsafe(_ value: String) -> Bool {
        if value.range(of: unsafePattern, options: [.regularExpression, .caseInsensitive]) != nil { return true }
        return value.unicodeScalars.contains { scalar in
            let code = scalar.value
            return code <= 0x08 || code == 0x0B || code == 0x0C || (0x0E...0x1F).contains(code) || code == 0x7F || code == 0xFFFE || code == 0xFFFF
        }
    }

    private static let unsafePattern = #"url\s*\(|expression\s*\(|javascript:|[<>{};\\]|@import|image-set|/\*"#

    /// The weight from which a text is bold, as Pele's `resolveStyle` reads `font-weight`.
    static let boldWeight = 600.0

    /// A color written as CSS's `hsl(…)`, `hsla(…)` or `rgb(…)` with spaces, which a style's other colors do not read. The
    /// comma syntax takes, as CSS and Pele's `ink` do, an hsl()'s saturation and lightness in percent and an rgb()'s
    /// channels all in percent or none.
    private static func functionColor(_ value: String) -> DiagramColor? {
        guard value.hasSuffix(")"), let opening = value.firstIndex(of: "(") else { return nil }
        let arguments = value[value.index(after: opening)..<value.index(before: value.endIndex)]
        if arguments.contains(",") {
            let isHSL = value.lowercased().hasPrefix("hsl")
            let channels = arguments.split(separator: ",", omittingEmptySubsequences: false).prefix(3).dropFirst(isHSL ? 1 : 0)
            let percentCount = channels.filter { channel in PlaneMapText.trimmed(String(channel)).hasSuffix("%") }.count
            guard isHSL ? percentCount == 2 : percentCount == 0 || percentCount == 3 else { return nil }
        }
        return SequenceHighlightColorSyntax.color(from: value).map { color in DiagramColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha) }
    }

    /// `!important` taken out, as Pele takes it out, and the spaces at the ends.
    private static func valueWithoutImportance(_ value: String) -> String {
        PlaneMapText.trimmed(value.replacingOccurrences(of: "!important", with: "", options: .caseInsensitive))
    }

    /// A plain number from 0 to 1, or a percentage, clamped to 0 to 1; nil for anything else (`calc(…)`).
    static func amount(_ value: String) -> Double? {
        let isPercentage = value.hasSuffix("%")
        let digits = isPercentage ? String(value.dropLast()) : value
        guard digits.utf8.allSatisfy({ byte in PlaneMapByte.isDigit(byte) || numberPunctuation.contains(byte) }),
              let number = Double(digits), number.isFinite else { return nil }
        return min(max(number / (isPercentage ? 100 : 1), 0), 1)
    }

    /// What a plain number may hold besides digits: a sign, a point, an exponent.
    private static let numberPunctuation: Set<UInt8> = [PlaneMapByte.plus, PlaneMapByte.hyphen, PlaneMapByte.period, UInt8(ascii: "e"), UInt8(ascii: "E")]

    /// The text color Pele's `ink` picks over this look's fill for text whose own look is `text`: the dark or the light
    /// text color by the fill's luminance, when the fill is a color read, at least half opaque, and the text sets no color
    /// of its own; nil otherwise, and the text keeps its usual color.
    func ink(forTextOf text: VennAppearance) -> DiagramColor? {
        guard !text.writesTextColor, !writesUnreadOpacity, let fill, fill.alpha * (fillOpacity ?? 1) * (opacity ?? 1) >= 0.5 else { return nil }
        return Self.luminance(of: fill) > Self.evenLuminance ? Self.textOnLight : Self.textOnDark
    }

    /// Pele's `--pele-fg-on-light` and `--pele-fg-on-dark` fallbacks: #1f1f1f and white.
    static let textOnLight = DiagramColor(red: 31.0 / 255, green: 31.0 / 255, blue: 31.0 / 255)
    static let textOnDark = DiagramColor(red: 1, green: 1, blue: 1)

    private static func linear(_ channel: Double) -> Double {
        channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }

    static func luminance(of color: DiagramColor) -> Double {
        0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
    }

    /// The luminance where #1f1f1f and white contrast equally.
    static let evenLuminance = (1.05 * (luminance(of: textOnLight) + 0.05)).squareRoot() - 0.05
}
