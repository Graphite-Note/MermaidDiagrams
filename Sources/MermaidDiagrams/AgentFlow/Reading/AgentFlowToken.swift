/**
 * File: AgentFlowToken.swift
 * --------------------------
 * Layer: Core
 * Description: The tokens of an agent flow's text, in the order and with the names of Pele's tokens.ts, and where each
 *              one sits in the text's bytes and in Jison's lines and columns.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 26/11/2026
 */

/// A token of an agent flow, as Pele's `tokens.ts` numbers them (the order of Mermaid's agentflow.jison terminals).
enum AgentFlowTokenKind: UInt8, Comparable {
    case end, error, accessibilityTitle, accessibilityTitleValue, accessibilityDescription, accessibilityDescriptionValue
    case accessibilityDescriptionMultilineValue, shapeData, callbackName, callbackArguments, markdownString, string, style, defaultKeyword
    case linkStyle, interpolate, classDefinition, classKeyword, hyperlinkReference, click, graph, flow, connector, global, endKeyword
    case linkTarget, noDirection, direction, directionTopToBottom, directionBottomToTop, directionRightToLeft, directionLeftToRight
    case directionTopDown, linkIdentifier, number, numberSign, styleSeparator, colon, ampersand, semicolon, comma, asterisk, link
    case startLink, edgeText, ellipseEnd, text, ellipseStart, stadiumEnd, stadiumStart, subroutineEnd, subroutineStart
    case vertexWithPropertiesStart, tagEnd, cylinderEnd, cylinderStart, doubleCircleEnd, doubleCircleStart, trapezoidEnd
    case invertedTrapezoidEnd, trapezoidStart, invertedTrapezoidStart, tagStart, up, separator, down, comment, nodeString, minus
    case unicodeText, pipe, parenthesisEnd, parenthesisStart, squareEnd, squareStart, diamondStop, diamondStart, newline, space
    case endOfFile

    static func < (left: AgentFlowTokenKind, right: AgentFlowTokenKind) -> Bool { left.rawValue < right.rawValue }

    /// Jison's name of the token, as Mermaid's messages write it.
    var grammarName: String { Self.grammarNames[Int(rawValue)] }

    private static let grammarNames = [
        "$end", "INVALID", "acc_title", "acc_title_value", "acc_descr", "acc_descr_value", "acc_descr_multiline_value", "SHAPE_DATA",
        "CALLBACKNAME", "CALLBACKARGS", "MD_STR", "STR", "STYLE", "DEFAULT", "LINKSTYLE", "INTERPOLATE", "CLASSDEF", "CLASS", "HREF",
        "CLICK", "GRAPH", "flow", "connector", "global", "end", "LINK_TARGET", "NODIR", "DIR", "direction_tb", "direction_bt",
        "direction_rl", "direction_lr", "direction_td", "LINK_ID", "NUM", "BRKT", "STYLE_SEPARATOR", "COLON", "AMP", "SEMI", "COMMA",
        "MULT", "LINK", "START_LINK", "EDGE_TEXT", "-)", "TEXT", "(-", "STADIUMEND", "STADIUMSTART", "SUBROUTINEEND", "SUBROUTINESTART",
        "VERTEX_WITH_PROPS_START", "TAGEND", "CYLINDEREND", "CYLINDERSTART", "DOUBLECIRCLEEND", "DOUBLECIRCLESTART", "TRAPEND",
        "INVTRAPEND", "TRAPSTART", "INVTRAPSTART", "TAGSTART", "UP", "SEP", "DOWN", "COMMENT", "NODE_STRING", "MINUS", "UNICODE_TEXT",
        "PIPE", "PE", "PS", "SQE", "SQS", "DIAMOND_STOP", "DIAMOND_START", "NEWLINE", "SPACE", "EOF",
    ]
}

/// A token: its kind, where its bytes start and end in the prepared text, and the line and column it starts and ends
/// at, counted as Jison counts them (lines from 1, columns from 0 in UTF-16 code units).
struct AgentFlowToken {
    var kind: AgentFlowTokenKind
    var start: Int32
    var end: Int32
    var firstLine: Int32
    var firstColumn: Int32
    var lastLine: Int32
    var lastColumn: Int32
}

/// The tokens of a text, in one list in the thread's scratch arena. A token whose text is not the text it covers (the `@{` that opens metadata, a
/// quoted metadata string with its line breaks made `<br/>`) keeps its text apart, in the bytes after the prepared text.
struct AgentFlowTokens {
    var records: ScratchList<AgentFlowToken>
    /// The tokens whose text is not their bytes, in order, and the ranges of their texts.
    var replacedTokenIndices: [Int32] = []
    var replacedRanges: [MermaidTextRange] = []

    init(arena: DiagramScratchArena, capacity: Int) {
        records = arena.list(capacity: capacity)
    }

    var count: Int { records.count }

    @inline(__always)
    func kind(at index: Int) -> AgentFlowTokenKind { records[index].kind }

    @inline(__always)
    func start(at index: Int) -> Int { Int(records[index].start) }

    /// The range of the text of the token at `index`: its bytes, or for a metadata token whose text was made, that
    /// text's.
    func textRange(at index: Int) -> MermaidTextRange {
        let record = records[index]
        if record.kind == .shapeData, !replacedTokenIndices.isEmpty, let replaced = replacedRange(at: index) { return replaced }
        return MermaidTextRange(start: Int(record.start), end: Int(record.end))
    }

    private func replacedRange(at index: Int) -> MermaidTextRange? {
        var low = 0
        var high = replacedTokenIndices.count - 1
        while low <= high {
            let middle = (low + high) / 2
            let found = Int(replacedTokenIndices[middle])
            if found == index { return replacedRanges[middle] }
            if found < index { low = middle + 1 } else { high = middle - 1 }
        }
        return nil
    }

    /// The span from the start of the token at `first` to the end of the token at `last`.
    func span(from first: Int, to last: Int) -> AgentFlowSourceSpan {
        AgentFlowSourceSpan(firstLine: Int(records[first].firstLine), firstColumn: Int(records[first].firstColumn), lastLine: Int(records[last].lastLine),
                            lastColumn: Int(records[last].lastColumn))
    }
}

/// A stretch of the text as Jison reports it: lines from 1, columns from 0.
struct AgentFlowSourceSpan: Equatable {
    var firstLine: Int
    var firstColumn: Int
    var lastLine: Int
    var lastColumn: Int
}

/// A set of token kinds held in the bits of two integers, tested without hashing as the parser tests each token.
struct AgentFlowTokenKindSet: ExpressibleByArrayLiteral {
    private var lowBits: UInt64 = 0
    private var highBits: UInt64 = 0

    init(arrayLiteral kinds: AgentFlowTokenKind...) {
        for kind in kinds {
            precondition(kind.rawValue < 128, "a token kind beyond the set's 128 bits")
            if kind.rawValue < 64 { lowBits |= 1 << UInt64(kind.rawValue) } else { highBits |= 1 << UInt64(kind.rawValue - 64) }
        }
    }

    @inline(__always)
    func contains(_ kind: AgentFlowTokenKind) -> Bool {
        kind.rawValue < 64 ? lowBits & (1 << UInt64(kind.rawValue)) != 0 : highBits & (1 << UInt64(kind.rawValue - 64)) != 0
    }
}
