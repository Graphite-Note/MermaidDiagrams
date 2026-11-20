/**
 * File: FlowchartNodeSyntax.swift
 * -------------------------------
 * Layer: Core
 * Description: Reads what follows a flowchart node's identifier: a shape in brackets around its text, or attributes.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.3
 * Date: 19/11/2026
 */

import Foundation

/// What a node's brackets or `@{ … }` say about it: its shape, its text, or both.
struct FlowchartNodeDefinition {
    var shape: FlowchartNodeShape?
    var label: DiagramLabel?
    /// `view: collapsed`, which a group's identifier takes to be drawn as one node.
    var asksForCollapsedView = false
}

/// Reads what follows a node's identifier: a shape in brackets around its text (`A{text}`), or attributes
/// (`A@{ shape: diam, label: "text" }`).
enum FlowchartNodeSyntax {
    /// The brackets that open a shape, longest first so that `((` is not read as `(`, and the texts that close each.
    private static let shapeBrackets: [(opening: [UInt8], closings: [(text: [UInt8], shape: FlowchartNodeShape)])] = [
        (Array("(((".utf8), [(Array(")))".utf8), .doubleCircle)]),
        (Array("((".utf8), [(Array("))".utf8), .circle)]),
        (Array("([".utf8), [(Array("])".utf8), .stadium)]),
        (Array("(-".utf8), [(Array("-)".utf8), .ellipse), (Array("/)".utf8), .ellipse), (Array("))".utf8), .ellipse)]),
        (Array("(".utf8), [(Array(")".utf8), .roundedRectangle)]),
        (Array("[[".utf8), [(Array("]]".utf8), .subroutine)]),
        (Array("[(".utf8), [(Array(")]".utf8), .cylinder)]),
        (Array("[/".utf8), [(Array("/]".utf8), .leanRight), (Array("\\]".utf8), .trapezoid)]),
        (Array("[\\".utf8), [(Array("\\]".utf8), .leanLeft), (Array("/]".utf8), .invertedTrapezoid)]),
        (Array("[".utf8), [(Array("]".utf8), .rectangle)]),
        (Array(">".utf8), [(Array("]".utf8), .asymmetric)]),
        (Array("{{".utf8), [(Array("}}".utf8), .hexagon)]),
        (Array("{".utf8), [(Array("}".utf8), .diamond)]),
    ]

    /// Reads a shape and its text at the cursor, which is right after the identifier, or returns nil and leaves the
    /// cursor where it was when no shape opens there.
    static func readShape(_ cursor: inout MermaidTextCursor) throws(MermaidDiagramReadError) -> FlowchartNodeDefinition? {
        if cursor.hasPrefix(propertyOpening) { return try readRectangleWithProperty(&cursor) }
        guard let brackets = shapeBrackets.first(where: { brackets in cursor.hasPrefix(brackets.opening) }) else { return nil }
        let openingLine = cursor.line
        cursor.advance(by: brackets.opening.count)
        let (label, closingIndex) = try FlowchartTextSyntax.readText(&cursor, closedByAnyOf: brackets.closings.map(\.text),
                                                                     openingLine: openingLine)
        return FlowchartNodeDefinition(shape: brackets.closings[closingIndex].shape, label: label)
    }

    private static let propertyOpening = Array("[|".utf8)

    /// `[|borders:lt|text]`, a rectangle with a property written before its text, as Pele's parser reads it
    /// (`VERTEX_WITH_PROPS_START`, a word, `:`, a word, `|`, then the text up to `]`): the property is read and left, as
    /// Pele keeps it without drawing it. Written otherwise, it is refused, as Pele refuses it.
    private static func readRectangleWithProperty(_ cursor: inout MermaidTextCursor) throws(MermaidDiagramReadError) -> FlowchartNodeDefinition {
        let openingLine = cursor.line
        cursor.advance(by: propertyOpening.count)
        for separator in [MermaidByte.colon, MermaidByte.verticalBar] {
            let wordStart = cursor.position
            while let byte = cursor.peek(), byte != separator, !MermaidByte.isSpace(byte), !MermaidByte.endsStatement(byte),
                  byte != MermaidByte.colon, byte != MermaidByte.verticalBar, byte != MermaidByte.closingBracket { cursor.advance() }
            guard cursor.position > wordStart, cursor.peek() == separator else {
                throw .invalidSyntax(line: cursor.line, problem: cursor.isAtEnd ? .unclosedShape(closingText: "]") : .unexpectedText(cursor.excerpt()))
            }
            cursor.advance()
        }
        let (label, _) = try FlowchartTextSyntax.readText(&cursor, closedByAnyOf: [Array("]".utf8)], openingLine: openingLine)
        return FlowchartNodeDefinition(shape: .rectangle, label: label)
    }

    /// Whether `@{` follows, which opens a node's (or an edge's) attributes.
    static func isAtAttributes(_ cursor: MermaidTextCursor) -> Bool {
        cursor.peek() == MermaidByte.atSign && cursor.peek(1) == MermaidByte.openingBrace
    }

    /// Reads `@{ key: value, … }`. `shape`, `label` and `view: collapsed` are kept, a shape Mermaid does not know refused
    /// (`FlowchartNodeShape.named`); other keys (`icon`, `img`, `pos`, …) are read and left.
    static func readAttributes(_ cursor: inout MermaidTextCursor) throws(MermaidDiagramReadError) -> FlowchartNodeDefinition {
        let openingLine = cursor.line
        cursor.advance(by: 2)
        var definition = FlowchartNodeDefinition()
        while true {
            while let byte = cursor.peek(), byte == MermaidByte.comma || MermaidByte.isSpace(byte) || byte == MermaidByte.newline
                    || byte == MermaidByte.carriageReturn { cursor.advance() }
            guard let byte = cursor.peek() else { throw .invalidSyntax(line: openingLine, problem: .unclosedAttributes) }
            if byte == MermaidByte.closingBrace {
                cursor.advance()
                return definition
            }
            let attributeLine = cursor.line
            let (key, value) = try readAttribute(&cursor, openingLine: openingLine)
            switch key.lowercased() {
            case "shape":
                // An empty name, as Pele reads `shape:` with nothing after it, changes nothing.
                let name = FlowchartTextSyntax.unquoted(value).text
                if !name.isEmpty { definition.shape = try FlowchartNodeShape.named(name, line: attributeLine) }
            case "label":
                let written = FlowchartTextSyntax.unquoted(value)
                definition.label = DiagramLabelDecoder.label(from: written.text, form: written.form)
            case "view": definition.asksForCollapsedView = FlowchartTextSyntax.unquoted(value).text == "collapsed"
            default: break
            }
        }
    }

    /// One `key: value` of an attribute list; the value is quoted text or runs to a comma, a line break or the brace.
    private static func readAttribute(_ cursor: inout MermaidTextCursor, openingLine: Int) throws(MermaidDiagramReadError) -> (String, String) {
        let keyStart = cursor.position
        while let byte = cursor.peek(), MermaidByte.isIdentifierByte(byte) || byte == MermaidByte.hyphen { cursor.advance() }
        let key = cursor.text(from: keyStart, to: cursor.position)
        cursor.skipSpaces()
        guard !key.isEmpty, cursor.peek() == MermaidByte.colon else {
            throw .invalidSyntax(line: cursor.line, problem: cursor.isAtEnd ? .unclosedAttributes : .unexpectedText(cursor.excerpt()))
        }
        cursor.advance()
        cursor.skipSpaces()
        let valueStart = cursor.position
        if cursor.peek() == MermaidByte.quotationMark {
            cursor.advance()
            while let byte = cursor.peek(), byte != MermaidByte.quotationMark { cursor.advance() }
            guard !cursor.isAtEnd else { throw .invalidSyntax(line: openingLine, problem: .unclosedQuotation) }
            cursor.advance()
            return (key, cursor.text(from: valueStart, to: cursor.position))
        }
        while let byte = cursor.peek(), byte != MermaidByte.comma, byte != MermaidByte.newline, byte != MermaidByte.closingBrace { cursor.advance() }
        return (key, cursor.text(from: valueStart, to: cursor.position).trimmingCharacters(in: .whitespaces))
    }
}
