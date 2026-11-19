/**
 * File: MermaidFlowCollectionReader.swift
 * ---------------------------------------
 * Layer: Core
 * Description: Reads the YAML flow collections (`{a: 1, b: [x, y]}`) of a diagram's front matter, as Pele's YAML reader does.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */

import Foundation

/// Reads one YAML flow value (a collection in braces or brackets, a quoted text or a plain scalar) from a text, as
/// Pele's `util/yaml.ts` reads the front matter's: entries separated by exactly one comma, keys plain or quoted, a key
/// without a value null, comments from ` #` to the end of the line, plain scalars as Pele reads them (`scalar`, also used
/// by `MermaidConfigurationOptions` for the block form). A collection nested deeper than 64 levels, one that is
/// not closed, one with a missing or an extra comma, and a text that does not read are not read (nil). The reading
/// looks at each byte once, so a hostile text costs no more than its length.
struct MermaidFlowCollectionReader {
    private let bytes: [UInt8]
    private var position: Int

    /// The deepest collection read.
    static let deepestNesting = 64

    /// The value that starts at `start` in `bytes`, and where it ends; nil when it is not a complete flow value.
    static func read(_ bytes: [UInt8], from start: Int) -> (value: DirectiveValue, end: Int)? {
        var reader = MermaidFlowCollectionReader(bytes: bytes, position: start)
        guard let value = reader.readValue(stops: [], depth: 0) else { return nil }
        return (value, reader.position)
    }

    private init(bytes: [UInt8], position: Int) {
        self.bytes = bytes
        self.position = position
    }

    private func isBlank(_ byte: UInt8) -> Bool {
        byte == MermaidByte.space || byte == MermaidByte.tab || byte == MermaidByte.newline || byte == MermaidByte.carriageReturn
    }

    /// Skips blanks and comments, and commas too when `commas`.
    private mutating func skip(commas: Bool) {
        while position < bytes.count {
            let byte = bytes[position]
            if isBlank(byte) || (commas && byte == MermaidByte.comma) {
                position += 1
            } else if byte == UInt8(ascii: "#"), position == 0 || isBlank(bytes[position - 1]) {
                while position < bytes.count, bytes[position] != MermaidByte.newline { position += 1 }
            } else {
                return
            }
        }
    }

    private mutating func readValue(stops: Set<UInt8>, depth: Int) -> DirectiveValue? {
        guard depth <= Self.deepestNesting else { return nil }
        skip(commas: false)
        guard position < bytes.count else { return nil }
        switch bytes[position] {
        case MermaidByte.openingBrace: return readMapping(depth: depth)
        case MermaidByte.openingBracket: return readSequence(depth: depth)
        case MermaidByte.quotationMark: return readDoubleQuoted().map(DirectiveValue.text)
        case UInt8(ascii: "'"): return readSingleQuoted().map(DirectiveValue.text)
        default: return readPlain(stops: stops)
        }
    }

    private mutating func readMapping(depth: Int) -> DirectiveValue? {
        position += 1
        var entries: [String: DirectiveValue] = [:]
        var isSeparated = true
        while true {
            skip(commas: false)
            guard position < bytes.count else { return nil }
            if bytes[position] == MermaidByte.closingBrace {
                position += 1
                return .object(entries)
            }
            guard isSeparated, bytes[position] != MermaidByte.comma, let key = readValue(stops: [MermaidByte.colon, MermaidByte.comma, MermaidByte.closingBrace],
                                                                                      depth: depth + 1) else { return nil }
            skip(commas: false)
            var value = DirectiveValue.null
            if position < bytes.count, bytes[position] == MermaidByte.colon {
                position += 1
                guard let read = readValue(stops: [MermaidByte.comma, MermaidByte.closingBrace], depth: depth + 1) else { return nil }
                value = read
            }
            entries[Self.keyText(key)] = value
            skip(commas: false)
            isSeparated = position < bytes.count && bytes[position] == MermaidByte.comma
            if isSeparated { position += 1 }
        }
    }

    private mutating func readSequence(depth: Int) -> DirectiveValue? {
        position += 1
        var items: [DirectiveValue] = []
        var isSeparated = true
        while true {
            skip(commas: false)
            guard position < bytes.count else { return nil }
            if bytes[position] == MermaidByte.closingBracket {
                position += 1
                return .array(items)
            }
            guard isSeparated, bytes[position] != MermaidByte.comma,
                  let item = readValue(stops: [MermaidByte.comma, MermaidByte.closingBracket], depth: depth + 1) else { return nil }
            items.append(item)
            skip(commas: false)
            isSeparated = position < bytes.count && bytes[position] == MermaidByte.comma
            if isSeparated { position += 1 }
        }
    }

    /// A key as text, the way JavaScript's `String(key)` gives it.
    private static func keyText(_ key: DirectiveValue) -> String {
        switch key {
        case .text(let text): text
        case .number(let number): number.isFinite ? JavaScriptNumberText.text(number) : String(number)
        case .boolean(let boolean): boolean ? "true" : "false"
        case .null: "null"
        case .object, .array: "[object Object]"
        }
    }

    private mutating func readDoubleQuoted() -> String? {
        var scalars: [UInt8] = []
        position += 1
        while position < bytes.count {
            let byte = bytes[position]
            if byte == MermaidByte.quotationMark {
                position += 1
                return String(decoding: scalars, as: UTF8.self)
            }
            if byte == UInt8(ascii: "\\") {
                guard position + 1 < bytes.count else { return nil }
                guard let escaped = readEscape() else { return nil }
                scalars.append(contentsOf: escaped)
                continue
            }
            scalars.append(byte)
            position += 1
        }
        return nil
    }

    /// The escape sequence at `position` (a backslash): its bytes, nil when it is unknown or cut short.
    private mutating func readEscape() -> [UInt8]? {
        let code = bytes[position + 1]
        let simple: [UInt8: String] = [UInt8(ascii: "0"): "\0", UInt8(ascii: "a"): "\u{07}", UInt8(ascii: "b"): "\u{08}", UInt8(ascii: "t"): "\t",
                                       UInt8(ascii: "n"): "\n", UInt8(ascii: "v"): "\u{0B}", UInt8(ascii: "f"): "\u{0C}", UInt8(ascii: "r"): "\r",
                                       UInt8(ascii: "e"): "\u{1B}", MermaidByte.space: " ", MermaidByte.quotationMark: "\"", UInt8(ascii: "/"): "/",
                                       UInt8(ascii: "\\"): "\\", UInt8(ascii: "N"): "\u{85}", UInt8(ascii: "_"): "\u{A0}",
                                       UInt8(ascii: "L"): "\u{2028}", UInt8(ascii: "P"): "\u{2029}"]
        if let text = simple[code] {
            position += 2
            return Array(text.utf8)
        }
        let length: Int
        switch code {
        case UInt8(ascii: "x"): length = 2
        case UInt8(ascii: "u"): length = 4
        case UInt8(ascii: "U"): length = 8
        default: return nil
        }
        let digitsStart = position + 2
        guard digitsStart + length <= bytes.count,
              let scalarValue = UInt32(String(decoding: bytes[digitsStart..<(digitsStart + length)], as: UTF8.self), radix: 16),
              let scalar = Unicode.Scalar(scalarValue) else { return nil }
        position = digitsStart + length
        return Array(String(Character(scalar)).utf8)
    }

    private mutating func readSingleQuoted() -> String? {
        var scalars: [UInt8] = []
        position += 1
        while position < bytes.count {
            let byte = bytes[position]
            if byte == UInt8(ascii: "'") {
                if position + 1 < bytes.count, bytes[position + 1] == UInt8(ascii: "'") {
                    scalars.append(byte)
                    position += 2
                    continue
                }
                position += 1
                return String(decoding: scalars, as: UTF8.self)
            }
            scalars.append(byte)
            position += 1
        }
        return nil
    }

    /// A plain scalar up to a stop (a colon only when a blank, a comma or a bracket follows), a comment or the end.
    private mutating func readPlain(stops: Set<UInt8>) -> DirectiveValue? {
        let start = position
        var end = position
        while end < bytes.count {
            let byte = bytes[end]
            if stops.contains(byte), byte != MermaidByte.colon || end + 1 >= bytes.count || Self.endsPlainKey(bytes[end + 1], isBlank: isBlank) { break }
            if byte == UInt8(ascii: "#"), end > start, isBlank(bytes[end - 1]) { break }
            end += 1
        }
        position = end
        let text = String(decoding: bytes[start..<end], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return Self.scalar(text)
    }

    private static func endsPlainKey(_ byte: UInt8, isBlank: (UInt8) -> Bool) -> Bool {
        isBlank(byte) || byte == MermaidByte.comma || byte == MermaidByte.openingBracket || byte == MermaidByte.closingBracket
            || byte == MermaidByte.openingBrace || byte == MermaidByte.closingBrace
    }

    /// A plain scalar as Pele's YAML reader reads it (its `scalar`, the JSON schema as js-yaml widens it): `null`, `~` and
    /// nothing in its three spellings are null, `true` and `false` in theirs Booleans, a decimal, hexadecimal (`0x`), octal
    /// (`0o`) or binary (`0b`) number a number, `.inf` and `.nan` the infinities and not-a-number; anything else is text.
    static func scalar(_ written: String) -> DirectiveValue {
        let text = written.trimmingCharacters(in: .whitespacesAndNewlines)
        switch text {
        case "", "~", "null", "Null", "NULL": return .null
        case "true", "True", "TRUE": return .boolean(true)
        case "false", "False", "FALSE": return .boolean(false)
        case ".inf", ".Inf", ".INF", "+.inf", "+.Inf", "+.INF": return .number(.infinity)
        case "-.inf", "-.Inf", "-.INF": return .number(-.infinity)
        case ".nan", ".NaN", ".NAN": return .number(.nan)
        default: break
        }
        if MermaidConfigurationOptions.isNumber(text), let number = Double(text) { return .number(number) }
        return radixNumber(text).map(DirectiveValue.number) ?? .text(text)
    }

    /// `0x1F`, `-0o17` or `+0b101`: the number its digits write in base 16, 8 or 2, after an optional sign; nil otherwise.
    private static func radixNumber(_ text: String) -> Double? {
        var bytes = Substring(text).utf8[...]
        let isNegative = bytes.first == UInt8(ascii: "-")
        if isNegative || bytes.first == UInt8(ascii: "+") { bytes = bytes.dropFirst() }
        guard bytes.count > 2, bytes.first == UInt8(ascii: "0") else { return nil }
        let radix: Double
        switch bytes.dropFirst().first {
        case UInt8(ascii: "x"): radix = 16
        case UInt8(ascii: "o"): radix = 8
        case UInt8(ascii: "b"): radix = 2
        default: return nil
        }
        var value = 0.0
        for byte in bytes.dropFirst(2) {
            let digit: Double
            switch byte {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): digit = Double(byte - UInt8(ascii: "0"))
            case UInt8(ascii: "a")...UInt8(ascii: "f") where radix == 16: digit = Double(byte - UInt8(ascii: "a") + 10)
            case UInt8(ascii: "A")...UInt8(ascii: "F") where radix == 16: digit = Double(byte - UInt8(ascii: "A") + 10)
            default: return nil
            }
            guard digit < radix else { return nil }
            value = value * radix + digit
        }
        return isNegative ? -value : value
    }
}
