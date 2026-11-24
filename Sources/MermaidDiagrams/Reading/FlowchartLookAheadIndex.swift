/**
 * File: FlowchartLookAheadIndex.swift
 * -----------------------------------
 * Layer: Core
 * Description: The positions of a flowchart's text that the lexer's far look-aheads depend on (a direction statement
 *              later on the line, a link identifier's last `@` in its word), found only in a text that holds them and
 *              answered by binary search, so that a line of many short tokens stays linear to read.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

/// The positions the lexer's look-ahead patterns depend on, each list increasing, borrowed from `FlowchartLookAheadLists`
/// for one reading. Scanning to the line's end at every token made a line of many short tokens (`a:a:a:…`, `&&&…`) take
/// time growing with the square of its length; each look-up here is a binary search.
struct FlowchartLookAheadIndex {
    /// Where `direction`, white space and one of `TB`, `BT`, `RL`, `LR` or `TD` start.
    private let directionStarts: UnsafeBufferPointer<Int32>
    /// For each direction statement, the position after the first byte of the last line terminator before it (a line
    /// feed, a carriage return, a line or paragraph separator), 0 when there is none: a position from there to the
    /// statement's start is on its line.
    private let directionLineStarts: UnsafeBufferPointer<Int32>
    /// Where an `@` stands that neither `{` nor `"` follows.
    private let linkAtSigns: UnsafeBufferPointer<Int32>
    /// For each such `@`, the position after the last word break before it (white space or a quotation mark).
    private let linkWordStarts: UnsafeBufferPointer<Int32>
    /// For each such `@`, the last such `@` of its word.
    private let linkLastAtSigns: UnsafeBufferPointer<Int32>

    /// The index of a text that holds no direction statement and no link identifier.
    static var empty: FlowchartLookAheadIndex { FlowchartLookAheadIndex(positions: UnsafeBufferPointer(start: nil, count: 0), directionCount: 0, linkCount: 0) }

    /// The index over `positions`, laid out as `FlowchartLookAheadLists` lays them out.
    init(positions: UnsafeBufferPointer<Int32>, directionCount: Int, linkCount: Int) {
        func slice(_ start: Int, _ length: Int) -> UnsafeBufferPointer<Int32> {
            length == 0 ? UnsafeBufferPointer(start: nil, count: 0) : UnsafeBufferPointer(rebasing: positions[start..<start + length])
        }
        directionStarts = slice(0, directionCount)
        directionLineStarts = slice(directionCount, directionCount)
        linkAtSigns = slice(directionCount * 2, linkCount)
        linkWordStarts = slice(directionCount * 2 + linkCount, linkCount)
        linkLastAtSigns = slice(directionCount * 2 + linkCount * 2, linkCount)
    }

    var hasDirectionStatements: Bool { !directionStarts.isEmpty }
    var hasLinkAtSigns: Bool { !linkAtSigns.isEmpty }

    /// Whether `direction`, white space and a direction start anywhere from `position` up to the line's end.
    func startsDirectionStatement(at position: Int) -> Bool {
        let index = Self.firstIndex(in: directionStarts, atLeast: position)
        return index < directionStarts.count && Int(directionLineStarts[index]) <= position
    }

    /// The position of the last `@` of the word from `position` (up to the next white space or quotation mark), after
    /// `position`, that neither `{` nor `"` follows; nil when there is none.
    func lastLinkAtSign(inWordFrom position: Int) -> Int? {
        let index = Self.firstIndex(in: linkAtSigns, atLeast: position + 1)
        guard index < linkAtSigns.count, Int(linkWordStarts[index]) <= position else { return nil }
        return Int(linkLastAtSigns[index])
    }

    /// The index of the first element of the increasing `positions` that is `position` or more; their count when none is.
    private static func firstIndex(in positions: UnsafeBufferPointer<Int32>, atLeast position: Int) -> Int {
        var low = 0
        var high = positions.count
        while low < high {
            let middle = (low + high) / 2
            if Int(positions[middle]) < position { low = middle + 1 } else { high = middle }
        }
        return low
    }
}

/// The lists of a `FlowchartLookAheadIndex`, one array of positions reused by the readings of a thread: the direction
/// statements' starts and line starts, then the link `@`s, their words' starts and their words' last `@`s.
struct FlowchartLookAheadLists {
    private(set) var positions: [Int32] = []
    private(set) var directionCount = 0
    private(set) var linkCount = 0

    /// Finds the positions in `bytes`, each kind only when a quick scan finds it may be there.
    mutating func build(over bytes: UnsafeBufferPointer<UInt8>) {
        positions.removeAll(keepingCapacity: true)
        directionCount = 0
        linkCount = 0
        if Self.mayContainDirection(bytes) { addDirectionStatements(in: bytes) }
        if Self.containsLinkAtSign(bytes) { addLinkAtSigns(in: bytes) }
    }

    /// Calls `body` with the index over the lists.
    func withIndex<Result>(_ body: (FlowchartLookAheadIndex) -> Result) -> Result {
        guard !positions.isEmpty else { return body(.empty) }
        return positions.withUnsafeBufferPointer { buffer in
            body(FlowchartLookAheadIndex(positions: buffer, directionCount: directionCount, linkCount: linkCount))
        }
    }

    private mutating func addDirectionStatements(in bytes: UnsafeBufferPointer<UInt8>) {
        var starts: [Int32] = []
        var lineStarts: [Int32] = []
        var lineStart = 0
        for position in 0..<bytes.count {
            let byte = bytes[position]
            if byte == MermaidByte.newline || byte == MermaidByte.carriageReturn
                || (byte == 0xE2 && position + 2 < bytes.count && bytes[position + 1] == 0x80 && (bytes[position + 2] == 0xA8 || bytes[position + 2] == 0xA9)) {
                lineStart = position + 1
            } else if byte == UInt8(ascii: "d"), Self.isDirectionStatement(in: bytes, at: position) {
                starts.append(Int32(position))
                lineStarts.append(Int32(lineStart))
            }
        }
        directionCount = starts.count
        positions.append(contentsOf: starts)
        positions.append(contentsOf: lineStarts)
    }

    private mutating func addLinkAtSigns(in bytes: UnsafeBufferPointer<UInt8>) {
        var atSigns: [Int32] = []
        var wordStarts: [Int32] = []
        var wordStart = 0
        for position in 0..<bytes.count {
            let byte = bytes[position]
            if byte == MermaidByte.quotationMark || JavaScriptWhitespace.length(in: bytes, at: position) > 0 {
                wordStart = position + 1
            } else if byte == MermaidByte.atSign, Self.isLinkAtSign(in: bytes, at: position) {
                atSigns.append(Int32(position))
                wordStarts.append(Int32(wordStart))
            }
        }
        var lastAtSigns = atSigns
        for index in atSigns.indices.dropLast().reversed() where wordStarts[index] == wordStarts[index + 1] { lastAtSigns[index] = lastAtSigns[index + 1] }
        linkCount = atSigns.count
        positions.append(contentsOf: atSigns)
        positions.append(contentsOf: wordStarts)
        positions.append(contentsOf: lastAtSigns)
    }

    /// An `@` that neither `{` nor `"` follows.
    private static func isLinkAtSign(in bytes: UnsafeBufferPointer<UInt8>, at position: Int) -> Bool {
        position + 1 >= bytes.count || (bytes[position + 1] != MermaidByte.openingBrace && bytes[position + 1] != MermaidByte.quotationMark)
    }

    private static func containsLinkAtSign(_ bytes: UnsafeBufferPointer<UInt8>) -> Bool {
        var position = 0
        while let atSign = MermaidPreprocessing.firstIndex(of: MermaidByte.atSign, in: bytes, from: position) {
            if isLinkAtSign(in: bytes, at: atSign) { return true }
            position = atSign + 1
        }
        return false
    }

    /// `direction`, JavaScript white space, then `TB`, `BT`, `RL`, `LR` or `TD`, at `position`.
    private static func isDirectionStatement(in bytes: UnsafeBufferPointer<UInt8>, at position: Int) -> Bool {
        let word = "direction".utf8
        guard position + word.count <= bytes.count, bytes[position..<position + word.count].elementsEqual(word) else { return false }
        let wordEnd = position + word.count
        let afterSpaces = JavaScriptWhitespace.endOfRun(in: bytes, from: wordEnd)
        guard afterSpaces > wordEnd, afterSpaces + 2 <= bytes.count else { return false }
        switch (bytes[afterSpaces], bytes[afterSpaces + 1]) {
        case (0x54, 0x42), (0x42, 0x54), (0x52, 0x4C), (0x4C, 0x52), (0x54, 0x44): return true
        default: return false
        }
    }

    /// Whether `direction` may stand in the text: a `d` with an `i` after it and an `n` eight bytes after it, looked for
    /// sixteen places at a time.
    private static func mayContainDirection(_ bytes: UnsafeBufferPointer<UInt8>) -> Bool {
        guard bytes.count >= 9, let base = bytes.baseAddress else { return false }
        let raw = UnsafeRawPointer(base)
        var index = 0
        while index + 24 <= bytes.count {
            let starts = raw.loadUnaligned(fromByteOffset: index, as: SIMD16<UInt8>.self)
            let seconds = raw.loadUnaligned(fromByteOffset: index + 1, as: SIMD16<UInt8>.self)
            let ends = raw.loadUnaligned(fromByteOffset: index + 8, as: SIMD16<UInt8>.self)
            if any((starts .== SIMD16(repeating: UInt8(ascii: "d"))) .& (seconds .== SIMD16(repeating: UInt8(ascii: "i")))
                .& (ends .== SIMD16(repeating: UInt8(ascii: "n")))) { return true }
            index += 16
        }
        while index + 9 <= bytes.count {
            if bytes[index] == UInt8(ascii: "d"), bytes[index + 1] == UInt8(ascii: "i"), bytes[index + 8] == UInt8(ascii: "n") { return true }
            index += 1
        }
        return false
    }
}
