/**
 * File: FlowchartLookAheadIndex.swift
 * -----------------------------------
 * Layer: Core
 * Description: Where a flowchart's text holds the far-reaching patterns Pele's lexer tests at the start of every token
 *              (a direction statement later on the line, a link identifier's `@` later in the word), found once, so
 *              that each token's test takes a binary search instead of a scan to the line's or the word's end.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

/// The positions of a flowchart's text that the lexer's look-ahead patterns depend on, each list in increasing order.
/// Scanning to the line's end at every token made a line of many short tokens (`a:a:a:…`, `&&&…`) take time growing
/// with the square of its length: a 48,000-byte line ran for minutes.
struct FlowchartLookAheadIndex {
    /// Where `direction`, white space and one of `TB`, `BT`, `RL`, `LR` or `TD` start.
    private let directionStatementStarts: [Int]
    /// Where a line feed, a carriage return, or a line or paragraph separator stands: what `.` does not match.
    private let lineTerminators: [Int]
    /// Where an `@` stands that neither `{` nor `"` follows.
    private let linkIdentifierEnds: [Int]
    /// Where JavaScript white space or a quotation mark stands: what ends a link identifier's word.
    private let wordBreaks: [Int]

    /// Finds the `@`s and the direction statements first, which most flowcharts have none of: the line terminators are
    /// listed only when a direction statement is there to compare them with, and the word breaks only when a link
    /// identifier's `@` is there to look for, since each test answers no without them.
    init(bytes: [UInt8]) {
        var linkIdentifierEnds: [Int] = []
        var searchStart = 0
        while let atSign = MermaidPreprocessing.firstIndex(of: MermaidByte.atSign, in: bytes, from: searchStart) {
            if atSign + 1 >= bytes.count || (bytes[atSign + 1] != MermaidByte.openingBrace && bytes[atSign + 1] != MermaidByte.quotationMark) {
                linkIdentifierEnds.append(atSign)
            }
            searchStart = atSign + 1
        }
        var directionStatementStarts: [Int] = []
        searchStart = 0
        while let start = MermaidPreprocessing.firstIndex(of: Self.direction, in: bytes, from: searchStart) {
            if Self.isDirectionStatement(in: bytes, at: start) { directionStatementStarts.append(start) }
            searchStart = start + 1
        }
        var lineTerminators: [Int] = []
        if !directionStatementStarts.isEmpty {
            for position in bytes.indices where Self.isLineTerminator(in: bytes, at: position) { lineTerminators.append(position) }
        }
        var wordBreaks: [Int] = []
        if !linkIdentifierEnds.isEmpty {
            for position in bytes.indices {
                let byte = bytes[position]
                let isBreak = byte == MermaidByte.quotationMark || byte == MermaidByte.space || (byte >= MermaidByte.tab && byte <= MermaidByte.carriageReturn)
                    || (byte >= 0xC2 && JavaScriptWhitespace.length(in: bytes, at: position) > 0)
                if isBreak { wordBreaks.append(position) }
            }
        }
        self.directionStatementStarts = directionStatementStarts
        self.lineTerminators = lineTerminators
        self.linkIdentifierEnds = linkIdentifierEnds
        self.wordBreaks = wordBreaks
    }

    /// Whether the text holds an `@` that can end a link identifier: without one, no position starts a link identifier.
    var hasLinkIdentifierEnds: Bool { !linkIdentifierEnds.isEmpty }

    /// The lexer's direction statement, `.*direction\s+(TB|BT|RL|LR|TD)[^\n]*` from `position`: whether `direction`,
    /// white space and a direction start anywhere from `position` up to the line's end.
    func startsDirectionStatement(at position: Int) -> Bool {
        guard let start = Self.first(in: directionStatementStarts, atOrAfter: position) else { return false }
        guard let lineEnd = Self.first(in: lineTerminators, atOrAfter: position) else { return true }
        return start < lineEnd
    }

    /// The position of the last `@` of the word from `position` (up to the next white space or quotation mark), after
    /// `position`, that neither `{` nor `"` follows; nil when there is none.
    func lastLinkIdentifierEnd(inWordFrom position: Int) -> Int? {
        let wordEnd = Self.first(in: wordBreaks, atOrAfter: position) ?? Int.max
        guard let last = Self.last(in: linkIdentifierEnds, before: wordEnd), last > position else { return nil }
        return last
    }

    private static func isDirectionStatement(in bytes: [UInt8], at position: Int) -> Bool {
        guard position + direction.count <= bytes.count, bytes[position..<position + direction.count].elementsEqual(direction) else { return false }
        let wordEnd = position + direction.count
        let afterSpaces = JavaScriptWhitespace.endOfRun(in: bytes, from: wordEnd)
        guard afterSpaces > wordEnd, afterSpaces + 2 <= bytes.count else { return false }
        return directions.contains { word in bytes[afterSpaces..<afterSpaces + 2].elementsEqual(word) }
    }

    private static func isLineTerminator(in bytes: [UInt8], at position: Int) -> Bool {
        let byte = bytes[position]
        if byte == MermaidByte.newline || byte == MermaidByte.carriageReturn { return true }
        return byte == 0xE2 && position + 2 < bytes.count && bytes[position + 1] == 0x80 && (bytes[position + 2] == 0xA8 || bytes[position + 2] == 0xA9)
    }

    /// The first element of the increasing `positions` that is `position` or more.
    private static func first(in positions: [Int], atOrAfter position: Int) -> Int? {
        var low = 0
        var high = positions.count
        while low < high {
            let middle = (low + high) / 2
            if positions[middle] < position { low = middle + 1 } else { high = middle }
        }
        return low < positions.count ? positions[low] : nil
    }

    /// The last element of the increasing `positions` that is less than `limit`.
    private static func last(in positions: [Int], before limit: Int) -> Int? {
        var low = 0
        var high = positions.count
        while low < high {
            let middle = (low + high) / 2
            if positions[middle] < limit { low = middle + 1 } else { high = middle }
        }
        return low > 0 ? positions[low - 1] : nil
    }

    private static let direction = Array("direction".utf8)
    private static let directions = ["TB", "BT", "RL", "LR", "TD"].map { word in Array(word.utf8) }
}
