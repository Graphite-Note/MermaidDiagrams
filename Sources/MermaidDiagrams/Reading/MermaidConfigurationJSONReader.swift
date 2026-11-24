/**
 * File: MermaidConfigurationJSONReader.swift
 * ------------------------------------------
 * Layer: Core
 * Description: Reads the JSON object of a `%%{init: …}%%` directive on its bytes, as JSONDecoder reads it into a
 *              directive's values, for the JSON directives are written in; anything else is left to JSONDecoder.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

/// A directive's JSON object read from its UTF-8 bytes into the values `JSONDecoder` makes of it (`DirectiveValue`):
/// objects, arrays, strings without an escape, numbers of JSON's grammar without an exponent, `true`, `false` and
/// `null`, between JSON's white space. Nil for any other text, which `MermaidDirectiveConfiguration` then gives
/// `JSONDecoder` as before: an escape in a string, a control character, a key written twice, a number with an exponent
/// or longer than `longestNumber`, collections nested deeper than `deepestNesting`, a value that is not an object, text
/// after it, or anything JSON does not allow.
struct MermaidConfigurationJSONReader {
    /// How deep collections may nest before the text is left to `JSONDecoder`.
    static let deepestNesting = 32
    /// The longest number read here, in bytes.
    static let longestNumber = 32

    private let bytes: UnsafeBufferPointer<UInt8>
    private var position = 0

    private init(bytes: UnsafeBufferPointer<UInt8>) {
        self.bytes = bytes
    }

    /// The object the trimmed JSON `bytes` writes, or nil when it is not read here.
    static func object(in bytes: UnsafeBufferPointer<UInt8>) -> [String: DirectiveValue]? {
        var reader = MermaidConfigurationJSONReader(bytes: bytes)
        guard reader.peek() == openingBrace, case .object(let object)? = reader.value(depth: 0) else { return nil }
        reader.skipWhitespace()
        return reader.position == bytes.count ? object : nil
    }

    private func peek() -> UInt8? {
        position < bytes.count ? bytes[position] : nil
    }

    /// JSON's white space: spaces, tabs, line feeds and carriage returns.
    private mutating func skipWhitespace() {
        while position < bytes.count {
            let byte = bytes[position]
            guard byte == MermaidByte.space || byte == MermaidByte.tab || byte == MermaidByte.newline || byte == MermaidByte.carriageReturn else { return }
            position += 1
        }
    }

    private mutating func value(depth: Int) -> DirectiveValue? {
        skipWhitespace()
        guard let first = peek() else { return nil }
        switch first {
        case Self.openingBrace: return depth < Self.deepestNesting ? object(depth: depth + 1) : nil
        case Self.openingBracket: return depth < Self.deepestNesting ? array(depth: depth + 1) : nil
        case MermaidByte.quotationMark: return string().map(DirectiveValue.text)
        case UInt8(ascii: "t"): return word(Self.trueWord, .boolean(true))
        case UInt8(ascii: "f"): return word(Self.falseWord, .boolean(false))
        case UInt8(ascii: "n"): return word(Self.nullWord, .null)
        default: return number()
        }
    }

    private mutating func object(depth: Int) -> DirectiveValue? {
        position += 1
        var entries: [String: DirectiveValue] = [:]
        skipWhitespace()
        if peek() == Self.closingBrace {
            position += 1
            return .object(entries)
        }
        while true {
            skipWhitespace()
            guard peek() == MermaidByte.quotationMark, let key = string() else { return nil }
            skipWhitespace()
            guard peek() == MermaidByte.colon else { return nil }
            position += 1
            guard let entry = value(depth: depth), entries.updateValue(entry, forKey: key) == nil else { return nil }
            skipWhitespace()
            switch peek() {
            case MermaidByte.comma: position += 1
            case Self.closingBrace:
                position += 1
                return .object(entries)
            default: return nil
            }
        }
    }

    private mutating func array(depth: Int) -> DirectiveValue? {
        position += 1
        var items: [DirectiveValue] = []
        skipWhitespace()
        if peek() == Self.closingBracket {
            position += 1
            return .array(items)
        }
        while true {
            guard let item = value(depth: depth) else { return nil }
            items.append(item)
            skipWhitespace()
            switch peek() {
            case MermaidByte.comma: position += 1
            case Self.closingBracket:
                position += 1
                return .array(items)
            default: return nil
            }
        }
    }

    /// A string from its opening quotation mark: its bytes up to the closing one, none of them a backslash or a control
    /// character.
    private mutating func string() -> String? {
        let start = position + 1
        var index = start
        while index < bytes.count {
            let byte = bytes[index]
            if byte == MermaidByte.quotationMark {
                position = index + 1
                return String(decoding: UnsafeBufferPointer(rebasing: bytes[start..<index]), as: UTF8.self)
            }
            guard byte != Self.backslash, byte >= 0x20 else { return nil }
            index += 1
        }
        return nil
    }

    private mutating func word(_ word: StaticString, _ value: DirectiveValue) -> DirectiveValue? {
        let letters = word.utf8Start
        guard position + word.utf8CodeUnitCount <= bytes.count else { return nil }
        for offset in 0..<word.utf8CodeUnitCount where bytes[position + offset] != letters[offset] { return nil }
        position += word.utf8CodeUnitCount
        return value
    }

    /// `-?(0|[1-9][0-9]*)(\.[0-9]+)?`, at most `longestNumber` bytes, so always a finite `Double`.
    private mutating func number() -> DirectiveValue? {
        let start = position
        var index = position
        func digits() -> Int {
            let first = index
            while index < bytes.count, MermaidByte.isDigit(bytes[index]) { index += 1 }
            return index - first
        }
        if index < bytes.count, bytes[index] == MermaidByte.hyphen { index += 1 }
        guard index < bytes.count, MermaidByte.isDigit(bytes[index]) else { return nil }
        if bytes[index] == UInt8(ascii: "0") {
            index += 1
        } else {
            _ = digits()
        }
        if index < bytes.count, bytes[index] == UInt8(ascii: ".") {
            index += 1
            guard digits() > 0 else { return nil }
        }
        // An exponent is left to JSONDecoder, which refuses a number past Double's range.
        if index < bytes.count, bytes[index] == UInt8(ascii: "e") || bytes[index] == UInt8(ascii: "E") { return nil }
        guard index - start <= Self.longestNumber,
              let number = Double(String(decoding: UnsafeBufferPointer(rebasing: bytes[start..<index]), as: UTF8.self)) else { return nil }
        position = index
        return .number(number)
    }

    private static let openingBrace = MermaidByte.openingBrace
    private static let closingBrace = MermaidByte.closingBrace
    private static let openingBracket = MermaidByte.openingBracket
    private static let closingBracket = MermaidByte.closingBracket
    private static let backslash = UInt8(ascii: "\\")
    private static let trueWord: StaticString = "true"
    private static let falseWord: StaticString = "false"
    private static let nullWord: StaticString = "null"
}
