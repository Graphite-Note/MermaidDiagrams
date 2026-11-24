/**
 * File: FlowchartAttributeValues.swift
 * ------------------------------------
 * Layer: Core
 * Description: The values of a node's one-line attributes read on bytes where YAML would read every one of them as
 *              text: keys of letters, each once, and values that are double-quoted strings or plain words; any other
 *              body is left to the YAML reader.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

/// The values of the attributes the flowchart reads, as ranges of the text, from a one-line body Pele's YAML reader
/// would read as a mapping of text (and of whole numbers for `w` and `h`). Nil for a body written otherwise.
struct FlowchartAttributeValues {
    /// The values' ranges, by key, valid where `written` has the key's bit.
    private var ranges = (MermaidTextRange.empty, MermaidTextRange.empty, MermaidTextRange.empty, MermaidTextRange.empty, MermaidTextRange.empty,
                          MermaidTextRange.empty, MermaidTextRange.empty, MermaidTextRange.empty, MermaidTextRange.empty, MermaidTextRange.empty,
                          MermaidTextRange.empty)
    /// One bit for each key written, by `Key.rawValue`.
    private var written: UInt16 = 0

    var shape: Range<Int>? { range(of: .shape) }
    var label: Range<Int>? { range(of: .label) }
    var labelType: Range<Int>? { range(of: .labelType) }
    var view: Range<Int>? { range(of: .view) }
    var icon: Range<Int>? { range(of: .icon) }
    var image: Range<Int>? { range(of: .image) }
    var form: Range<Int>? { range(of: .form) }
    var position: Range<Int>? { range(of: .position) }
    var constraint: Range<Int>? { range(of: .constraint) }
    var width: Range<Int>? { range(of: .width) }
    var height: Range<Int>? { range(of: .height) }

    /// Whether any icon or picture attribute is written.
    var hasAssetAttributes: Bool { written & 0b111_1111_0000 != 0 }

    private func range(of key: Key) -> Range<Int>? {
        guard written & (1 << key.rawValue) != 0 else { return nil }
        let range: MermaidTextRange
        switch key {
        case .shape: range = ranges.0
        case .label: range = ranges.1
        case .labelType: range = ranges.2
        case .view: range = ranges.3
        case .icon: range = ranges.4
        case .image: range = ranges.5
        case .form: range = ranges.6
        case .position: range = ranges.7
        case .constraint: range = ranges.8
        case .width: range = ranges.9
        case .height, .other: range = ranges.10
        }
        return range.lowerBound..<range.upperBound
    }

    private enum Key: UInt16 {
        case shape, label, labelType, view, icon, image, form, position, constraint, width, height, other
    }

    /// The values of the body from `start` to `end` (the `}`), or nil when YAML may read it otherwise: a key that is not
    /// letters, a key written twice, a value that is not a quoted string without escapes or a plain word YAML reads as
    /// text, a label beyond ASCII, a size that is not a whole number without a leading zero.
    init?(in bytes: FlowchartBytes, from start: Int, to end: Int) {
        var index = start
        func skipBlanks() { while index < end, MermaidByte.isSpace(bytes.base[index]) { index += 1 } }
        skipBlanks()
        guard index < end else { return nil }
        while index < end {
            let keyStart = index
            while index < end, MermaidByte.isLetter(bytes.base[index]) { index += 1 }
            guard index > keyStart else { return nil }
            let key = Self.key(in: bytes, from: keyStart, to: index)
            skipBlanks()
            guard index + 1 < end, bytes.base[index] == MermaidByte.colon, MermaidByte.isSpace(bytes.base[index + 1]) else { return nil }
            index += 1
            skipBlanks()
            guard let value = Self.value(in: bytes, at: &index, before: end, isNumber: key == .width || key == .height) else { return nil }
            guard set(value, for: key, in: bytes) else { return nil }
            skipBlanks()
            guard index == end || bytes.base[index] == MermaidByte.comma else { return nil }
            if index < end {
                index += 1
                skipBlanks()
                guard index < end else { return nil }
            }
        }
    }

    /// Records `value` for `key`; false when the key was written before or its value is one YAML may read otherwise.
    private mutating func set(_ value: Range<Int>, for key: Key, in bytes: FlowchartBytes) -> Bool {
        guard key != .other else { return true }
        let bit: UInt16 = 1 << key.rawValue
        guard written & bit == 0 else { return false }
        if key == .label, value.contains(where: { index in bytes.base[index] >= 0x80 }) { return false }
        written |= bit
        let range = MermaidTextRange(start: value.lowerBound, end: value.upperBound)
        switch key {
        case .shape: ranges.0 = range
        case .label: ranges.1 = range
        case .labelType: ranges.2 = range
        case .view: ranges.3 = range
        case .icon: ranges.4 = range
        case .image: ranges.5 = range
        case .form: ranges.6 = range
        case .position: ranges.7 = range
        case .constraint: ranges.8 = range
        case .width: ranges.9 = range
        case .height, .other: ranges.10 = range
        }
        return true
    }

    private static func key(in bytes: FlowchartBytes, from start: Int, to end: Int) -> Key {
        switch end - start {
        case 1: return bytes[start] == UInt8(ascii: "w") ? .width : bytes[start] == UInt8(ascii: "h") ? .height : .other
        case 3: return bytes.hasText("img", at: start) ? .image : bytes.hasText("pos", at: start) ? .position : .other
        case 4: return bytes.hasText("view", at: start) ? .view : bytes.hasText("icon", at: start) ? .icon : bytes.hasText("form", at: start) ? .form : .other
        case 5: return bytes.hasText("shape", at: start) ? .shape : bytes.hasText("label", at: start) ? .label : .other
        case 9: return bytes.hasText("labelType", at: start) ? .labelType : .other
        case 10: return bytes.hasText("constraint", at: start) ? .constraint : .other
        default: return .other
        }
    }

    /// A double-quoted string's inside, or a plain value up to the next comma without its trailing spaces.
    private static func value(in bytes: FlowchartBytes, at index: inout Int, before end: Int, isNumber: Bool) -> Range<Int>? {
        if bytes.base[index] == MermaidByte.quotationMark {
            guard !isNumber else { return nil }
            let start = index + 1
            index = start
            while index < end, bytes.base[index] != MermaidByte.quotationMark { index += 1 }
            guard index < end else { return nil }
            index += 1
            return start..<(index - 1)
        }
        let start = index
        while index < end, bytes.base[index] != MermaidByte.comma { index += 1 }
        var valueEnd = index
        while valueEnd > start, MermaidByte.isSpace(bytes.base[valueEnd - 1]) { valueEnd -= 1 }
        guard valueEnd > start else { return nil }
        let range = start..<valueEnd
        return (isNumber ? isWholeNumber(range, in: bytes) : isPlainText(range, in: bytes)) ? range : nil
    }

    /// Digits, the first not 0, at most fifteen: a number YAML and `Double` read alike.
    private static func isWholeNumber(_ range: Range<Int>, in bytes: FlowchartBytes) -> Bool {
        guard range.count <= 15, bytes.base[range.lowerBound] != UInt8(ascii: "0") else { return false }
        return range.allSatisfy { index in MermaidByte.isDigit(bytes.base[index]) }
    }

    /// A plain scalar YAML reads as text: a letter first, ASCII, none of `#`, quotation marks, `:`, brackets or braces,
    /// and not one of YAML's words for true, false and null.
    private static func isPlainText(_ range: Range<Int>, in bytes: FlowchartBytes) -> Bool {
        guard MermaidByte.isLetter(bytes.base[range.lowerBound]) else { return false }
        for index in range {
            switch bytes.base[index] {
            case 0x80...0xFF, UInt8(ascii: "#"), MermaidByte.quotationMark, UInt8(ascii: "'"), MermaidByte.colon, MermaidByte.openingBrace,
                 MermaidByte.closingBrace, MermaidByte.openingBracket, MermaidByte.closingBracket: return false
            default: continue
            }
        }
        let start = range.lowerBound
        switch range.count {
        case 4: return !fourLetterWords.contains { word in bytes.hasText(word, at: start) }
        case 5: return !fiveLetterWords.contains { word in bytes.hasText(word, at: start) }
        default: return true
        }
    }

    private static let fourLetterWords: [StaticString] = ["null", "Null", "NULL", "true", "True", "TRUE"]
    private static let fiveLetterWords: [StaticString] = ["false", "False", "FALSE"]
}
