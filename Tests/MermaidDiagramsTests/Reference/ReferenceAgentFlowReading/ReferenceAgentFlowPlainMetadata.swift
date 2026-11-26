/**
 * File: ReferenceAgentFlowPlainMetadata.swift
 * -------------------------------------------
 * Layer: Tests
 * Description: 0.7.0's agent flow reader on UTF-16 code units (AgentFlowPlainMetadata.swift), kept unchanged but for its
 *              names as the reference the reader on bytes is compared with (AgentFlowReadingEquivalenceTests).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

@testable import MermaidDiagrams

/// A one-line metadata body of `key: value` entries separated by commas: each key a word, each value a plain scalar of
/// letters, digits, `_`, `.`, `+`, `-` and inner spaces, read by `SequenceAttributesScalarSyntax.scalar` as the YAML
/// reader reads its plain scalars, or a double-quoted text of printable ASCII without a backslash, its text as written.
/// A body with anything else (single quotes, brackets, colons in plain values, comments, tabs, line breaks, a key written
/// twice, a key YAML reads as no text or that could pollute a prototype, an empty entry) gives nil, and is read as YAML.
enum ReferenceAgentFlowPlainMetadata {
    static func value(of body: String) -> SequenceAttributeValue? {
        let bytes = Array(body.utf8)
        var fields: [String: SequenceAttributeValue] = [:]
        var entryStart = 0
        while entryStart <= bytes.count {
            guard let entry = entry(bytes, from: entryStart), fields[entry.key] == nil else { return nil }
            fields[entry.key] = entry.value
            entryStart = entry.end + 1
        }
        return .mapping(fields)
    }

    /// One `key: value` entry from `start`, the spaces around it, up to the comma after it or the end: its key, its
    /// value and where it ends; nil when it is not one this reader takes.
    private static func entry(_ bytes: [UInt8], from start: Int) -> (key: String, value: SequenceAttributeValue, end: Int)? {
        var keyStart = start
        while keyStart < bytes.count, bytes[keyStart] == space { keyStart += 1 }
        var keyEnd = keyStart
        while keyEnd < bytes.count, isKeyByte(bytes[keyEnd]) { keyEnd += 1 }
        guard keyEnd > keyStart, isLetter(bytes[keyStart]) || bytes[keyStart] == underscore, keyEnd + 1 < bytes.count, bytes[keyEnd] == colon,
              bytes[keyEnd + 1] == space, !isReservedKey(bytes[keyStart..<keyEnd]) else { return nil }
        var valueStart = keyEnd + 1
        while valueStart < bytes.count, bytes[valueStart] == space { valueStart += 1 }
        guard valueStart < bytes.count else { return nil }
        let key = String(decoding: bytes[keyStart..<keyEnd], as: UTF8.self)
        if bytes[valueStart] == quotationMark { return quoted(bytes, key: key, from: valueStart) }
        var entryEnd = valueStart
        while entryEnd < bytes.count, bytes[entryEnd] != comma { entryEnd += 1 }
        var valueEnd = entryEnd
        while valueEnd > valueStart, bytes[valueEnd - 1] == space { valueEnd -= 1 }
        guard isLetter(bytes[valueStart]) || isDigit(bytes[valueStart]) || bytes[valueStart] == underscore else { return nil }
        for index in valueStart..<valueEnd where !isValueByte(bytes[index]) { return nil }
        return (key, SequenceAttributesScalarSyntax.scalar(bytes[valueStart..<valueEnd]), entryEnd)
    }

    /// A double-quoted value without a backslash, then only spaces up to the comma or the end.
    private static func quoted(_ bytes: [UInt8], key: String, from opening: Int) -> (key: String, value: SequenceAttributeValue, end: Int)? {
        var closing = opening + 1
        while closing < bytes.count, bytes[closing] != quotationMark {
            // An escape, a control character or one past ASCII (some of which YAML does not print) is the YAML reader's.
            guard bytes[closing] != backslash, bytes[closing] >= space, bytes[closing] < delete else { return nil }
            closing += 1
        }
        guard closing < bytes.count else { return nil }
        var entryEnd = closing + 1
        while entryEnd < bytes.count, bytes[entryEnd] == space { entryEnd += 1 }
        guard entryEnd == bytes.count || bytes[entryEnd] == comma else { return nil }
        return (key, .text(String(decoding: bytes[(opening + 1)..<closing], as: UTF8.self)), entryEnd)
    }

    /// A key YAML reads as something other than text (`null`, `true`, `false` in any case), or that could pollute a
    /// prototype (`__proto__`, `constructor`, `prototype`).
    private static func isReservedKey(_ key: ArraySlice<UInt8>) -> Bool {
        reservedKeys.contains { reserved in
            reserved.count == key.count && zip(reserved, key).allSatisfy { lowered, byte in lowered == (isLetter(byte) ? byte | 0x20 : byte) }
        }
    }

    private static let reservedKeys: [[UInt8]] = ["null", "true", "false", "__proto__", "constructor", "prototype"].map { key in Array(key.utf8) }

    private static func isLetter(_ byte: UInt8) -> Bool { (byte | 0x20) >= UInt8(ascii: "a") && (byte | 0x20) <= UInt8(ascii: "z") }
    private static func isDigit(_ byte: UInt8) -> Bool { byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9") }
    private static func isKeyByte(_ byte: UInt8) -> Bool { isLetter(byte) || isDigit(byte) || byte == underscore || byte == hyphen }

    private static func isValueByte(_ byte: UInt8) -> Bool {
        isLetter(byte) || isDigit(byte) || byte == underscore || byte == hyphen || byte == period || byte == plus || byte == space
    }

    private static let comma = UInt8(ascii: ",")
    private static let space = UInt8(ascii: " ")
    private static let colon = UInt8(ascii: ":")
    private static let underscore = UInt8(ascii: "_")
    private static let hyphen = UInt8(ascii: "-")
    private static let period = UInt8(ascii: ".")
    private static let plus = UInt8(ascii: "+")
    private static let quotationMark = UInt8(ascii: "\"")
    private static let backslash = UInt8(ascii: "\\")
    private static let delete: UInt8 = 0x7F
}
