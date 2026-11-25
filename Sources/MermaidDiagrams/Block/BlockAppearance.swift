/**
 * File: BlockAppearance.swift
 * ---------------------------
 * Layer: Core
 * Description: What a block's classes and style set for its look, as Pele's resolveStyle reads them: colors, its line,
 *              its text in bold, italic or at its own size, and the text color Pele picks on a fill it sets.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 24/11/2026
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

    /// Each declaration of a style entry, which a semicolon may hold several of: an ASCII entry read on its bytes
    /// (`applyDeclaration(bytes:)`), any other through its characters.
    private mutating func apply(_ entry: String) {
        var text = entry
        let isApplied = text.withUTF8 { bytes -> Bool in
            guard !bytes.contains(where: { byte in byte >= 0x80 }) else { return false }
            var start = 0
            for index in 0...bytes.count where index == bytes.count || bytes[index] == UInt8(ascii: ";") {
                applyDeclaration(bytes: UnsafeBufferPointer(rebasing: bytes[start..<index]))
                start = index + 1
            }
            return true
        }
        guard !isApplied else { return }
        for declaration in entry.split(separator: ";", omittingEmptySubsequences: false) { applyDeclaration(String(declaration)) }
    }

    /// `applyDeclaration(_:)` of an ASCII declaration, on its bytes: the property before the first colon (not the first
    /// byte), trimmed and lowered; the value after it without every `!important` in any case, trimmed, kept unless
    /// empty or unsafe.
    private mutating func applyDeclaration(bytes declaration: UnsafeBufferPointer<UInt8>) {
        guard let colon = declaration.firstIndex(of: UInt8(ascii: ":")), colon > 0 else { return }
        let propertyRange = Self.trimmedRange(declaration, 0..<colon)
        var property: [UInt8] = declaration[propertyRange].map(MermaidByte.lowercased)
        var value = Array(declaration[(colon + 1)...])
        while value.contains(MermaidByte.exclamationMark), let important = Self.firstIndexIgnoringCase(of: Self.important, in: value) {
            value.removeSubrange(important..<(important + Self.important.count))
        }
        let valueRange = value.withUnsafeBufferPointer { buffer in Self.trimmedRange(buffer, 0..<buffer.count) }
        value = Array(value[valueRange])
        guard !value.isEmpty, !Self.isUnsafe(asciiBytes: value) else { return }
        switch property {
        case Self.fontWeight:
            isBold = value == Self.bold || value == Self.bolder || (Double(String(decoding: value, as: UTF8.self)).map { weight in weight >= 600 } ?? false)
        case Self.fontStyle: isItalic = value == Self.italic
        case Self.fontSizeProperty: fontSize = Self.fontSize(String(decoding: value, as: UTF8.self))
        default:
            let propertyText = String(decoding: property, as: UTF8.self)
            property.append(UInt8(ascii: ":"))
            property.append(contentsOf: value)
            let read = property.withUnsafeBufferPointer { bytes in DiagramElementStyle.reading(bytes: bytes).style }
            setShapeProperty(propertyText, to: read)
        }
    }

    /// The part of `range` of `bytes` without ASCII white space and line breaks at either end.
    private static func trimmedRange(_ bytes: UnsafeBufferPointer<UInt8>, _ range: Range<Int>) -> Range<Int> {
        var start = range.lowerBound
        var end = range.upperBound
        while start < end, isSpace(bytes[start]) { start += 1 }
        while end > start, isSpace(bytes[end - 1]) { end -= 1 }
        return start..<end
    }

    private static func isSpace(_ byte: UInt8) -> Bool { byte == 0x20 || (byte >= 0x09 && byte <= 0x0D) }

    private static func firstIndexIgnoringCase(of word: [UInt8], in bytes: [UInt8]) -> Int? {
        guard word.count <= bytes.count else { return nil }
        return (0...(bytes.count - word.count)).first { start in
            (0..<word.count).allSatisfy { offset in MermaidByte.lowercased(bytes[start + offset]) == word[offset] }
        }
    }

    private static let important = Array("!important".utf8)
    private static let fontWeight = Array("font-weight".utf8)
    private static let fontStyle = Array("font-style".utf8)
    private static let fontSizeProperty = Array("font-size".utf8)
    private static let bold = Array("bold".utf8)
    private static let bolder = Array("bolder".utf8)
    private static let italic = Array("italic".utf8)

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
        guard !value.utf8.contains(where: { byte in byte >= 0x80 }) else { return nil }
        return isUnsafe(asciiBytes: Array(value.utf8))
    }

    /// `isUnsafe` of an ASCII value's bytes.
    static func isUnsafe(asciiBytes value: [UInt8]) -> Bool {
        let lowered = value.map(MermaidByte.lowercased)
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
