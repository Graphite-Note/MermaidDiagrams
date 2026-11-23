/**
 * File: YAMLBytes.swift
 * ---------------------
 * Layer: Core
 * Description: The UTF-8 bytes of a YAML text as Pele's YAML reader sorts its scalars: Unicode's white space, what
 *              JavaScript's `trim` takes off, and how many scalars a run of white space holds.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

/// The scalars of a YAML text read from its UTF-8 bytes, as the reader's port of Pele's reader sorts them
/// (`SequenceAttributesFlowSyntax.isWhitespace`, `isTrimmed`). The text is a Swift string's, so it is valid UTF-8 and a
/// scalar's length is its first byte's; a byte that cannot start a scalar counts as one byte that is never white space.
enum YAMLBytes {
    static let space = UInt8(ascii: " ")
    static let tab = UInt8(ascii: "\t")
    static let newline = UInt8(ascii: "\n")
    static let carriageReturn = UInt8(ascii: "\r")
    static let hash = UInt8(ascii: "#")
    static let colon = UInt8(ascii: ":")
    static let comma = UInt8(ascii: ",")
    static let hyphen = UInt8(ascii: "-")
    static let backslash = UInt8(ascii: "\\")
    static let quotationMark = UInt8(ascii: "\"")
    static let apostrophe = UInt8(ascii: "'")
    static let openingBrace = UInt8(ascii: "{")
    static let closingBrace = UInt8(ascii: "}")
    static let openingBracket = UInt8(ascii: "[")
    static let closingBracket = UInt8(ascii: "]")

    /// A set of ASCII bytes, tested without hashing: YAML's indicators.
    struct ASCIISet {
        private let lowMask: UInt64
        private let highMask: UInt64

        init(_ scalars: [Unicode.Scalar]) {
            var lowMask: UInt64 = 0
            var highMask: UInt64 = 0
            for scalar in scalars where scalar.isASCII {
                if scalar.value < 64 { lowMask |= 1 << UInt64(scalar.value) } else { highMask |= 1 << UInt64(scalar.value - 64) }
            }
            self.lowMask = lowMask
            self.highMask = highMask
        }

        @inline(__always)
        func contains(_ byte: UInt8) -> Bool {
            byte < 64 ? lowMask & (1 << UInt64(byte)) != 0 : byte < 128 && highMask & (1 << UInt64(byte - 64)) != 0
        }

        static let none = ASCIISet([])
    }

    /// How many bytes the scalar that `first` starts takes.
    @inline(__always)
    static func scalarLength(startingWith first: UInt8) -> Int {
        first < 0xC0 ? 1 : first < 0xE0 ? 2 : first < 0xF0 ? 3 : 4
    }

    /// The length of the white-space scalar at `index`, before `end`: Unicode's White_Space, and also the byte order
    /// mark when `orByteOrderMark` (JavaScript's `trim`); 0 when the scalar there is not one.
    @inline(__always)
    static func whitespaceLength<Bytes: RandomAccessCollection<UInt8>>(in bytes: Bytes, at index: Int, end: Int,
                                                                        orByteOrderMark: Bool = false) -> Int where Bytes.Index == Int {
        let first = bytes[index]
        if first < 0x80 { return first == space || (0x09...0x0D).contains(first) ? 1 : 0 }
        return nonASCIIWhitespaceLength(in: bytes, at: index, end: end, orByteOrderMark: orByteOrderMark)
    }

    /// The length of the white-space scalar that ends just before `end` and starts at `start` or after; 0 when the
    /// scalar there is not one.
    static func whitespaceLength<Bytes: RandomAccessCollection<UInt8>>(in bytes: Bytes, endingAt end: Int, from start: Int,
                                                                        orByteOrderMark: Bool = false) -> Int where Bytes.Index == Int {
        let last = bytes[end - 1]
        if last < 0x80 { return last == space || (0x09...0x0D).contains(last) ? 1 : 0 }
        var first = end - 1
        while first > start, bytes[first] & 0xC0 == 0x80 { first -= 1 }
        let length = nonASCIIWhitespaceLength(in: bytes, at: first, end: end, orByteOrderMark: orByteOrderMark)
        return first + length == end ? length : 0
    }

    /// Whether the scalar at `index` is white space, as `SequenceAttributesFlowSyntax.isWhitespace` tests it.
    @inline(__always)
    static func isWhitespace<Bytes: RandomAccessCollection<UInt8>>(in bytes: Bytes, at index: Int,
                                                                    end: Int) -> Bool where Bytes.Index == Int {
        whitespaceLength(in: bytes, at: index, end: end) > 0
    }

    /// The bounds of `range` without what JavaScript's `trim` takes off either end.
    static func trimmedBounds<Bytes: RandomAccessCollection<UInt8>>(in bytes: Bytes, _ range: Range<Int>) -> Range<Int> where Bytes.Index == Int {
        var start = range.lowerBound
        var end = range.upperBound
        while start < end, case let length = whitespaceLength(in: bytes, at: start, end: end, orByteOrderMark: true), length > 0 {
            start += length
        }
        while end > start, case let length = whitespaceLength(in: bytes, endingAt: end, from: start, orByteOrderMark: true), length > 0 {
            end -= length
        }
        return start..<end
    }

    /// Whether `range` holds nothing JavaScript's `trim` keeps.
    static func isBlank(in bytes: [UInt8], _ range: Range<Int>) -> Bool {
        trimmedBounds(in: bytes, range).isEmpty
    }

    /// The white space at the start of `range` (with the byte order mark when `orByteOrderMark`): how many scalars it
    /// holds and where it ends.
    static func leadingWhitespace(in bytes: [UInt8], _ range: Range<Int>, orByteOrderMark: Bool) -> (scalarCount: Int, end: Int) {
        var scalarCount = 0
        var index = range.lowerBound
        while index < range.upperBound,
              case let length = whitespaceLength(in: bytes, at: index, end: range.upperBound, orByteOrderMark: orByteOrderMark), length > 0 {
            scalarCount += 1
            index += length
        }
        return (scalarCount, index)
    }

    /// Where `range` is once its first `count` scalars, white space or byte order marks, are passed.
    static func passingLeadingWhitespace(_ count: Int, in bytes: [UInt8], _ range: Range<Int>) -> Int {
        var index = range.lowerBound
        for _ in 0..<count where index < range.upperBound {
            index += max(1, whitespaceLength(in: bytes, at: index, end: range.upperBound, orByteOrderMark: true))
        }
        return index
    }

    /// Where the bytes are once `count` scalars from `index` are passed, the end at the latest.
    static func passingScalars(_ count: Int, in bytes: [UInt8], from index: Int, end: Int) -> Int {
        var position = index
        for _ in 0..<count where position < end { position += scalarLength(startingWith: bytes[position]) }
        return min(position, end)
    }

    /// The first `byte` in `range`, or its end.
    @inline(__always)
    static func firstIndex(of byte: UInt8, in bytes: [UInt8], _ range: Range<Int>) -> Int {
        var index = range.lowerBound
        while index < range.upperBound, bytes[index] != byte { index += 1 }
        return index
    }

    /// The text of the bytes in `range`, which start and end at scalars.
    @inline(__always)
    static func string(_ bytes: [UInt8], _ range: Range<Int>) -> String {
        String(decoding: bytes[range], as: UTF8.self)
    }

    private static func nonASCIIWhitespaceLength<Bytes: RandomAccessCollection<UInt8>>(in bytes: Bytes, at index: Int, end: Int,
                                                                                        orByteOrderMark: Bool) -> Int where Bytes.Index == Int {
        let first = bytes[index]
        // Every white-space scalar beyond ASCII, and the byte order mark, takes two or three bytes.
        guard first >= 0xC2, first <= 0xEF else { return 0 }
        let length = first < 0xE0 ? 2 : 3
        guard index + length <= end else { return 0 }
        var value = UInt32(first & (length == 2 ? 0x1F : 0x0F))
        for offset in 1..<length {
            let continuation = bytes[index + offset]
            guard continuation & 0xC0 == 0x80 else { return 0 }
            value = value << 6 | UInt32(continuation & 0x3F)
        }
        guard let scalar = Unicode.Scalar(value) else { return 0 }
        return scalar.properties.isWhitespace || (orByteOrderMark && value == 0xFEFF) ? length : 0
    }
}
