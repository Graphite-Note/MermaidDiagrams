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

/// Up to three texts that close a node's or an edge's text, each up to three bytes, tried in their order.
struct FlowchartClosings {
    private struct Closing {
        var first: UInt8
        var second: UInt8
        var third: UInt8
        var length: Int

        init(_ text: StaticString) {
            let start = text.utf8Start
            length = text.utf8CodeUnitCount
            first = start[0]
            second = length > 1 ? start[1] : 0
            third = length > 2 ? start[2] : 0
        }

        @inline(__always) func matches(in bytes: FlowchartBytes, at position: Int) -> Bool {
            guard bytes[position] == first, position + length <= bytes.count else { return false }
            if length > 1, bytes[position + 1] != second { return false }
            return length < 3 || bytes[position + 2] == third
        }
    }

    private let first: Closing
    private let second: Closing?
    private let third: Closing?
    private let firstWritten: StaticString

    /// The first closing as text, which an unclosed text names.
    var firstText: String { firstWritten.description }

    init(_ first: StaticString, _ second: StaticString? = nil, _ third: StaticString? = nil) {
        self.first = Closing(first)
        self.second = second.map(Closing.init)
        self.third = third.map(Closing.init)
        firstWritten = first
    }

    /// The index of the first closing at `position`, or nil.
    @inline(__always) func match(in bytes: FlowchartBytes, at position: Int) -> Int? {
        if first.matches(in: bytes, at: position) { return 0 }
        if let second, second.matches(in: bytes, at: position) { return 1 }
        if let third, third.matches(in: bytes, at: position) { return 2 }
        return nil
    }

    /// The length of the closing at `index`.
    func length(_ index: Int) -> Int {
        switch index {
        case 0: first.length
        case 1: second?.length ?? 0
        default: third?.length ?? 0
        }
    }

    /// The bytes at which plain text in `state` may stop: those that end it, and the closings' first bytes.
    func stopMask(state: FlowchartTextState) -> FlowchartByteMask {
        var mask = FlowchartByteMask.brackets
        if state == .text { mask.insert(MermaidByte.verticalBar) }
        if state != .trapezoid { mask.insert(MermaidByte.quotationMark) }
        mask.insert(first.first)
        if let second { mask.insert(second.first) }
        if let third { mask.insert(third.first) }
        return mask
    }
}
