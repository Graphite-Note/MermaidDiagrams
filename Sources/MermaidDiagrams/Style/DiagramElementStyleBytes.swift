/**
 * File: DiagramElementStyleBytes.swift
 * ------------------------------------
 * Layer: Core
 * Description: Reads an ASCII list of style declarations on its bytes: split at its top-level commas, each property
 *              told by its bytes, a hexadecimal color read without a String, as the list's characters are read.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

extension DiagramElementStyle {
    /// The style the ASCII declarations `bytes` write and whether one was not applied, as `reading(_:)` reads the same
    /// text through its characters (`propertiesAndValues`): the list cut at commas outside parentheses, each declaration's
    /// property before its first colon, spaces and tabs trimmed and lowered, its value after it, trimmed, cut before
    /// a `!important` in any case. A property is told by its bytes, a hexadecimal color is read on them
    /// (`DiagramColor.hexadecimal`); any other value is read from its text as before.
    static func reading(bytes: UnsafeBufferPointer<UInt8>) -> (style: DiagramElementStyle, hasUnappliedDeclaration: Bool) {
        var style = DiagramElementStyle()
        var hasUnappliedDeclaration = false
        var start = 0
        var depth = 0
        for index in 0...bytes.count {
            if index < bytes.count {
                let byte = bytes[index]
                if byte == openingParenthesis { depth += 1 } else if byte == closingParenthesis { depth = max(0, depth - 1) }
                guard byte == MermaidByte.comma, depth == 0 else { continue }
            }
            let declaration = start..<index
            start = index + 1
            guard let colon = declaration.first(where: { position in bytes[position] == MermaidByte.colon }) else {
                if !trimmed(declaration, in: bytes).isEmpty { hasUnappliedDeclaration = true }
                continue
            }
            let property = trimmed(declaration.lowerBound..<colon, in: bytes)
            var value = trimmed((colon + 1)..<declaration.upperBound, in: bytes)
            if value.contains(where: { position in bytes[position] == MermaidByte.exclamationMark }), let importance = importanceStart(in: value, of: bytes) {
                value = trimmed(value.lowerBound..<importance, in: bytes)
            }
            if !style.set(property, to: value, in: bytes) { hasUnappliedDeclaration = true }
        }
        return (style, hasUnappliedDeclaration)
    }

    /// Sets the property `property` (lowered as it is compared) to `value`; false when either is not read.
    private mutating func set(_ property: Range<Int>, to value: Range<Int>, in bytes: UnsafeBufferPointer<UInt8>) -> Bool {
        func spells(_ name: StaticString) -> Bool {
            guard property.count == name.utf8CodeUnitCount else { return false }
            let letters = name.utf8Start
            for offset in 0..<property.count where MermaidByte.lowercased(bytes[property.lowerBound + offset]) != letters[offset] { return false }
            return true
        }
        let isFill = spells("fill")
        let isStroke = !isFill && spells("stroke")
        if isFill || isStroke || spells("color") {
            guard let color = Self.color(value, in: bytes) else { return false }
            if isFill { fill = color } else if isStroke { stroke = color } else { textColor = color }
            return true
        }
        let written = String(decoding: UnsafeBufferPointer(rebasing: bytes[value]), as: UTF8.self)
        if spells("stroke-width") { return set("stroke-width", to: written) }
        if spells("stroke-dasharray") { return set("stroke-dasharray", to: written) }
        return false
    }

    /// The color a value writes: a hexadecimal one read on its bytes, any other through `DiagramColor(cssText:)`.
    private static func color(_ value: Range<Int>, in bytes: UnsafeBufferPointer<UInt8>) -> DiagramColor? {
        guard let first = value.first, bytes[first] == UInt8(ascii: "#") else {
            return DiagramColor(cssText: String(decoding: UnsafeBufferPointer(rebasing: bytes[value]), as: UTF8.self))
        }
        return DiagramColor.hexadecimal(UnsafeBufferPointer(rebasing: bytes[value]))
    }

    /// Where the first `!important` in any case starts in `value`, or nil.
    private static func importanceStart(in value: Range<Int>, of bytes: UnsafeBufferPointer<UInt8>) -> Int? {
        let word: StaticString = "!important"
        let length = word.utf8CodeUnitCount
        guard value.count >= length else { return nil }
        let letters = word.utf8Start
        for start in value.lowerBound...(value.upperBound - length) where bytes[start] == MermaidByte.exclamationMark {
            var offset = 1
            while offset < length, MermaidByte.lowercased(bytes[start + offset]) == letters[offset] { offset += 1 }
            if offset == length { return start }
        }
        return nil
    }

    /// The range without the spaces and tabs at its ends: Foundation's `whitespaces` in ASCII.
    private static func trimmed(_ range: Range<Int>, in bytes: UnsafeBufferPointer<UInt8>) -> Range<Int> {
        var start = range.lowerBound
        var end = range.upperBound
        while start < end, bytes[start] == MermaidByte.space || bytes[start] == MermaidByte.tab { start += 1 }
        while end > start, bytes[end - 1] == MermaidByte.space || bytes[end - 1] == MermaidByte.tab { end -= 1 }
        return start..<end
    }

    private static let openingParenthesis = UInt8(ascii: "(")
    private static let closingParenthesis = UInt8(ascii: ")")
}
