/**
 * File: AgentFlowLexerBytes.swift
 * -------------------------------
 * Layer: Core
 * Description: How an agent flow's lexer reads characters on the text's UTF-8 bytes as Pele reads UTF-16 code units,
 *              moves over a match counting Jison's lines and columns in code units, and records each token.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

extension AgentFlowLexer {
    /// The character starting at `index` as Pele's `charCodeAt` reads it, or -1 past either end (JavaScript's NaN), which
    /// no rule matches. A character beyond the Basic Multilingual Plane, two code units in UTF-16, reads as its high
    /// surrogate (0xD800, which no rule takes), and a byte inside a character as a low surrogate (0xDC00): the rules
    /// that test one character only ever test the first byte of one, or compare with ASCII.
    @inline(__always)
    func character(at index: Int) -> Int {
        guard index >= 0, index < bytes.count else { return -1 }
        let byte = bytes[index]
        return byte < 0x80 ? Int(byte) : decodedCharacter(at: index, lead: byte)
    }

    private func decodedCharacter(at index: Int, lead: UInt8) -> Int {
        if lead < 0xC0 { return 0xDC00 }
        if lead >= 0xF0 { return 0xD800 }
        let second = index + 1 < bytes.count ? Int(bytes[index + 1] & 0x3F) : 0
        if lead < 0xE0 { return Int(lead & 0x1F) << 6 | second }
        let third = index + 2 < bytes.count ? Int(bytes[index + 2] & 0x3F) : 0
        return Int(lead & 0x0F) << 12 | second << 6 | third
    }

    /// The number of bytes of the character starting at `index`: one for ASCII.
    @inline(__always)
    func characterLength(at index: Int) -> Int {
        let byte = bytes[index]
        if byte < 0xC0 { return 1 }
        return byte < 0xE0 ? 2 : byte < 0xF0 ? 3 : 4
    }

    /// The length in bytes of the white space (JavaScript's `\s`) at `index`, or zero for any other character.
    @inline(__always)
    func spaceLength(at index: Int) -> Int {
        guard index < bytes.count else { return 0 }
        let byte = bytes[index]
        if byte < 0x80 { return byte == 32 || (byte >= 9 && byte <= 13) ? 1 : 0 }
        return JavaScriptWhitespace.length(in: bytes, at: index)
    }

    /// Whether the character at `index` is white space.
    func isSpace(at index: Int) -> Bool { spaceLength(at: index) > 0 }

    /// The UTF-16 code units of the bytes from `start` to `end`, which hold whole characters: a byte per unit in ASCII,
    /// else one unit for each character but those beyond the Basic Multilingual Plane, which take two.
    @inline(__always)
    func codeUnitCount(from start: Int, to end: Int) -> Int32 {
        if isASCII { return Int32(truncatingIfNeeded: end - start) }
        var units: Int32 = 0
        var index = start
        while index < end {
            let byte = bytes[index]
            if byte & 0xC0 != 0x80 { units += byte >= 0xF0 ? 2 : 1 }
            index += 1
        }
        return units
    }

    /// Whether a line ends at `index`: a line feed, a carriage return, or U+2028 or U+2029, which `.` does not match.
    func isLineTerminator(at index: Int) -> Bool {
        let byte = bytes[index]
        if byte == 10 || byte == 13 { return true }
        return byte == 0xE2 && index + 2 < bytes.count && bytes[index + 1] == 0x80 && (bytes[index + 2] == 0xA8 || bytes[index + 2] == 0xA9)
    }

    // MARK: - Moving and emitting

    /// Moves over a match to `end`. Jison counts `\r\n`, `\r` and `\n` as one line break each, and after a break its
    /// column stops at the first U+2028 or U+2029.
    mutating func advance(to end: Int) {
        var lastBreak = -1
        var index = position
        while index < end {
            let byte = bytes[index]
            if byte == 10 {
                line += 1
                lastBreak = index
            } else if byte == 13 {
                if index + 1 < end, bytes[index + 1] == 10 { index += 1 }
                line += 1
                lastBreak = index
            }
            index += 1
        }
        if lastBreak < 0 {
            column += codeUnitCount(from: position, to: end)
        } else {
            var stop = lastBreak + 1
            while stop < end, !isLineOrParagraphSeparator(at: stop) { stop += 1 }
            column = codeUnitCount(from: lastBreak + 1, to: stop)
        }
        position = end
    }

    private func isLineOrParagraphSeparator(at index: Int) -> Bool {
        bytes[index] == 0xE2 && isLineTerminator(at: index)
    }

    mutating func emit(_ kind: AgentFlowTokenKind, to end: Int) {
        let (start, firstLine, firstColumn) = (position, line, column)
        advance(to: end)
        append(kind, from: start, to: end, firstLine: firstLine, firstColumn: firstColumn)
    }

    /// A token that cannot hold a line break.
    mutating func emitFlat(_ kind: AgentFlowTokenKind, to end: Int) {
        let (start, firstColumn) = (position, column)
        column += codeUnitCount(from: position, to: end)
        position = end
        append(kind, from: start, to: end, firstLine: line, firstColumn: firstColumn)
    }

    /// A run Jison matches one character at a time, where `\r\n` counts as two line breaks.
    mutating func emitCharacters(_ kind: AgentFlowTokenKind, to end: Int) {
        let (start, firstLine, firstColumn) = (position, line, column)
        for index in position..<end {
            let byte = bytes[index]
            if byte == 10 || byte == 13 {
                line += 1
                column = 0
            } else if byte & 0xC0 != 0x80 {
                column += byte >= 0xF0 ? 2 : 1
            }
        }
        position = end
        append(kind, from: start, to: end, firstLine: firstLine, firstColumn: firstColumn)
    }

    /// The token from `start` to `end`, which the lexer has moved over: it ends at the current line and column.
    @inline(__always)
    private mutating func append(_ kind: AgentFlowTokenKind, from start: Int, to end: Int, firstLine: Int32, firstColumn: Int32) {
        tokens.records.append(AgentFlowToken(kind: kind, start: Int32(truncatingIfNeeded: start), end: Int32(truncatingIfNeeded: end), firstLine: firstLine,
                                             firstColumn: firstColumn, lastLine: line, lastColumn: column))
    }

    /// A metadata token whose text is not the text it covers but the derived bytes from `textStart` to their end.
    mutating func emitShapeData(textFrom textStart: Int, to end: Int) {
        tokens.replacedTokenIndices.append(Int32(tokens.count))
        tokens.replacedRanges.append(MermaidTextRange(start: bytes.count + textStart, end: bytes.count + derived.count))
        emit(.shapeData, to: end)
    }
}
