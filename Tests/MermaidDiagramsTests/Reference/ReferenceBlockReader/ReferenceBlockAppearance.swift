/**
 * File: ReferenceBlockAppearance.swift
 * ------------------------------------
 * Layer: Tests
 * Description: MermaidDiagrams 0.7.0's BlockAppearance, frozen as main 2a0cc65 had it: a block's look read through its
 *              declarations' characters, the reference the byte reading is proven against (BlockAppearanceBytesTests).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */


import CoreGraphics
import Foundation
@testable import MermaidDiagrams

/// A block's look, from its classes (or the `default` class, for a block that has none) and then its own `style`, each
/// declaration as Pele's `resolveStyle` takes it: the property before the first colon, the value after it without
/// `!important`, a later one over an earlier (and a later one whose value is not read leaving the property unset).
struct ReferenceBlockAppearance: Equatable {
    /// Its fill, outline, line width and dashes, and its text's color.
    var style = DiagramElementStyle()
    var isBold = false
    var isItalic = false
    /// `font-size` in points (`14` or `14px`), above zero and at most 200; nil for the diagram's size.
    var fontSize: CGFloat?

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
    var textColor: DiagramColor? {
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
        while value.utf8.contains(MermaidByte.exclamationMark), let important = value.range(of: "!important", options: .caseInsensitive) {
            value.removeSubrange(important)
        }
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
        if let asciiUnsafe = isUnsafe(ascii: value) { return asciiUnsafe }
        let lowered = value.lowercased()
        if lowered.contains("javascript:") || lowered.contains("@import") || lowered.contains("image-set") || lowered.contains("/*") { return true }
        if value.contains(where: { character in "<>{};\\".contains(character) }) { return true }
        for function in ["url", "expression"] {
            guard let range = lowered.range(of: function) else { continue }
            if lowered[range.upperBound...].drop(while: { character in character == " " || character == "\t" }).first == "(" { return true }
        }
        return false
    }

    /// `isUnsafe` read from the bytes of an ASCII value, whose lowercasing and searches are those of its bytes; nil for a
    /// value beyond ASCII.
    static func isUnsafe(ascii value: String) -> Bool? {
        var lowered: [UInt8] = []
        lowered.reserveCapacity(value.utf8.count)
        for byte in value.utf8 {
            guard byte < 0x80 else { return nil }
            lowered.append(MermaidByte.lowercased(byte))
        }
        for word in unsafeWords where firstIndex(of: word, in: lowered) != nil { return true }
        if lowered.contains(where: { byte in unsafeBytes.contains(byte) }) { return true }
        // Only the first `url` and the first `expression` count, as the search for them stops at the first.
        for function in unsafeFunctions {
            guard var index = firstIndex(of: function, in: lowered).map({ start in start + function.count }) else { continue }
            while index < lowered.count, lowered[index] == MermaidByte.space || lowered[index] == UInt8(ascii: "\t") { index += 1 }
            if index < lowered.count, lowered[index] == UInt8(ascii: "(") { return true }
        }
        return false
    }

    private static func firstIndex(of word: [UInt8], in bytes: [UInt8]) -> Int? {
        guard word.count <= bytes.count else { return nil }
        return (0...(bytes.count - word.count)).first { start in bytes[start] == word[0] && bytes[start..<(start + word.count)].elementsEqual(word) }
    }

    private static let unsafeWords = ["javascript:", "@import", "image-set", "/*"].map { word in Array(word.utf8) }
    private static let unsafeBytes = Array("<>{};\\".utf8)
    private static let unsafeFunctions = ["url", "expression"].map { word in Array(word.utf8) }
}
