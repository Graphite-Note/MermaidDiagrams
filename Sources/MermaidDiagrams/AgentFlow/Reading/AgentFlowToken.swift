/**
 * File: AgentFlowToken.swift
 * --------------------------
 * Layer: Core
 * Description: The tokens of an agent flow's text, in the order and with the names of Pele's tokens.ts, and where each
 *              one sits in the text.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// A token of an agent flow, as Pele's `tokens.ts` numbers them (the order of Mermaid's agentflow.jison terminals).
enum AgentFlowTokenKind: Int, Comparable {
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
    var grammarName: String { Self.grammarNames[rawValue] }

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

/// The tokens of a text: each one's kind, where its text starts and ends in UTF-16 code units, and the line and column
/// it starts and ends at, counted as Jison counts them (lines from 1, columns from 0). A token whose text is not the
/// text it covers (the `@{` that opens metadata, a quoted metadata string with its line breaks made `<br/>`) keeps its
/// text apart.
struct AgentFlowTokens {
    var kinds: [AgentFlowTokenKind] = []
    var starts: [Int] = []
    var ends: [Int] = []
    /// Four numbers per token: first line, first column, last line, last column.
    var locations: [Int] = []
    var replacedTexts: [Int: String] = [:]

    var count: Int { kinds.count }

    /// The text of the token at `index` in `units`.
    func text(at index: Int, in units: [UInt16]) -> String {
        if let replaced = replacedTexts[index] { return replaced }
        return String(decoding: units[starts[index]..<ends[index]], as: UTF16.self)
    }

    /// The span from the start of the token at `first` to the end of the token at `last`.
    func span(from first: Int, to last: Int) -> AgentFlowSourceSpan {
        AgentFlowSourceSpan(firstLine: locations[4 * first], firstColumn: locations[4 * first + 1], lastLine: locations[4 * last + 2],
                            lastColumn: locations[4 * last + 3])
    }
}

/// A stretch of the text as Jison reports it: lines from 1, columns from 0.
struct AgentFlowSourceSpan: Equatable {
    var firstLine: Int
    var firstColumn: Int
    var lastLine: Int
    var lastColumn: Int
}
