/**
 * File: AgentFlowPreparedText.swift
 * ---------------------------------
 * Layer: Core
 * Description: An agent flow's text as Pele hands it to its parser, the token sets its grammar uses, and where a
 *              syntax error sits.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

/// The text Pele's parser reads: line breaks made `\n`, directives taken out (here blanked, so lines keep their
/// numbers), a line break added at the end, and the spaces between a closing brace and the end of its line removed, as
/// Mermaid trims them before parsing. Comments stay: the agent flow's grammar reads them.
enum AgentFlowPreparedText {
    static func units(of text: String) -> [UInt16] {
        // Text in ASCII has a UTF-16 code unit per byte, of the same value: it is read from its bytes.
        var units = text.utf8.allSatisfy({ byte in byte < 0x80 })
            ? withLineFeeds(text.utf8.lazy.map(UInt16.init), capacity: text.utf8.count + 1)
            : withLineFeeds(text.utf16, capacity: text.utf16.count + 1)
        blankDirectives(in: &units)
        units.append(10)
        return withoutSpaceAfterClosingBraces(units)
    }

    /// The code units with each `\r\n` and `\r` made `\n`.
    private static func withLineFeeds(_ written: some Sequence<UInt16>, capacity: Int) -> [UInt16] {
        var units: [UInt16] = []
        units.reserveCapacity(capacity)
        var previousWasCarriageReturn = false
        for unit in written {
            if unit == 13 {
                units.append(10)
                previousWasCarriageReturn = true
                continue
            }
            if unit == 10, previousWasCarriageReturn {
                previousWasCarriageReturn = false
                continue
            }
            previousWasCarriageReturn = false
            units.append(unit)
        }
        return units
    }

    /// Each `%%{ … }%%` made spaces, its line breaks kept; one never closed runs to the end, as Pele's expression takes it.
    private static func blankDirectives(in units: inout [UInt16]) {
        var index = 0
        while index + 2 < units.count {
            guard units[index] == 37, units[index + 1] == 37, units[index + 2] == 123 else {
                index += 1
                continue
            }
            var end = index + 3
            while end + 2 < units.count, !(units[end] == 125 && units[end + 1] == 37 && units[end + 2] == 37) { end += 1 }
            end = end + 2 < units.count ? end + 3 : units.count
            for blank in index..<end where units[blank] != 10 { units[blank] = 32 }
            index = end
        }
    }

    /// `}[^\S\n]*\n` made `}\n`.
    private static func withoutSpaceAfterClosingBraces(_ units: [UInt16]) -> [UInt16] {
        // Without a closing brace there is nothing to remove.
        guard units.contains(125) else { return units }
        var kept: [UInt16] = []
        kept.reserveCapacity(units.count)
        var index = 0
        while index < units.count {
            kept.append(units[index])
            guard units[index] == 125 else {
                index += 1
                continue
            }
            var end = index + 1
            while end < units.count, units[end] != 10, C4Characters.isSpace(units[end]) { end += 1 }
            index = end < units.count && units[end] == 10 ? end : index + 1
        }
        return kept
    }
}

extension AgentFlowParser {
    /// The syntax error at the current token: Jison's name for it and what was expected, on the line of the token, or
    /// for the end of the text on its last line with content; text the lexer did not read is unrecognized.
    func failure(expecting expected: String) -> MermaidDiagramReadError {
        let kind = current
        var offset = index < tokens.count ? tokens.starts[index] : units.count
        if kind == .endOfFile || kind == .end {
            // Comments are tokens here, so trailing ones are skipped.
            var last = index
            while last > 0, Self.trailingTokens.contains(self.kind(at: last - 1)) { last -= 1 }
            offset = trimmedLength(upTo: last < tokens.count ? tokens.starts[last] : units.count)
        }
        let line = builder.lineOffset + lineNumber(at: offset)
        if kind == .error { return .invalidSyntax(line: line, problem: .agentFlow(.unrecognizedText)) }
        return .invalidSyntax(line: line, problem: .agentFlow(.unexpectedToken(found: kind.grammarName, expected: expected)))
    }

    /// The length of the text before `end` without the white space at its end.
    private func trimmedLength(upTo end: Int) -> Int {
        var length = min(end, units.count)
        while length > 0, C4Characters.isSpace(units[length - 1]) { length -= 1 }
        return length
    }

    /// The line of an offset, kept on the last line with content when it is past it, as Pele's `locate` does.
    private func lineNumber(at offset: Int) -> Int {
        let contentEnd = trimmedLength(upTo: units.count)
        let place = contentEnd > 0 && offset >= contentEnd ? contentEnd - 1 : offset
        var line = 1
        for unit in units[..<min(place, units.count)] where unit == 10 { line += 1 }
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
