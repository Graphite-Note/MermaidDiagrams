/**
 * File: MermaidOutlineReader.swift
 * --------------------------------
 * Layer: Core
 * Description: Reads the indented outline Mermaid's mindmap and kanban grammars share: a node per line with its
 *              indentation, icons and classes for the node above, comments, and a kanban card's metadata.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// A decoration of the node written last: `::icon(name)` or `:::classes`.
enum MermaidOutlineDecoration: Equatable {
    case icon(String)
    case classes(String)
}

/// What takes an outline's statements in the order they are written: a mindmap's tree, a kanban board's columns.
protocol MermaidOutlineBuilding {
    /// A node written `indentation` characters in on `line`, with the text of its `@{ … }` when it has one.
    mutating func addNode(_ definition: MindmapNodeDefinition, indentation: Int, metadata: String?, line: Int) throws(MermaidDiagramReadError)
    mutating func decorate(_ decoration: MermaidOutlineDecoration)
    mutating func apply(_ statement: MermaidAccessibilityStatement)
}

/// The grammar of one outline type: what it reads beyond the nodes, decorations and comments both have.
struct MermaidOutlineGrammar {
    /// `accTitle` and `accDescr`, which Mermaid's mindmap grammar does not have and this package reads for a screen reader.
    let readsAccessibilityStatements: Bool
    /// A kanban card's `@{ … }` straight after its node; `@` then ends an identifier, as in Mermaid's kanban lexer.
    let readsMetadata: Bool

    static let mindmap = MermaidOutlineGrammar(readsAccessibilityStatements: true, readsMetadata: false)
    static let kanban = MermaidOutlineGrammar(readsAccessibilityStatements: false, readsMetadata: true)
}

/// Reads an outline's lines after its keyword, the rest of the keyword's own line included, as Pele's `common/outline.ts`
/// tokenizes them for mindmaps and kanban boards. A line holds one statement: a node, indented to show its place; an
/// icon (`::icon(…)`, the name to the closing parenthesis) or classes (`:::…`, the rest of the line) for the node above
/// it; accessibility text where the grammar reads it. Blank lines and `%%` comments are skipped, and a `%%` comment may
/// end a line.
struct MermaidOutlineReader {
    private var cursor: MermaidTextCursor
    private let grammar: MermaidOutlineGrammar

    /// Reads the outline whose keyword ends at the cursor into `builder`.
    static func read(_ cursor: MermaidTextCursor, grammar: MermaidOutlineGrammar, into builder: inout some MermaidOutlineBuilding) throws(MermaidDiagramReadError) {
        var reader = MermaidOutlineReader(cursor: cursor, grammar: grammar)
        try reader.readLines(into: &builder)
    }

    private init(cursor: MermaidTextCursor, grammar: MermaidOutlineGrammar) {
        self.cursor = cursor
        self.grammar = grammar
    }

    private mutating func readLines(into builder: inout some MermaidOutlineBuilding) throws(MermaidDiagramReadError) {
        while !cursor.isAtEnd {
            let indentation = readIndentation()
            if isAtLineEnd {
                skipLineEnd()
                continue
            }
            if cursor.hasPrefix(Self.commentStart) {
                cursor.skipToEndOfLine()
                continue
            }
            try readStatement(indentation: indentation, into: &builder)
            try expectLineEnd()
        }
    }

    /// Moves past the spaces and tabs that start a line and returns how many there were.
    private mutating func readIndentation() -> Int {
        let start = cursor.position
        cursor.skipSpaces()
        return cursor.position - start
    }

    private mutating func readStatement(indentation: Int, into builder: inout some MermaidOutlineBuilding) throws(MermaidDiagramReadError) {
        let line = cursor.line
        if grammar.readsAccessibilityStatements, let statement = try MermaidAccessibilityStatement.read(&cursor) {
            builder.apply(statement)
        } else if cursor.hasPrefix(Self.classMarker) {
            cursor.advance(by: Self.classMarker.count)
            let start = cursor.position
            cursor.skipToEndOfLine()
            builder.decorate(.classes(cursor.text(from: start, to: cursor.position)))
        } else if cursor.hasCaseInsensitivePrefix(Self.iconStart) {
            builder.decorate(.icon(try readIcon()))
        } else {
            let node = try MindmapNodeSyntax.readNode(&cursor, identifierEndsAtAtSign: grammar.readsMetadata)
            let metadata = grammar.readsMetadata && cursor.hasPrefix(Self.metadataStart) ? try readMetadata() : nil
            try builder.addNode(node, indentation: indentation, metadata: metadata, line: line)
        }
    }

    /// `::icon(name)`: the name runs to the closing parenthesis.
    private mutating func readIcon() throws(MermaidDiagramReadError) -> String {
        let openingLine = cursor.line
        cursor.advance(by: Self.iconStart.count)
        let start = cursor.position
        while let byte = cursor.peek(), byte != Self.closingParenthesis { cursor.advance() }
        guard !cursor.isAtEnd else { throw .invalidSyntax(line: openingLine, problem: .unclosedIcon) }
        let name = cursor.text(from: start, to: cursor.position)
        cursor.advance()
        return name
    }

    /// `@{ … }`: the text between the braces, which may cross lines; a closing brace inside quotation marks does not end
    /// it, and a line break inside them is written `<br/>`, as Mermaid's kanban lexer writes it.
    private mutating func readMetadata() throws(MermaidDiagramReadError) -> String {
        let openingLine = cursor.line
        cursor.advance(by: Self.metadataStart.count)
        var text: [UInt8] = []
        var isQuoted = false
        while let byte = cursor.peek(), isQuoted || byte != MermaidByte.closingBrace {
            if byte == MermaidByte.quotationMark { isQuoted.toggle() }
            if !isQuoted, byte == Self.caret { throw .invalidSyntax(line: cursor.line, problem: .unexpectedText(cursor.excerpt())) }
            cursor.advance()
            if isQuoted, byte == MermaidByte.newline {
                text += Self.quotedLineBreak
                cursor.skipWhitespace()
            } else {
                text.append(byte)
            }
        }
        guard !cursor.isAtEnd else { throw .invalidSyntax(line: openingLine, problem: .unclosedAttributes) }
        cursor.advance()
        return String(decoding: text, as: UTF8.self)
    }

    private var isAtLineEnd: Bool {
        guard let byte = cursor.peek() else { return true }
        return byte == MermaidByte.newline || byte == MermaidByte.carriageReturn
    }

    /// Moves past a line break, `\n` or `\r\n`.
    private mutating func skipLineEnd() {
        if cursor.peek() == MermaidByte.carriageReturn { cursor.advance() }
        if cursor.peek() == MermaidByte.newline { cursor.advance() }
    }

    /// A statement is followed by spaces, an optional `%%` comment and the end of its line; anything else is an error.
    private mutating func expectLineEnd() throws(MermaidDiagramReadError) {
        cursor.skipSpaces()
        if cursor.hasPrefix(Self.commentStart) { cursor.skipToEndOfLine() }
        guard isAtLineEnd else { throw .invalidSyntax(line: cursor.line, problem: .unexpectedText(cursor.excerpt())) }
        skipLineEnd()
    }

    private static let commentStart = Array("%%".utf8)
    private static let classMarker = Array(":::".utf8)
    /// Lowercased, for a comparison without regard to case.
    private static let iconStart = Array("::icon(".utf8)
    private static let metadataStart = Array("@{".utf8)
    private static let quotedLineBreak = Array("<br/>".utf8)
    private static let closingParenthesis = UInt8(ascii: ")")
    /// Mermaid's kanban lexer reads no caret in metadata outside quotation marks.
    private static let caret = UInt8(ascii: "^")
}
