/**
 * File: AgentFlowTextBytes.swift
 * ------------------------------
 * Layer: Core
 * Description: The bytes an agent flow's model indexes: the prepared text, then the texts made while reading it, with
 *              the trimming, unquoting and splitting 0.7.0 did on Strings done on ranges, as its Strings did them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

/// The prepared text's bytes and, after them, the texts the reader makes (identifiers joined from tokens that do not
/// follow one another, generated identifiers, constant names), which ranges of the model index alike. An operation
/// that 0.7.0 did on Swift characters (a prefix, a split) is done on bytes when the range is ASCII, where a byte is a
/// character, and on the String otherwise, as 0.7.0 did it.
struct AgentFlowTextBytes {
    var bytes: [UInt8] = []
    /// How many of the bytes are the prepared text's.
    var preparedCount = 0
    /// Whether the prepared text is ASCII: every text made from it then is.
    var isASCII = true

    init() {}

    /// The prepared text's `bytes`, then the texts its lexer made for some tokens.
    init(prepared bytes: consuming [UInt8], derived: [UInt8], isASCII: Bool) {
        self.bytes = bytes
        preparedCount = self.bytes.count
        // Room for the texts made while reading (identifiers made for edges, texts joined), so that they do not copy the
        // prepared text as they grow.
        self.bytes.reserveCapacity(preparedCount + derived.count + preparedCount / 2 + 64)
        self.bytes += derived
        self.isASCII = isASCII
    }

    func string(_ range: MermaidTextRange) -> String {
        bytes.withUnsafeBufferPointer { buffer in
            String(decoding: UnsafeBufferPointer(rebasing: buffer[range.lowerBound..<range.upperBound]), as: UTF8.self)
        }
    }

    /// The text of `range`, or nil for none.
    func string(orNil range: MermaidTextRange?) -> String? { range.map(string) }

    /// `made` appended after the bytes, and its range.
    mutating func append(_ made: some Sequence<UInt8>) -> MermaidTextRange {
        let start = bytes.count
        bytes.append(contentsOf: made)
        return MermaidTextRange(start: start, end: bytes.count)
    }

    /// The bytes of `range` appended again after the bytes, one by one: no slice of the bytes is held while they grow, so
    /// they are not copied.
    mutating func appendCopy(of range: MermaidTextRange) {
        bytes.reserveCapacity(bytes.count + range.count)
        var index = range.lowerBound
        while index < range.upperBound {
            bytes.append(bytes[index])
            index += 1
        }
    }

    /// Whether the bytes of `range` are all ASCII.
    func isASCII(_ range: MermaidTextRange) -> Bool {
        if isASCII { return true }
        var index = range.lowerBound
        while index < range.upperBound {
            if bytes[index] >= 0x80 { return false }
            index += 1
        }
        return true
    }

    func isEmpty(_ range: MermaidTextRange) -> Bool { range.isEmpty }

    /// Whether `range` holds exactly `word`'s bytes.
    func equals(_ range: MermaidTextRange, _ word: [UInt8]) -> Bool {
        guard range.count == word.count else { return false }
        for offset in 0..<word.count where bytes[range.lowerBound + offset] != word[offset] { return false }
        return true
    }

    /// Whether the byte `byte` is in `range`.
    func contains(_ range: MermaidTextRange, byte: UInt8) -> Bool {
        bytes[range.lowerBound..<range.upperBound].contains(byte)
    }

    /// `range` without the white space at either end, as JavaScript's `trim` and 0.7.0's `C4Characters.trimmed` leave it.
    func trimmed(_ range: MermaidTextRange) -> MermaidTextRange {
        var start = range.lowerBound
        var end = range.upperBound
        while start < end, bytes[start] < 0x80 {
            let byte = bytes[start]
            guard byte == 32 || (byte >= 9 && byte <= 13) else { break }
            start += 1
        }
        if start < end, bytes[start] >= 0x80 {
            let trimmed = JavaScriptWhitespace.trimmed(bytes[start..<end])
            return MermaidTextRange(start: trimmed.startIndex, end: trimmed.endIndex)
        }
        while end > start, bytes[end - 1] < 0x80 {
            let byte = bytes[end - 1]
            guard byte == 32 || (byte >= 9 && byte <= 13) else { break }
            end -= 1
        }
        if end > start, bytes[end - 1] >= 0x80 {
            let trimmed = JavaScriptWhitespace.trimmed(bytes[start..<end])
            return MermaidTextRange(start: trimmed.startIndex, end: trimmed.endIndex)
        }
        return MermaidTextRange(start: start, end: end)
    }

    /// `range` without the quotation marks around it, as 0.7.0's `unquoted` took them off its String: two characters at
    /// least, the first and the last a quotation mark.
    mutating func unquoted(_ range: MermaidTextRange) -> MermaidTextRange {
        guard range.count >= 2, bytes[range.lowerBound] == 34, bytes[range.upperBound - 1] == 34 else { return range }
        guard !isASCII(range) else { return MermaidTextRange(start: range.lowerBound + 1, end: range.upperBound - 1) }
        let text = string(range)
        guard text.count >= 2, text.hasPrefix("\""), text.hasSuffix("\"") else { return range }
        return append(String(text.dropFirst().dropLast()).utf8)
    }

    /// The pieces of `range` between its commas, as 0.7.0's `split(separator: ",", omittingEmptySubsequences: false)`
    /// cut its String, appended to `pieces`.
    mutating func appendCommaPieces(of range: MermaidTextRange, to pieces: inout ScratchList<MermaidTextRange>) {
        guard isASCII(range) else {
            for piece in string(range).split(separator: ",", omittingEmptySubsequences: false) { pieces.append(append(piece.utf8)) }
            return
        }
        var start = range.lowerBound
        for index in range.lowerBound..<range.upperBound where bytes[index] == 44 {
            pieces.append(MermaidTextRange(start: start, end: index))
            start = index + 1
        }
        pieces.append(MermaidTextRange(start: start, end: range.upperBound))
    }

    /// The range of `text`'s bytes once made: the first time it is asked for in this model, appended.
    mutating func constant(_ text: AgentFlowConstantText, cache: inout [MermaidTextRange?]) -> MermaidTextRange {
        if let made = cache[Int(text.rawValue)] { return made }
        let made = append(text.bytes)
        cache[Int(text.rawValue)] = made
        return made
    }
}

/// The texts the reader writes itself.
enum AgentFlowConstantText: UInt8, CaseIterable {
    case topToBottom, bottomToTop, rightToLeft, leftToRight, topDown, fillNone, defaultClass, nodeClass, clickable, edge, connectors

    var bytes: [UInt8] { Self.allBytes[Int(rawValue)] }

    private static let allBytes: [[UInt8]] = allCases.map { text in Array(text.text.utf8) }

    var text: String {
        switch self {
        case .topToBottom: "TB"
        case .bottomToTop: "BT"
        case .rightToLeft: "RL"
        case .leftToRight: "LR"
        case .topDown: "TD"
        case .fillNone: "fill:none"
        case .defaultClass: "default"
        case .nodeClass: "node"
        case .clickable: "clickable"
        case .edge: "edge"
        case .connectors: "connectors"
        }
    }
}
