/**
 * File: BlockAppearance.swift
 * ---------------------------
 * Layer: Core
 * Description: What a block's classes and style set for its look, as Pele's resolveStyle reads them: colors, its line,
 *              its text in bold, italic or at its own size, and the text color Pele picks on a fill it sets.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */

import CoreGraphics

/// A block's look, from its classes (or the `default` class, for a block that has none) and then its own `style`, each
/// declaration as Pele's `resolveStyle` takes it: the property before the first colon, the value after it without
/// `!important`, a later one over an earlier (and a later one whose value is not read leaving the property unset).
public struct BlockAppearance: Equatable, Sendable {
    /// Its fill, outline, line width and dashes, and its text's color.
    public internal(set) var style = DiagramElementStyle()
    public internal(set) var isBold = false
    public internal(set) var isItalic = false
    /// `font-size` in points (`14` or `14px`), above zero and at most 200; nil for the diagram's size.
    public internal(set) var fontSize: CGFloat?

    /// The appearance of a block of `classNames` with `styles`, `classes` the diagram's definitions.
    init(classNames: [String]?, styles: [String]?, classes: [String: BlockClassDefinition]) {
        let names = classNames.flatMap { names in names.isEmpty ? nil : names } ?? ["default"]
        for name in names {
            for style in classes[name]?.styles ?? [] { apply(style) }
        }
        for style in styles ?? [] { apply(style) }
    }

    init() {}

    /// The color Pele writes the text in: the style's `color`, else its dark or white text on a fill the style sets at
    /// half opacity or more, by which contrasts more; nil for the usual color.
    public var textColor: DiagramColor? {
        if let color = style.textColor { return color }
        return style.fill.flatMap(SequenceTextInk.ink(onColor:))
    }

    /// Each declaration of a style entry, which a semicolon may hold several of.
    private mutating func apply(_ entry: String) {
        for declaration in entry.split(separator: ";", omittingEmptySubsequences: false) { applyDeclaration(String(declaration)) }
    }

    private mutating func applyDeclaration(_ declaration: String) {
        guard let colon = declaration.firstIndex(of: ":"), colon > declaration.startIndex else { return }
        let property = declaration[..<colon].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var value = String(declaration[declaration.index(after: colon)...])
        while let important = value.range(of: "!important", options: .caseInsensitive) { value.removeSubrange(important) }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !Self.isUnsafe(value) else { return }
        switch property {
        case "font-weight": isBold = value == "bold" || value == "bolder" || (Double(value).map { weight in weight >= 600 } ?? false)
        case "font-style": isItalic = value == "italic"
        case "font-size": fontSize = Self.fontSize(value)
        default: setShapeProperty(property, to: DiagramElementStyle.reading(property + ":" + value).style)
        }
    }

    /// Sets `property` to what `read` holds of it, nil when its value was not read: Pele writes only the last declaration
    /// of a property, and a browser drops one whose value is not CSS, so the block keeps its usual look rather than an
    /// earlier declaration's.
    private mutating func setShapeProperty(_ property: String, to read: DiagramElementStyle) {
        switch property {
        case "fill": style.fill = read.fill
        case "stroke": style.stroke = read.stroke
        case "color": style.textColor = read.textColor
        case "stroke-width": style.strokeWidth = read.strokeWidth
        case "stroke-dasharray": style.strokeDashLengths = read.strokeDashLengths
        default: break
        }
    }

    /// `14` or `14px`, above zero and at most 200, as Pele reads a text's size.
    private static func fontSize(_ value: String) -> CGFloat? {
        let digits = value.hasSuffix("px") ? String(value.dropLast(2)) : value
        guard !digits.isEmpty, digits.allSatisfy({ character in character.isASCII && (character.isNumber || character == ".") }),
              let size = Double(digits), size > 0, size <= largestFontSize else { return nil }
        return CGFloat(size)
    }

    static let largestFontSize = 200.0

    /// Pele's `RE_UNSAFE`: a value that could reach outside its declaration, which it drops.
    private static func isUnsafe(_ value: String) -> Bool {
        let lowered = value.lowercased()
        if lowered.contains("javascript:") || lowered.contains("@import") || lowered.contains("image-set") || lowered.contains("/*") { return true }
        if value.contains(where: { character in "<>{};\\".contains(character) }) { return true }
        for function in ["url", "expression"] {
            guard let range = lowered.range(of: function) else { continue }
            if lowered[range.upperBound...].drop(while: { character in character == " " || character == "\t" }).first == "(" { return true }
        }
        return false
    }
}
