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
    var shape: Range<Int>?
    var label: Range<Int>?
    var labelType: Range<Int>?
    var view: Range<Int>?
    var icon: Range<Int>?
    var image: Range<Int>?
    var form: Range<Int>?
    var position: Range<Int>?
    var constraint: Range<Int>?
    var width: Range<Int>?
    var height: Range<Int>?

    private enum Key {
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
        func once(_ slot: inout Range<Int>?) -> Bool {
            guard slot == nil else { return false }
            slot = value
            return true
        }
        switch key {
        case .shape: return once(&shape)
        case .label: return value.allSatisfy { index in bytes.base[index] < 0x80 } && once(&label)
        case .labelType: return once(&labelType)
        case .view: return once(&view)
        case .icon: return once(&icon)
        case .image: return once(&image)
        case .form: return once(&form)
        case .position: return once(&position)
        case .constraint: return once(&constraint)
        case .width: return once(&width)
        case .height: return once(&height)
        case .other: return true
        }
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
