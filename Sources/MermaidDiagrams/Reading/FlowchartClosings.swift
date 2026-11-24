/**
 * File: FlowchartClosings.swift
 * -----------------------------
 * Layer: Core
 * Description: The texts that may close a node's or an edge's text (up to three, each up to three bytes), and the
 *              set of bytes at which plain text in a lexer state may stop, both held without a list.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

/// A set of ASCII bytes as two 64-bit words.
struct FlowchartByteMask {
    var low: UInt64 = 0
    var high: UInt64 = 0

    @inline(__always) mutating func insert(_ byte: UInt8) {
        if byte < 64 { low |= 1 &<< UInt64(byte) } else if byte < 128 { high |= 1 &<< UInt64(byte - 64) }
    }

    @inline(__always) func contains(_ byte: UInt8) -> Bool {
        byte < 64 ? (low &>> UInt64(byte)) & 1 != 0 : byte < 128 && (high &>> UInt64(byte - 64)) & 1 != 0
    }

    /// Brackets, braces and parentheses, which end plain text in every state.
    static let brackets: FlowchartByteMask = {
        var mask = FlowchartByteMask()
        for byte in "()[]{}".utf8 { mask.insert(byte) }
        return mask
    }()
}

/// Up to three texts that close a node's or an edge's text, each up to three bytes, tried in their order: each packed in
/// a word, its bytes in the low three bytes and its length in the high one, 0 for none, so that the closings pass in
/// three words.
struct FlowchartClosings {
    private let first: UInt32
    private let second: UInt32
    private let third: UInt32

    init(_ first: StaticString, _ second: StaticString? = nil, _ third: StaticString? = nil) {
        self.first = Self.packed(first)
        self.second = second.map(Self.packed) ?? 0
        self.third = third.map(Self.packed) ?? 0
    }

    private static func packed(_ text: StaticString) -> UInt32 {
        let bytes = text.utf8Start
        var word = UInt32(text.utf8CodeUnitCount) << 24
        for offset in 0..<text.utf8CodeUnitCount { word |= UInt32(bytes[offset]) << (8 * offset) }
        return word
    }

    @inline(__always) private static func matches(_ closing: UInt32, in bytes: FlowchartBytes, at position: Int) -> Bool {
        let length = Int(closing >> 24)
        guard length > 0, bytes[position] == UInt8(truncatingIfNeeded: closing), position + length <= bytes.count else { return false }
        if length > 1, bytes[position + 1] != UInt8(truncatingIfNeeded: closing >> 8) { return false }
        return length < 3 || bytes[position + 2] == UInt8(truncatingIfNeeded: closing >> 16)
    }

    /// The index of the first closing at `position`, or nil.
    @inline(__always) func match(in bytes: FlowchartBytes, at position: Int) -> Int? {
        if Self.matches(first, in: bytes, at: position) { return 0 }
        if Self.matches(second, in: bytes, at: position) { return 1 }
        if Self.matches(third, in: bytes, at: position) { return 2 }
        return nil
    }

    /// The length of the closing at `index`.
    func length(_ index: Int) -> Int {
        Int((index == 0 ? first : index == 1 ? second : third) >> 24)
    }

    /// The first closing as text, which an unclosed text names.
    var firstText: String {
        String(decoding: (0..<Int(first >> 24)).map { offset in UInt8(truncatingIfNeeded: first >> (8 * offset)) }, as: UTF8.self)
    }

    /// The bytes at which plain text in `state` may stop: those that end it, and the closings' first bytes.
    func stopMask(state: FlowchartTextState) -> FlowchartByteMask {
        var mask = FlowchartByteMask.brackets
        if state == .text { mask.insert(MermaidByte.verticalBar) }
        if state != .trapezoid { mask.insert(MermaidByte.quotationMark) }
        mask.insert(UInt8(truncatingIfNeeded: first))
        if second != 0 { mask.insert(UInt8(truncatingIfNeeded: second)) }
        if third != 0 { mask.insert(UInt8(truncatingIfNeeded: third)) }
        return mask
    }
}
