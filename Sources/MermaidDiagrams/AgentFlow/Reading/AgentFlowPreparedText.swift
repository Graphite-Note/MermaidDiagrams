/**
 * File: AgentFlowPreparedText.swift
 * ---------------------------------
 * Layer: Core
 * Description: An agent flow's text as Pele hands it to its parser, on UTF-8 bytes, the token sets its grammar uses,
 *              and where a syntax error sits.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 26/11/2026
 */

/// The text Pele's parser reads: line breaks made `\n`, directives taken out (here blanked, a space for each UTF-16 code
/// unit, so that lines keep their numbers and columns their counts), a line break added at the end, and the spaces
/// between a closing brace and the end of its line removed, as Mermaid trims them before parsing. Comments stay: the
/// agent flow's grammar reads them.
enum AgentFlowPreparedText {
    /// The prepared UTF-8 bytes of the text's `bytes`, and whether they are all ASCII.
    static func bytes(of source: ArraySlice<UInt8>) -> (bytes: [UInt8], isASCII: Bool) {
        var bytes = withLineFeeds(source)
        let isASCII = bytes.withUnsafeBufferPointer(GraphDiagramNameTable.isASCII)
        blankDirectives(in: &bytes, isASCII: isASCII)
        bytes.append(10)
        removeSpaceAfterClosingBraces(in: &bytes)
        return (bytes, isASCII)
    }

    /// The bytes with each `\r\n` and `\r` made `\n`, written in one pass into room for one more byte.
    private static func withLineFeeds(_ bytes: ArraySlice<UInt8>) -> [UInt8] {
        // Most texts have no carriage return: their bytes are copied whole.
        guard bytes.contains(13) else {
            var copied: [UInt8] = []
            copied.reserveCapacity(bytes.count + 1)
            copied.append(contentsOf: bytes)
            return copied
        }
        return [UInt8](unsafeUninitializedCapacity: bytes.count + 1) { buffer, count in
            var written = 0
            var previousWasCarriageReturn = false
            for byte in bytes {
                if byte == 13 {
                    buffer[written] = 10
                    written += 1
                    previousWasCarriageReturn = true
                    continue
                }
                if byte == 10, previousWasCarriageReturn {
                    previousWasCarriageReturn = false
                    continue
                }
                previousWasCarriageReturn = false
                buffer[written] = byte
                written += 1
            }
            count = written
        }
    }

    /// Each `%%{ … }%%` made spaces, its line breaks kept; one never closed runs to the end, as Pele's expression takes it.
    /// A character beyond ASCII becomes a space for each of its UTF-16 code units, as Pele blanks code units.
    private static func blankDirectives(in bytes: inout [UInt8], isASCII: Bool) {
        // Bytes before the first directive stay where they are.
        guard let first = firstDirective(in: bytes) else { return }
        var kept = first
        var index = first
        while index < bytes.count {
            guard index + 2 < bytes.count, bytes[index] == 37, bytes[index + 1] == 37, bytes[index + 2] == 123 else {
                bytes[kept] = bytes[index]
                kept += 1
                index += 1
                continue
            }
            var end = index + 3
            while end + 2 < bytes.count, !(bytes[end] == 125 && bytes[end + 1] == 37 && bytes[end + 2] == 37) { end += 1 }
            end = end + 2 < bytes.count ? end + 3 : bytes.count
            // Each character is read by its first byte and stepped over whole, before the spaces written for it, which
            // never reach past it, could be read: a four-byte character is two code units.
            var blank = index
            while blank < end {
                let byte = bytes[blank]
                let length = isASCII || byte < 0xC0 ? 1 : byte < 0xE0 ? 2 : byte < 0xF0 ? 3 : 4
                bytes[kept] = byte == 10 ? 10 : 32
                kept += 1
                if length == 4 {
                    bytes[kept] = 32
                    kept += 1
                }
                blank += length
            }
            index = end
        }
        bytes.removeLast(bytes.count - kept)
    }

    /// Where the first `%%{` starts, or nil.
    private static func firstDirective(in bytes: [UInt8]) -> Int? {
        var index = 0
        while index + 2 < bytes.count {
            guard let percent = bytes[index..<(bytes.count - 2)].firstIndex(of: 37) else { return nil }
            if bytes[percent + 1] == 37, bytes[percent + 2] == 123 { return percent }
            index = percent + 1
        }
        return nil
    }

    /// `}[^\S\n]*\n` made `}\n`, in place: the bytes kept are moved down over those removed, which only ever lie ahead
    /// of the byte being read.
    private static func removeSpaceAfterClosingBraces(in bytes: inout [UInt8]) {
        // Bytes before the first brace with spaces to remove after it stay where they are.
        guard let firstBrace = firstBraceWithSpaceAfter(in: bytes) else { return }
        var kept = firstBrace
        var index = firstBrace
        while index < bytes.count {
            let byte = bytes[index]
            bytes[kept] = byte
            kept += 1
            guard byte == 125 else {
                index += 1
                continue
            }
            var end = index + 1
            while end < bytes.count, bytes[end] != 10, case let length = JavaScriptWhitespace.length(in: bytes, at: end), length > 0 { end += length }
            index = end < bytes.count && bytes[end] == 10 ? end : index + 1
        }
        bytes.removeLast(bytes.count - kept)
    }

    /// The first closing brace that white space other than line feeds follows up to a line feed, or nil.
    private static func firstBraceWithSpaceAfter(in bytes: [UInt8]) -> Int? {
        var start = 0
        while let brace = bytes[start...].firstIndex(of: 125) {
            var end = brace + 1
            while end < bytes.count, bytes[end] != 10, case let length = JavaScriptWhitespace.length(in: bytes, at: end), length > 0 { end += length }
            if end > brace + 1, end < bytes.count, bytes[end] == 10 { return brace }
            start = brace + 1
        }
        return nil
    }
}

extension AgentFlowParser {
    /// The syntax error at the current token: Jison's name for it and what was expected, on the line of the token, or
    /// for the end of the text on its last line with content; text the lexer did not read is unrecognized.
    func failure(expecting expected: String) -> MermaidDiagramReadError {
        let kind = current
        var offset = index < tokens.count ? tokens.start(at: index) : preparedCount
        if kind == .endOfFile || kind == .end {
            // Comments are tokens here, so trailing ones are skipped.
            var last = index
            while last > 0, Self.trailingTokens.contains(self.kind(at: last - 1)) { last -= 1 }
            offset = trimmedLength(upTo: last < tokens.count ? tokens.start(at: last) : preparedCount)
        }
        let line = builder.lineOffset + lineNumber(at: offset)
        if kind == .error { return .invalidSyntax(line: line, problem: .agentFlow(.unrecognizedText)) }
        return .invalidSyntax(line: line, problem: .agentFlow(.unexpectedToken(found: kind.grammarName, expected: expected)))
    }

    /// The length of the text before `end` without the white space at its end.
    private func trimmedLength(upTo end: Int) -> Int {
        let bytes = builder.model.text.bytes
        var length = min(end, preparedCount)
        while length > 0, case let last = JavaScriptWhitespace.lengthOfLast(in: bytes[..<length]), last > 0 { length -= last }
        return length
    }

    /// The line of an offset, kept on the last line with content when it is past it, as Pele's `locate` does.
    private func lineNumber(at offset: Int) -> Int {
        let contentEnd = trimmedLength(upTo: preparedCount)
        let place = contentEnd > 0 && offset >= contentEnd ? contentEnd - 1 : offset
        var line = 1
        for byte in builder.model.text.bytes[..<min(place, preparedCount)] where byte == 10 { line += 1 }
        return line
    }

    static let identifierTokens: AgentFlowTokenKindSet = [.number, .nodeString, .down, .minus, .defaultKeyword, .comma, .colon, .ampersand,
                                                             .numberSign, .asterisk, .unicodeText]
    static let alphanumericTokens: AgentFlowTokenKindSet = [.number, .unicodeText, .nodeString, .direction, .down, .minus, .comma, .colon,
                                                               .ampersand, .numberSign, .asterisk]
    static let textWithoutTagsTokens: AgentFlowTokenKindSet = [
        .number, .nodeString, .space, .minus, .ampersand, .unicodeText, .colon, .asterisk, .numberSign, .style, .linkStyle, .classDefinition,
        .classKeyword, .click, .graph, .direction, .flow, .connector, .global, .endKeyword, .down, .up, .startLink,
    ]
    static let styleTokens: AgentFlowTokenKindSet = [.number, .nodeString, .colon, .space, .numberSign, .style]
    static let separators: AgentFlowTokenKindSet = [.newline, .semicolon, .endOfFile, .comment]
    static let trailingTokens: AgentFlowTokenKindSet = [.comment, .newline, .space, .endOfFile]
    /// What a node's text holds after its first token.
    static let nodeTextTokens: AgentFlowTokenKindSet = [.text, .tagStart, .tagEnd, .unicodeText]
    static let textTokens = "'UNICODE_TEXT', 'TEXT', 'TAGSTART'"
    static let separatorNames = "'COMMENT', 'SEMI', 'NEWLINE', 'EOF'"
    static let statementStart = "'COMMENT', 'SEMI', 'NEWLINE', 'SPACE', 'EOF', 'flow', 'global', 'connector', 'acc_title', 'acc_descr', "
        + "'acc_descr_multiline_value', 'STYLE', 'LINKSTYLE', 'CLASSDEF', 'CLASS', 'CLICK', 'NODE_STRING'"
}
