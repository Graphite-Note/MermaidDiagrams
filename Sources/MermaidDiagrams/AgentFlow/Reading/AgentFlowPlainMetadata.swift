/**
 * File: AgentFlowPlainMetadata.swift
 * ----------------------------------
 * Layer: Core
 * Description: The one-line metadata most agent flows write (`@{ shape: input }`, `@{ shape: tool, returns: "Report" }`)
 *              read on its bytes, as the YAML reader reads it, without building the YAML document; any other body is
 *              left to the YAML reader.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 26/11/2026
 */

/// A one-line metadata body of `key: value` entries separated by commas: each key a word, each value a plain scalar of
/// letters, digits, `_`, `.`, `+`, `-` and inner spaces, read by `SequenceAttributesScalarSyntax.scalar` as the YAML
/// reader reads its plain scalars, or a double-quoted text of printable ASCII without a backslash, its text as written.
/// A body with anything else (single quotes, brackets, colons in plain values, comments, tabs, line breaks, a key written
/// twice, a key YAML reads as no text or that could pollute a prototype, an empty entry) gives nil, and is read as YAML.
enum AgentFlowPlainMetadata {
    /// One entry: its key's and its value's bytes (a quoted value's without its quotation marks), and where it ends.
    struct Entry: BitwiseCopyable {
        var keyStart: Int
        var keyEnd: Int
        var valueStart: Int
        var valueEnd: Int
        var isQuoted: Bool
        var end: Int

        init(key: Range<Int>, value: Range<Int>, isQuoted: Bool, end: Int) {
            (keyStart, keyEnd, valueStart, valueEnd) = (key.lowerBound, key.upperBound, value.lowerBound, value.upperBound)
            self.isQuoted = isQuoted
            self.end = end
        }

        var key: Range<Int> { keyStart..<keyEnd }
        var value: Range<Int> { valueStart..<valueEnd }
    }

    static func value(of body: String) -> SequenceAttributeValue? {
        let bytes = Array(body.utf8)
        var fields: [String: SequenceAttributeValue] = [:]
        var entryStart = 0
        while entryStart <= bytes.count {
            guard let entry = entry(bytes, from: entryStart, end: bytes.count) else { return nil }
            let key = String(decoding: bytes[entry.key], as: UTF8.self)
            guard fields[key] == nil else { return nil }
            fields[key] = entry.isQuoted ? .text(String(decoding: bytes[entry.value], as: UTF8.self)) : SequenceAttributesScalarSyntax.scalar(bytes[entry.value])
            entryStart = entry.end + 1
        }
        return .mapping(fields)
    }

    /// The entries of the body `range` of `bytes` passed to `body` in order; false when it is not a body this reader
    /// takes. Past sixteen entries the body is left to the YAML reader, which reads it alike, so that finding a key
    /// written twice stays within sixteen comparisons an entry.
    static func entries(of bytes: [UInt8], _ range: Range<Int>, into found: inout ScratchList<Entry>) -> Bool {
        found.removeAll()
        var entryStart = range.lowerBound
        while entryStart <= range.upperBound {
            guard found.count < 16, let entry = entry(bytes, from: entryStart, end: range.upperBound) else { return false }
            for earlier in found where bytes[earlier.key].elementsEqual(bytes[entry.key]) { return false }
            found.append(entry)
            entryStart = entry.end + 1
        }
        return true
    }

    /// One `key: value` entry from `start`, the spaces around it, up to the comma after it or `end`; nil when it is not
    /// one this reader takes.
    private static func entry(_ bytes: [UInt8], from start: Int, end: Int) -> Entry? {
        var keyStart = start
        while keyStart < end, bytes[keyStart] == space { keyStart += 1 }
        var keyEnd = keyStart
        while keyEnd < end, isKeyByte(bytes[keyEnd]) { keyEnd += 1 }
        guard keyEnd > keyStart, isLetter(bytes[keyStart]) || bytes[keyStart] == underscore, keyEnd + 1 < end, bytes[keyEnd] == colon,
              bytes[keyEnd + 1] == space, !isReservedKey(bytes[keyStart..<keyEnd]) else { return nil }
        var valueStart = keyEnd + 1
        while valueStart < end, bytes[valueStart] == space { valueStart += 1 }
        guard valueStart < end else { return nil }
        if bytes[valueStart] == quotationMark { return quoted(bytes, key: keyStart..<keyEnd, from: valueStart, end: end) }
        var entryEnd = valueStart
        while entryEnd < end, bytes[entryEnd] != comma { entryEnd += 1 }
        var valueEnd = entryEnd
        while valueEnd > valueStart, bytes[valueEnd - 1] == space { valueEnd -= 1 }
        guard isLetter(bytes[valueStart]) || isDigit(bytes[valueStart]) || bytes[valueStart] == underscore else { return nil }
        for index in valueStart..<valueEnd where !isValueByte(bytes[index]) { return nil }
        return Entry(key: keyStart..<keyEnd, value: valueStart..<valueEnd, isQuoted: false, end: entryEnd)
    }

    /// A double-quoted value without a backslash, then only spaces up to the comma or the end.
    private static func quoted(_ bytes: [UInt8], key: Range<Int>, from opening: Int, end: Int) -> Entry? {
        var closing = opening + 1
        while closing < end, bytes[closing] != quotationMark {
            // An escape, a control character or one past ASCII (some of which YAML does not print) is the YAML reader's.
            guard bytes[closing] != backslash, bytes[closing] >= space, bytes[closing] < delete else { return nil }
            closing += 1
        }
        guard closing < end else { return nil }
        var entryEnd = closing + 1
        while entryEnd < end, bytes[entryEnd] == space { entryEnd += 1 }
        guard entryEnd == end || bytes[entryEnd] == comma else { return nil }
        return Entry(key: key, value: (opening + 1)..<closing, isQuoted: true, end: entryEnd)
    }

    /// Whether a plain value is text as the YAML reader reads it, without making it: one starting with a letter or an
    /// underscore is text unless it spells null or a Boolean; one starting with a digit is the scalar reader's.
    static func isPlainText(_ value: ArraySlice<UInt8>) -> Bool {
        guard let first = value.first, isLetter(first) || first == underscore else { return false }
        switch value.count {
        case 4: return !spells(value, ["null", "Null", "NULL", "true", "True", "TRUE"])
        case 5: return !spells(value, ["false", "False", "FALSE"])
        default: return true
        }
    }

    private static func spells(_ value: ArraySlice<UInt8>, _ spellings: [StaticString]) -> Bool {
        spellings.contains { spelling in
            spelling.withUTF8Buffer { buffer in buffer.elementsEqual(value) }
        }
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
