/**
 * File: UseCaseJSONReader.swift
 * -----------------------------
 * Layer: Core
 * Description: Reads the JSON object of a use case diagram's `json` statement as JSON.parse and Pele's propertyOrder
 *              walk read it together: its keys in the order written, nesting kept on a stack of its own, and on text
 *              that is not JSON the offset of the first character that is not.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

/// Reads JSON text on UTF-16 code units, as JavaScript reads it, into a `UseCaseJSONValue`. Nesting is kept on a stack
/// of its own, so its depth is bounded by the text and not by the thread's stack.
struct UseCaseJSONReader {
    /// Why the text is not JSON: the offset, in code units from its start, of the first character that is not.
    struct Failure: Error, Equatable {
        let offset: Int
    }

    private struct Frame {
        let entry: Int
        let isObject: Bool
        /// Where each key read so far is among the object's keys.
        var keyPlaces: [String: Int] = [:]
        var pendingKey = ""
    }

    private enum State {
        case value, key, afterValue
    }

    private let units: ArraySlice<UInt16>
    private var position: Int
    private var entries: [UseCaseJSONValue.Entry] = []
    private var stack: [Frame] = []

    /// `units` read as one JSON value, or the offset of the first character that is not JSON.
    static func read(_ units: ArraySlice<UInt16>) throws(Failure) -> UseCaseJSONValue {
        var reader = UseCaseJSONReader(units: units)
        try reader.readValue()
        return UseCaseJSONValue(entries: reader.entries)
    }

    private init(units: ArraySlice<UInt16>) {
        self.units = units
        position = units.startIndex
    }

    private func unit(at index: Int) -> UInt16? { index < units.endIndex ? units[index] : nil }

    private func failure(at index: Int) -> Failure { Failure(offset: index - units.startIndex) }

    private mutating func skipWhitespace() {
        while let unit = unit(at: position), unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D { position += 1 }
    }

    private mutating func readValue() throws(Failure) {
        var state = State.value
        skipWhitespace()
        while true {
            switch state {
            case .value:
                state = try readOneValue()
            case .key:
                try readKey()
                state = .value
            case .afterValue:
                guard !stack.isEmpty else {
                    skipWhitespace()
                    guard position == units.endIndex else { throw failure(at: position) }
                    return
                }
                state = try readAfterValue()
            }
        }
    }

    /// A scalar, or the start of an object or array: the state after it.
    private mutating func readOneValue() throws(Failure) -> State {
        skipWhitespace()
        guard let first = unit(at: position) else { throw failure(at: position) }
        switch first {
        case UInt16(ascii: "{"), UInt16(ascii: "["):
            let isObject = first == UInt16(ascii: "{")
            position += 1
            let entry = attach(isObject ? .object : .array)
            skipWhitespace()
            if unit(at: position) == UInt16(ascii: isObject ? "}" : "]") {
                position += 1
                return .afterValue
            }
            stack.append(Frame(entry: entry, isObject: isObject))
            return isObject ? .key : .value
        case UInt16(ascii: "\""): attach(.string(try readString()))
        case UInt16(ascii: "t"): try readLiteral("true", kind: .boolean(true))
        case UInt16(ascii: "f"): try readLiteral("false", kind: .boolean(false))
        case UInt16(ascii: "n"): try readLiteral("null", kind: .null)
        case UInt16(ascii: "-"), UInt16(ascii: "0")...UInt16(ascii: "9"): attach(.number(try readNumber()))
        default: throw failure(at: position)
        }
        return .afterValue
    }

    /// An object's key and its colon.
    private mutating func readKey() throws(Failure) {
        guard unit(at: position) == UInt16(ascii: "\"") else { throw failure(at: position) }
        let key = try readString()
        skipWhitespace()
        guard unit(at: position) == UInt16(ascii: ":") else { throw failure(at: position) }
        position += 1
        stack[stack.count - 1].pendingKey = key
    }

    /// After a value inside a container: a comma and the next value or key, or the container's end.
    private mutating func readAfterValue() throws(Failure) -> State {
        skipWhitespace()
        let frame = stack[stack.count - 1]
        guard let next = unit(at: position) else { throw failure(at: position) }
        if next == UInt16(ascii: frame.isObject ? "}" : "]") {
            position += 1
            stack.removeLast()
            return .afterValue
        }
        guard next == UInt16(ascii: ",") else { throw failure(at: position) }
        position += 1
        skipWhitespace()
        return frame.isObject ? .key : .value
    }

    /// A new entry of `kind`, made a child of the container being read: under its pending key in an object, where a key
    /// written again takes its first place.
    @discardableResult
    private mutating func attach(_ kind: UseCaseJSONValue.Kind) -> Int {
        let index = entries.count
        entries.append(UseCaseJSONValue.Entry(kind: kind, keys: [], children: []))
        guard var frame = stack.popLast() else { return index }
        if !frame.isObject {
            entries[frame.entry].children.append(index)
        } else if let place = frame.keyPlaces[frame.pendingKey] {
            entries[frame.entry].children[place] = index
        } else {
            frame.keyPlaces[frame.pendingKey] = entries[frame.entry].keys.count
            entries[frame.entry].keys.append(frame.pendingKey)
            entries[frame.entry].children.append(index)
        }
        stack.append(frame)
        return index
    }

    private mutating func readLiteral(_ word: String, kind: UseCaseJSONValue.Kind) throws(Failure) {
        for (offset, expected) in word.utf16.enumerated() where unit(at: position + offset) != expected { throw failure(at: position + offset) }
        position += word.utf16.count
        attach(kind)
    }

    private func isDigit(_ unit: UInt16?) -> Bool {
        guard let unit else { return false }
        return unit >= UInt16(ascii: "0") && unit <= UInt16(ascii: "9")
    }

    private mutating func skipDigits() {
        while isDigit(unit(at: position)) { position += 1 }
    }

    /// A number in JSON's grammar, read as JavaScript reads it.
    private mutating func readNumber() throws(Failure) -> Double {
        let start = position
        if unit(at: position) == UInt16(ascii: "-") { position += 1 }
        if unit(at: position) == UInt16(ascii: "0") {
            position += 1
        } else if isDigit(unit(at: position)) {
            skipDigits()
        } else {
            throw failure(at: position)
        }
        if unit(at: position) == UInt16(ascii: ".") {
            position += 1
            guard isDigit(unit(at: position)) else { throw failure(at: position) }
            skipDigits()
        }
        if let exponent = unit(at: position), exponent | 0x20 == UInt16(ascii: "e") {
            position += 1
            if unit(at: position) == UInt16(ascii: "+") || unit(at: position) == UInt16(ascii: "-") { position += 1 }
            guard isDigit(unit(at: position)) else { throw failure(at: position) }
            skipDigits()
        }
        return Double(String(decoding: units[start..<position], as: UTF16.self)) ?? 0
    }

    /// A string from its opening quotation mark, its escapes decoded.
    private mutating func readString() throws(Failure) -> String {
        position += 1
        var decoded: [UInt16] = []
        while let current = unit(at: position) {
            let start = position
            position += 1
            if current == UInt16(ascii: "\"") { return String(decoding: decoded, as: UTF16.self) }
            guard current >= 0x20 else { throw failure(at: start) }
            guard current == UInt16(ascii: "\\") else {
                decoded.append(current)
                continue
            }
            decoded.append(try readEscape())
        }
        throw failure(at: position)
    }

    /// The code unit an escape after a backslash stands for.
    private mutating func readEscape() throws(Failure) -> UInt16 {
        guard let escape = unit(at: position) else { throw failure(at: position) }
        let escapeStart = position
        position += 1
        switch escape {
        case UInt16(ascii: "\""), UInt16(ascii: "\\"), UInt16(ascii: "/"): return escape
        case UInt16(ascii: "b"): return 0x08
        case UInt16(ascii: "f"): return 0x0C
        case UInt16(ascii: "n"): return 0x0A
        case UInt16(ascii: "r"): return 0x0D
        case UInt16(ascii: "t"): return 0x09
        case UInt16(ascii: "u"):
            guard position + 4 <= units.endIndex,
                  let value = UInt16(String(decoding: units[position..<(position + 4)], as: UTF16.self), radix: 16),
                  units[position..<(position + 4)].allSatisfy({ unit in Self.isHexadecimal(unit) }) else { throw failure(at: position) }
            position += 4
            return value
        default: throw failure(at: escapeStart)
        }
    }

    private static func isHexadecimal(_ unit: UInt16) -> Bool {
        (unit >= 0x30 && unit <= 0x39) || (unit >= 0x41 && unit <= 0x46) || (unit >= 0x61 && unit <= 0x66)
    }
}

extension UInt16 {
    /// The code unit of an ASCII character, as `UInt8(ascii:)` gives its byte.
    init(ascii scalar: Unicode.Scalar) {
        self = UInt16(truncatingIfNeeded: scalar.value)
    }
}
