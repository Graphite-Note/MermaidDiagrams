/**
 * File: KanbanMetadataYAML.swift
 * ------------------------------
 * Layer: Core
 * Description: The YAML a kanban node's metadata is written in: flow collections, quoted and plain scalars, read as
 *              Pele's YAML reader reads them with the JSON schema.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 23/11/2026
 */

import Foundation

/// A YAML value of a kanban node's metadata, as the JSON schema reads it. A mapping keeps only the text of its fields, a
/// sequence only the text JavaScript's `String` writes for it: its values' joined by commas.
enum KanbanYAMLValue {
    case null
    case boolean(Bool)
    case number(Double)
    case text(String)
    case mapping([String: String])
    case sequence(String)

    /// A plain scalar: null, a Boolean or a number when it is written as one (`~`, `True`, `-1.5e3`, `0x1F`, `.inf`),
    /// else its text.
    init(plainScalar written: String) {
        let scalar = FoundationTextOnBytes.trimmed(written, includingLineBreaks: true)
        switch scalar {
        case "", "~", "null", "Null", "NULL": self = .null
        case "true", "True", "TRUE": self = .boolean(true)
        case "false", "False", "FALSE": self = .boolean(false)
        case ".inf", ".Inf", ".INF", "+.inf", "+.Inf", "+.INF": self = .number(.infinity)
        case "-.inf", "-.Inf", "-.INF": self = .number(-.infinity)
        case ".nan", ".NaN", ".NAN": self = .number(.nan)
        default: self = Self.number(scalar).map(KanbanYAMLValue.number) ?? .text(scalar)
        }
    }

    /// A decimal, hexadecimal (`0x`), octal (`0o`) or binary (`0b`) number of the JSON schema, or nil.
    private static func number(_ scalar: String) -> Double? {
        guard let first = scalar.utf8.first, first == UInt8(ascii: "-") || first == UInt8(ascii: "+") || first == UInt8(ascii: ".")
                || MermaidByte.isDigit(first) else { return nil }
        let isNegative = first == UInt8(ascii: "-")
        let unsigned = first == UInt8(ascii: "-") || first == UInt8(ascii: "+") ? String(scalar.dropFirst()) : scalar
        for (prefix, radix) in [("0x", 16), ("0o", 8), ("0b", 2)] where unsigned.hasPrefix(prefix) {
            guard let value = UInt64(unsigned.dropFirst(2), radix: radix) else { return nil }
            return isNegative ? -Double(value) : Double(value)
        }
        let isDecimal = unsigned.range(of: #"^(?:[0-9][0-9]*(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][-+]?[0-9]+)?$"#, options: .regularExpression) != nil
        let isLeadingZeroInteger = unsigned.count > 1 && unsigned.hasPrefix("0") && unsigned.allSatisfy(\.isNumber)
        guard isDecimal, !isLeadingZeroInteger, let value = Double(unsigned) else { return nil }
        return isNegative ? -value : value
    }

    /// The value as JavaScript's `String` writes it, when JavaScript holds it true: nil for null, `false`, zero, NaN and
    /// empty text; a mapping `[object Object]` and a sequence its values joined by commas (`[High]` is `High`), as Pele
    /// writes them. A sequence whose values join to nothing is no field either, where Pele would keep empty text.
    var text: String? {
        switch self {
        case .null, .boolean(false): nil
        case .boolean(true): "true"
        case .number(let number): number == 0 || number.isNaN ? nil : JavaScriptNumberText.text(number)
        case .text(let text), .sequence(let text): text.isEmpty ? nil : text
        case .mapping: "[object Object]"
        }
    }

    /// The value as a value of a sequence JavaScript's `join` writes: null as nothing, anything else as `String` does.
    var elementText: String {
        switch self {
        case .null: ""
        default: keyText
        }
    }

    /// The value as a mapping's key, which JavaScript's `String` writes whatever it is.
    var keyText: String {
        switch self {
        case .null: "null"
        case .boolean(let value): value ? "true" : "false"
        case .number(let number): JavaScriptNumberText.text(number)
        case .text(let text): text
        case .mapping: "[object Object]"
        case .sequence(let joined): joined
        }
    }
}

/// Reads YAML's flow values (`{ … }`, `[ … ]`, `"…"`, `'…'`, plain) from bytes, with `#` comments after a space. Entries
/// of a collection are separated by exactly one comma, as js-yaml requires.
struct KanbanFlowReader {
    private let bytes: [UInt8]
    private var position = 0

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    /// What is left after the cursor.
    var rest: String { String(decoding: bytes[min(position, bytes.count)...], as: UTF8.self) }

    /// One value and nothing after it but blanks and comments.
    mutating func readDocument() throws(KanbanCardMetadata.Failure) -> KanbanYAMLValue {
        let value = try readValue(stops: .none, depth: 0)
        skipBlanks()
        guard position >= bytes.count else { throw .notYAML }
        return value
    }

    /// A block mapping's key: quoted, or plain up to a colon that a blank or the end follows. Nil when the line holds none.
    mutating func readKey() throws(KanbanCardMetadata.Failure) -> String? {
        guard let first = peek() else { return nil }
        if first == Self.doubleQuote || first == Self.singleQuote { return try readValue(stops: .none, depth: 0).keyText }
        guard !Self.keyStarts.contains(first), !MermaidByte.isWhitespace(first) else { return nil }
        let start = position
        while let byte = peek(), byte != MermaidByte.colon || !(position + 1 >= bytes.count || MermaidByte.isWhitespace(bytes[position + 1])) {
            if byte == UInt8(ascii: "#") { return nil }
            position += 1
        }
        return FoundationTextOnBytes.trimmed(String(decoding: bytes[start..<position], as: UTF8.self), includingLineBreaks: false)
    }

    /// Moves past the blanks and the colon after a key, which a blank or the end of the line follows.
    mutating func skipsColonBeforeValue() -> Bool {
        while let byte = peek(), MermaidByte.isSpace(byte) { position += 1 }
        guard peek() == MermaidByte.colon else { return false }
        position += 1
        guard let next = peek() else { return true }
        return MermaidByte.isWhitespace(next)
    }

    private func peek(_ offset: Int = 0) -> UInt8? {
        position + offset < bytes.count ? bytes[position + offset] : nil
    }

    /// Skips spaces, tabs, line breaks and comments, a `#` being a comment at the start or after a blank.
    private mutating func skipBlanks() {
        while let byte = peek() {
            if MermaidByte.isWhitespace(byte) {
                position += 1
            } else if byte == UInt8(ascii: "#"), position == 0 || MermaidByte.isWhitespace(bytes[position - 1]) {
                while let commented = peek(), commented != MermaidByte.newline { position += 1 }
            } else {
                return
            }
        }
    }

    private mutating func readValue(stops: YAMLBytes.ASCIISet, depth: Int) throws(KanbanCardMetadata.Failure) -> KanbanYAMLValue {
        guard depth <= KanbanCardMetadata.deepestNesting else { throw .notYAML }
        skipBlanks()
        switch peek() {
        case MermaidByte.openingBrace: return try readCollection(closing: MermaidByte.closingBrace, depth: depth)
        case MermaidByte.openingBracket: return try readCollection(closing: MermaidByte.closingBracket, depth: depth)
        case Self.doubleQuote: return .text(try readDoubleQuoted())
        case Self.singleQuote: return .text(try readSingleQuoted())
        default: return readPlain(stops: stops)
        }
    }

    /// A mapping's entries (`key: value`, a key alone being null) or a sequence's values, to the closing bracket.
    private mutating func readCollection(closing: UInt8, depth: Int) throws(KanbanCardMetadata.Failure) -> KanbanYAMLValue {
        let isMapping = closing == MermaidByte.closingBrace
        let keyStops = isMapping ? Self.mappingKeyStops : Self.sequenceValueStops
        let valueStops = isMapping ? Self.mappingValueStops : Self.sequenceValueStops
        position += 1
        var fields: [String: String] = [:]
        var elements: [String] = []
        var isSeparated = true
        while true {
            skipBlanks()
            guard let byte = peek() else { throw .notYAML }
            if byte == closing {
                position += 1
                return isMapping ? .mapping(fields) : .sequence(elements.joined(separator: ","))
            }
            guard isSeparated, byte != MermaidByte.comma else { throw .notYAML }
            if isMapping {
                let key = try readValue(stops: keyStops, depth: depth + 1).keyText
                skipBlanks()
                var value = KanbanYAMLValue.null
                if peek() == MermaidByte.colon {
                    position += 1
                    value = try readValue(stops: valueStops, depth: depth + 1)
                }
                fields[key] = value.text
            } else {
                elements.append(try readValue(stops: valueStops, depth: depth + 1).elementText)
            }
            skipBlanks()
            isSeparated = peek() == MermaidByte.comma
            if isSeparated { position += 1 }
        }
    }

    /// Plain text up to a stop (a colon only when a blank, a comma, a bracket or the end follows it) or a comment.
    private mutating func readPlain(stops: YAMLBytes.ASCIISet) -> KanbanYAMLValue {
        let start = position
        while let byte = peek() {
            if stops.contains(byte), byte != MermaidByte.colon || peek(1).map({ next in MermaidByte.isWhitespace(next) || Self.flowIndicators.contains(next) }) ?? true {
                break
            }
            if byte == UInt8(ascii: "#"), position > start, MermaidByte.isWhitespace(bytes[position - 1]) { break }
            position += 1
        }
        return KanbanYAMLValue(plainScalar: Self.folded(String(decoding: bytes[start..<position], as: UTF8.self)))
    }

    private mutating func readDoubleQuoted() throws(KanbanCardMetadata.Failure) -> String {
        position += 1
        var text = ""
        var scalars = String.UnicodeScalarView()
        let start = position
        while let byte = peek(), byte != Self.doubleQuote { position += byte == Self.backslash ? 2 : 1 }
        guard position < bytes.count else { throw .notYAML }
        let body = String(decoding: bytes[start..<position], as: UTF8.self)
        position += 1
        // Without a backslash there is no escape and no escaped line break: the body is only folded.
        guard bytes[start..<(position - 1)].contains(Self.backslash) else { return Self.folded(body) }
        var characters = Self.folded(body.replacingOccurrences(of: #"\\\n[ \t]*"#, with: "", options: .regularExpression)).unicodeScalars[...]
        while let scalar = characters.popFirst() {
            guard scalar == "\\" else { scalars.append(scalar); continue }
            guard let escape = characters.popFirst() else { throw .notYAML }
            if let length = ["x": 2, "u": 4, "U": 8][Character(escape)] {
                let digits = UnicodeScalarText.string(characters.prefix(length))
                characters = characters.dropFirst(length)
                guard digits.count == length, let code = UInt32(digits, radix: 16), let decoded = Unicode.Scalar(code) else { throw .notYAML }
                scalars.append(decoded)
            } else if let decoded = Self.escapes[Character(escape)] {
                scalars.append(decoded)
            } else {
                throw .notYAML
            }
        }
        text.unicodeScalars.append(contentsOf: scalars)
        return text
    }

    private mutating func readSingleQuoted() throws(KanbanCardMetadata.Failure) -> String {
        position += 1
        let start = position
        while position < bytes.count {
            if bytes[position] == Self.singleQuote {
                guard peek(1) == Self.singleQuote else { break }
                position += 1
            }
            position += 1
        }
        guard position < bytes.count else { throw .notYAML }
        let body = String(decoding: bytes[start..<position], as: UTF8.self)
        let holdsQuotationMark = bytes[start..<position].contains(Self.singleQuote)
        position += 1
        // Every quotation mark of the body is one of a doubled pair: a body without one has nothing to undouble.
        return holdsQuotationMark ? Self.folded(body).replacingOccurrences(of: "''", with: "'") : Self.folded(body)
    }

    /// Line breaks folded as YAML folds a scalar's: the blanks around a break go, one break becomes a space, and each
    /// further break stays.
    static func folded(_ text: String) -> String {
        // A line feed is a character of its own but after a carriage return, where splitting at "\n" leaves the text
        // whole: text without its byte is returned as it is.
        guard text.utf8.contains(MermaidByte.newline) else { return text }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let trimmed = lines.enumerated().map { index, line -> Substring in
            var kept = line
            if index > 0 { kept = kept.drop { character in character == " " || character == "\t" } }
            if index < lines.count - 1 { while let last = kept.last, last == " " || last == "\t" { kept = kept.dropLast() } }
            return kept
        }
        var folded = ""
        var pendingBreaks = 0
        for (index, line) in trimmed.enumerated() {
            if index > 0 { pendingBreaks += 1 }
            if line.isEmpty, index < trimmed.count - 1 { continue }
            if pendingBreaks > 0 { folded += pendingBreaks == 1 ? " " : String(repeating: "\n", count: pendingBreaks - 1) }
            pendingBreaks = 0
            folded += line
        }
        return folded
    }

    private static let doubleQuote = UInt8(ascii: "\"")
    private static let singleQuote = UInt8(ascii: "'")
    private static let backslash = UInt8(ascii: "\\")
    private static let flowIndicators = YAMLBytes.ASCIISet([",", "[", "]", "{", "}"])
    /// What a plain key may not start with.
    private static let keyStarts = YAMLBytes.ASCIISet(Array("#:,[]{}&*!|>'\"%@`".unicodeScalars))
    /// What ends a mapping's key, a mapping's value and a sequence's value.
    private static let mappingKeyStops = YAMLBytes.ASCIISet([":", ",", "}"])
    private static let mappingValueStops = YAMLBytes.ASCIISet([",", "}"])
    private static let sequenceValueStops = YAMLBytes.ASCIISet([",", "]"])
    private static let escapes: [Character: Unicode.Scalar] = [
        "0": "\0", "a": "\u{07}", "b": "\u{08}", "t": "\t", "n": "\n", "v": "\u{0B}", "f": "\u{0C}", "r": "\r", "e": "\u{1B}", " ": " ",
        "\"": "\"", "/": "/", "\\": "\\", "N": "\u{85}", "_": "\u{A0}", "L": "\u{2028}", "P": "\u{2029}",
    ]
}
