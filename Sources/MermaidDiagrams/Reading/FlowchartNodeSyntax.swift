/**
 * File: FlowchartNodeSyntax.swift
 * -------------------------------
 * Layer: Core
 * Description: Reads what follows a flowchart node's identifier: a shape in brackets around its text, or attributes.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.6
 * Date: 23/11/2026
 */

import Foundation

/// What a node's brackets or `@{ … }` say about it: its shape, its text, or both.
struct FlowchartNodeDefinition {
    var shape: FlowchartNodeShape?
    var label: DiagramLabel?
    /// Whether `label:` was written with nothing but spaces in it, or not at all: such a node drawn as an icon or a picture
    /// loses the identifier it would otherwise show, as in Pele.
    var hasBlankWrittenLabel = true
    /// `view: collapsed`, which a group's identifier takes to be drawn as one node.
    var asksForCollapsedView = false
    /// The icon and picture attributes written (`icon`, `img`, `form`, `pos`, `w`, `h`, `constraint`); nil for one not written.
    var assetAttributes = FlowchartNodeAssetAttributes()
}

/// Reads what follows a node's identifier: a shape in brackets around its text (`A{text}`), or attributes
/// (`A@{ shape: diam, label: "text" }`).
enum FlowchartNodeSyntax {
    /// The brackets that open a shape, the texts that close each and the state its text is read in, made once.
    private static let shapeBrackets = writtenShapeBrackets.map { brackets in
        (opening: brackets.opening, closings: brackets.closings, closingTexts: brackets.closings.map { closing in closing.text },
         textState: textState(after: brackets.opening))
    }

    /// The brackets that open a shape, longest first so that `((` is not read as `(`, and the texts that close each.
    private static let writtenShapeBrackets: [(opening: [UInt8], closings: [(text: [UInt8], shape: FlowchartNodeShape)])] = [
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
        let (label, closingIndex) = try FlowchartTextSyntax.readText(&cursor, closedByAnyOf: brackets.closingTexts, state: brackets.textState,
                                                                     openingLine: openingLine)
        return FlowchartNodeDefinition(shape: brackets.closings[closingIndex].shape, label: label)
    }

    private static let propertyOpening = Array("[|".utf8)

    /// The lexer state Pele reads the text after `opening` in: a trapezoid's after `[/` and `[\`, an ellipse's after
    /// `(-`, plain text's after every other bracket.
    private static func textState(after opening: [UInt8]) -> FlowchartTextState {
        switch String(decoding: opening, as: UTF8.self) {
        case "[/", "[\\": .trapezoid
        case "(-": .ellipse
        default: .text
        }
    }

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
}
