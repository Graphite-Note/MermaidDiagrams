/**
 * File: ClassDiagramParser.swift
 * ------------------------------
 * Layer: Core
 * Description: Reads a class diagram's statements after its keyword, on the text's borrowed bytes, its names byte
 *              ranges until the diagram keeps them and each error's line counted only when it is reported.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.6
 * Date: 25/11/2026
 */

/// Reads a class diagram's statements after its `classDiagram` or `classDiagram-v2` keyword: classes with their
/// labels, annotations and members (`class Name["Label"] <<interface>> { … }`, `Name : +member`), relations
/// (`A "1" *-- "*" B : label`), annotations (`<<interface>> Name`), notes, namespaces, the direction and the
/// accessibility text, and the statements that only style the diagram or make it clickable, which are counted and
/// left. A statement ends at a line break; `%%` starts a comment.
struct ClassDiagramParser {
    private var cursor: GraphDiagramBytes
    private var builder: ClassDiagramBuilder

    /// Reads the class diagram whose keyword ends at the cursor, on the cursor's bytes, borrowed.
    static func parse(_ cursor: MermaidTextCursor, limits: MermaidDiagramLimits) throws(MermaidDiagramReadError) -> ClassDiagram {
        var diagram = try cursor.bytes.withUnsafeBufferPointer { buffer throws(MermaidDiagramReadError) in
            let bytes = GraphDiagramBytes(buffer, position: cursor.position)
            var parser = ClassDiagramParser(cursor: bytes, builder: ClassDiagramBuilder(limits: limits, bytes: bytes))
            try parser.expectStatementEnd()
            try parser.readStatements()
            return parser.builder.finished()
        }
        let options = MermaidConfigurationOptions(section: "class", in: cursor).values
        if case .boolean(false) = options["hierarchicalNamespaces"] { diagram.hierarchicalNamespaces = false }
        if case .boolean(true) = options["hideEmptyMembersBox"] { diagram.hidesEmptyMemberBoxes = true }
        return diagram
    }

    private mutating func readStatements() throws(MermaidDiagramReadError) {
        while true {
            cursor.skipWhitespace()
            if cursor.isAtEnd { return }
            if cursor.isAtCommentStart {
                cursor.skipToEndOfLine()
                continue
            }
            try readStatement()
            try expectStatementEnd()
        }
    }

    private mutating func readStatement() throws(MermaidDiagramReadError) {
        if cursor.isAt(MermaidByte.lessThan, MermaidByte.lessThan) { return try readAnnotationStatement() }
        guard let (keyword, length) = keywordAtCursor() else { return try readNameStatement() }
        cursor.advance(by: length)
        switch keyword {
        case .classStatement: _ = try readClassStatement()
        case .namespace: try readNamespace()
        case .note: try readNote()
        case .direction: readDirection()
        case .accessibilityTitle: builder.setAccessibilityTitle(readAccessibilityLine())
        case .accessibilityDescription: builder.setAccessibilityDescription(try readAccessibilityDescription())
        case .unapplied:
            // `style`, `classDef`, `cssClass`, `click`, `link` and `callback`.
            cursor.skipToEndOfLine()
            builder.countUnappliedStatement()
        }
    }

    /// The keyword at the cursor and its length, when one of the statements' keywords starts there, as written, and no
    /// identifier character follows it. `accTitle` and `accDescr` count only before their `:` or `{`, so that a class
    /// may bear another word's name.
    private func keywordAtCursor() -> (ClassDiagramKeyword, Int)? {
        var lookahead = cursor
        let word = lookahead.readWord()
        guard let keyword = ClassDiagramKeyword(word, in: cursor.buffer) else { return nil }
        if let next = lookahead.peek(), MermaidByte.isIdentifierByte(next) { return nil }
        guard keyword == .accessibilityTitle || keyword == .accessibilityDescription else { return (keyword, word.count) }
        lookahead.skipSpaces()
        let opens = lookahead.peek() == MermaidByte.colon || (keyword == .accessibilityDescription && lookahead.peek() == MermaidByte.openingBrace)
        return opens ? (keyword, word.count) : nil
    }

    // MARK: Classes

    /// `class Name~T~["Label"]:::style <<annotation>> { members }`, each part after the name optional. Returns the
    /// class's index.
    private mutating func readClassStatement() throws(MermaidDiagramReadError) -> Int {
        cursor.skipSpaces()
        guard let name = try ClassDiagramNameSyntax.read(&cursor) else { throw .invalidSyntax(line: cursor.line, problem: .expectedName) }
        let index = try builder.classIndex(for: name)
        cursor.skipSpaces()
        if cursor.peek() == MermaidByte.openingBracket { builder.setLabel(try readBracketedLabel(), ofClassAt: index) }
        cursor.skipSpaces()
        if cursor.isAt(MermaidByte.colon, MermaidByte.colon, MermaidByte.colon) {
            cursor.advance(by: 3)
            Self.skipIdentifier(&cursor)
            builder.countUnappliedStatement()
            cursor.skipSpaces()
        }
        if cursor.isAt(MermaidByte.lessThan, MermaidByte.lessThan) {
            builder.addAnnotation(try readAnnotation(), toClassAt: index)
            cursor.skipSpaces()
        }
        if cursor.peek() == MermaidByte.openingBrace { try readClassBody(ofClassAt: index, identifier: name.identifier) }
        return index
    }

    /// Moves past a run of identifier bytes, a `-` kept only where an identifier byte follows it
    /// (`MermaidTextCursor.readIdentifier`).
    private static func skipIdentifier(_ cursor: inout GraphDiagramBytes) {
        let start = cursor.position
        while let byte = cursor.peek() {
            if MermaidByte.isIdentifierByte(byte) {
                cursor.advance()
            } else if byte == MermaidByte.hyphen, cursor.position > start, let next = cursor.peek(1), MermaidByte.isIdentifierByte(next) {
                cursor.advance()
            } else {
                break
            }
        }
    }

    /// `["Label"]`, the label quoted inside square brackets.
    private mutating func readBracketedLabel() throws(MermaidDiagramReadError) -> DiagramLabel {
        let opening = cursor.position
        cursor.advance()
        cursor.skipSpaces()
        guard cursor.peek() == MermaidByte.quotationMark else { throw .invalidSyntax(line: cursor.line, problem: .expectedQuotedText) }
        let text = try readQuotedText()
        cursor.skipSpaces()
        guard cursor.peek() == MermaidByte.closingBracket else {
            throw .invalidSyntax(line: cursor.line(at: opening), problem: .unclosedShape(closingText: "]"))
        }
        cursor.advance()
        return DiagramLabelDecoder.label(from: cursor.text(text), form: .plain)
    }

    /// `{` members, one per line, `}`. A `{` inside is an error, as in Mermaid; a line that starts with `%%` is a comment.
    private mutating func readClassBody(ofClassAt index: Int, identifier: MermaidTextRange) throws(MermaidDiagramReadError) {
        let opening = cursor.position
        cursor.advance()
        while true {
            cursor.skipSpaces()
            if cursor.isAtCommentStart { cursor.skipToEndOfLine() }
            let start = cursor.position
            while let byte = cursor.peek(), byte != MermaidByte.newline, byte != MermaidByte.openingBrace, byte != MermaidByte.closingBrace {
                cursor.advance()
            }
            let member = cursor.trimmed(from: start, to: cursor.position)
            builder.addMember(at: member, toClassAt: index)
            guard let byte = cursor.peek() else {
                throw .invalidSyntax(line: cursor.line(at: opening), problem: .unclosedClassBody(identifier: cursor.text(identifier)))
            }
            if byte == MermaidByte.openingBrace { throw .invalidSyntax(line: cursor.line, problem: .unexpectedText(cursor.excerpt())) }
            cursor.advance()
            if byte == MermaidByte.closingBrace { return }
        }
    }

    /// `<<interface>> Name`.
    private mutating func readAnnotationStatement() throws(MermaidDiagramReadError) {
        let annotation = try readAnnotation()
        cursor.skipSpaces()
        guard let name = try ClassDiagramNameSyntax.read(&cursor) else { throw .invalidSyntax(line: cursor.line, problem: .expectedName) }
        builder.addAnnotation(annotation, toClassAt: try builder.classIndex(for: name))
    }

    /// `<<text>>` on one line: the text, trimmed.
    private mutating func readAnnotation() throws(MermaidDiagramReadError) -> String {
        let opening = cursor.position
        cursor.advance(by: 2)
        let start = cursor.position
        while !cursor.isAtEnd, !cursor.isAt(MermaidByte.greaterThan, MermaidByte.greaterThan), cursor.peek() != MermaidByte.newline { cursor.advance() }
        guard cursor.isAt(MermaidByte.greaterThan, MermaidByte.greaterThan) else {
            throw .invalidSyntax(line: cursor.line(at: opening), problem: .unclosedAnnotation)
        }
        let annotation = cursor.trimmed(from: start, to: cursor.position)
        cursor.advance(by: 2)
        guard !annotation.isEmpty else { throw .invalidSyntax(line: cursor.line(at: opening), problem: .unexpectedText("<<>>")) }
        return cursor.text(annotation)
    }

    // MARK: Members and relations

    /// A statement that starts with a class's name: `Name : member`, a relation, or the name alone, which Mermaid
    /// reads and adds nothing for.
    private mutating func readNameStatement() throws(MermaidDiagramReadError) {
        guard let name = try ClassDiagramNameSyntax.read(&cursor) else {
            throw .invalidSyntax(line: cursor.line, problem: .unexpectedText(cursor.excerpt()))
        }
        cursor.skipSpaces()
        if cursor.peek() == MermaidByte.colon, !cursor.isAt(MermaidByte.colon, MermaidByte.colon, MermaidByte.colon) {
            cursor.advance()
            cursor.skipSpaces()
            let member = cursor.readRestOfLineRange()
            builder.addMember(at: member, toClassAt: try builder.classIndex(for: name))
            return
        }
        if isAtStatementEnd { return }
        try readRelation(from: name)
    }

    /// `A "1" <|-- "*" B : label`, from the first cardinality on.
    private mutating func readRelation(from source: ClassDiagramName) throws(MermaidDiagramReadError) {
        let sourceCardinality = try readCardinality()
        cursor.skipSpaces()
        guard let relationOperator = ClassDiagramRelationSyntax.readOperator(&cursor) else {
            let problem: MermaidSyntaxProblem = sourceCardinality != nil || ClassDiagramRelationSyntax.startsOperator(cursor)
                ? .expectedRelationLine : .unexpectedText(cursor.excerpt())
            throw .invalidSyntax(line: cursor.line, problem: problem)
        }
        cursor.skipSpaces()
        let targetCardinality = try readCardinality()
        cursor.skipSpaces()
        guard let target = try ClassDiagramNameSyntax.read(&cursor) else { throw .invalidSyntax(line: cursor.line, problem: .expectedName) }
        cursor.skipSpaces()
        var label: DiagramLabel?
        if cursor.peek() == MermaidByte.colon {
            cursor.advance()
            cursor.skipSpaces()
            let text = cursor.readRestOfLine()
            label = text.isEmpty ? nil : DiagramLabelDecoder.label(from: text, form: .markdown)
        }
        try builder.addRelation(from: source, to: target, operator: relationOperator, cardinalities: (sourceCardinality, targetCardinality), label: label)
    }

    /// `"1"` at the cursor: its text trimmed with entity codes read, nil when it is empty or there is none.
    private mutating func readCardinality() throws(MermaidDiagramReadError) -> String? {
        guard cursor.peek() == MermaidByte.quotationMark else { return nil }
        let text = ClassDiagramMemberSyntax.trimmed(DiagramLabelDecoder.decodingEntities(cursor.text(try readQuotedText())))
        return text.isEmpty ? nil : text
    }

    // MARK: Notes, namespaces, direction, accessibility

    /// `note "text"` or `note for Name "text"`.
    private mutating func readNote() throws(MermaidDiagramReadError) {
        cursor.skipSpaces()
        var classIdentifier: MermaidTextRange?
        if cursor.hasPrefix("for"), let next = cursor.peek(3), MermaidByte.isSpace(next) {
            cursor.advance(by: 3)
            cursor.skipSpaces()
            guard let name = try ClassDiagramNameSyntax.read(&cursor) else { throw .invalidSyntax(line: cursor.line, problem: .expectedName) }
            classIdentifier = name.identifier
            cursor.skipSpaces()
        }
        guard cursor.peek() == MermaidByte.quotationMark else { throw .invalidSyntax(line: cursor.line, problem: .expectedQuotedText) }
        try builder.addNote(DiagramLabelDecoder.label(from: cursor.text(try readQuotedText()), form: .markdown), forClassIdentifiedBy: classIdentifier)
    }

    /// `namespace Name["Title"] { … }` with the classes, notes and namespaces inside it, read with the builder's
    /// stack of open namespaces rather than by recursion, so that deep nesting cannot exhaust the thread's stack.
    private mutating func readNamespace() throws(MermaidDiagramReadError) {
        try openNamespace()
        while let innermost = builder.innermostOpenNamespaceIdentifier {
            cursor.skipWhitespace()
            guard let byte = cursor.peek() else { throw .invalidSyntax(line: cursor.line, problem: .unclosedNamespace(identifier: innermost)) }
            if byte == MermaidByte.closingBrace {
                cursor.advance()
                builder.closeNamespace()
                continue
            }
            if cursor.isAtCommentStart {
                cursor.skipToEndOfLine()
                continue
            }
            let keyword = keywordAtCursor()
            cursor.advance(by: keyword?.1 ?? 0)
            switch keyword?.0 {
            case .classStatement: builder.addToInnermostNamespace(classAt: try readClassStatement())
            case .note: try readNote()
            case .namespace: try openNamespace()
            default: throw .invalidSyntax(line: cursor.line, problem: .unexpectedText(cursor.excerpt()))
            }
            cursor.skipSpaces()
            if cursor.peek() != MermaidByte.closingBrace { try expectStatementEnd() }
        }
    }

    /// `Name["Title"] {` after `namespace`.
    private mutating func openNamespace() throws(MermaidDiagramReadError) {
        cursor.skipSpaces()
        guard let name = try ClassDiagramNameSyntax.read(&cursor) else { throw .invalidSyntax(line: cursor.line, problem: .expectedName) }
        cursor.skipSpaces()
        let title = cursor.peek() == MermaidByte.openingBracket ? try readBracketedLabel() : nil
        cursor.skipSpaces()
        guard cursor.peek() == MermaidByte.openingBrace else { throw .invalidSyntax(line: cursor.line, problem: .unexpectedText(cursor.excerpt())) }
        cursor.advance()
        try builder.openNamespace(named: cursor.text(name.identifier), title: title)
    }

    /// `direction TB`, `BT`, `LR` or `RL`. Mermaid reads any other word after `direction` as part of a class's name
    /// that adds nothing, so the line is left without an error.
    private mutating func readDirection() {
        cursor.skipSpaces()
        let word = cursor.readWord()
        if let direction = Self.direction(spelledBy: word, in: cursor) { builder.setDirection(direction) }
        cursor.skipToEndOfLine()
    }

    /// `accTitle: text`, to the end of the line.
    private mutating func readAccessibilityLine() -> String {
        cursor.skipSpaces()
        if cursor.peek() == MermaidByte.colon { cursor.advance() }
        cursor.skipSpaces()
        return DiagramLabelDecoder.decodingEntities(cursor.readRestOfLine())
    }

    /// `accDescr: text` or `accDescr { lines }`, the lines joined by spaces.
    private mutating func readAccessibilityDescription() throws(MermaidDiagramReadError) -> String {
        cursor.skipSpaces()
        guard cursor.peek() == MermaidByte.openingBrace else { return readAccessibilityLine() }
        let opening = cursor.position
        cursor.advance()
        let start = cursor.position
        while let byte = cursor.peek(), byte != MermaidByte.closingBrace { cursor.advance() }
        guard !cursor.isAtEnd else { throw .invalidSyntax(line: cursor.line(at: opening), problem: .unclosedAccessibilityDescription) }
        let description = cursor.text(from: start, to: cursor.position)
        cursor.advance()
        return DiagramLabelDecoder.label(from: description, form: .plain).lines.filter { line in !line.isEmpty }.joined(separator: " ")
    }

    // MARK: Text and statement ends

    /// The bytes between quotation marks at the cursor, which may hold anything but a quotation mark; moves past them.
    private mutating func readQuotedText() throws(MermaidDiagramReadError) -> MermaidTextRange {
        let opening = cursor.position
        cursor.advance()
        let start = cursor.position
        while let byte = cursor.peek(), byte != MermaidByte.quotationMark { cursor.advance() }
        guard !cursor.isAtEnd else { throw .invalidSyntax(line: cursor.line(at: opening), problem: .unclosedQuotation) }
        let text = MermaidTextRange(start: start, end: cursor.position)
        cursor.advance()
        return text
    }

    /// Whether only spaces, then a line break, a comment or the end of the text, follow.
    private var isAtStatementEnd: Bool {
        var lookahead = cursor
        lookahead.skipSpaces()
        guard let byte = lookahead.peek() else { return true }
        return byte == MermaidByte.newline || byte == MermaidByte.carriageReturn || lookahead.isAtCommentStart
    }

    /// A statement ends at a line break, a comment or the end of the text; anything else is an error.
    private mutating func expectStatementEnd() throws(MermaidDiagramReadError) {
        guard isAtStatementEnd else {
            cursor.skipSpaces()
            throw .invalidSyntax(line: cursor.line, problem: .unexpectedText(cursor.excerpt()))
        }
        cursor.skipToEndOfLine()
    }

    /// The direction `TB`, `BT`, `LR` or `RL`, in upper case, spells, or nil.
    private static func direction(spelledBy word: MermaidTextRange, in bytes: GraphDiagramBytes) -> FlowchartDirection? {
        guard word.count == 2 else { return nil }
        switch (bytes.buffer[word.lowerBound], bytes.buffer[word.lowerBound + 1]) {
        case (UInt8(ascii: "T"), UInt8(ascii: "B")): return .topToBottom
        case (UInt8(ascii: "B"), UInt8(ascii: "T")): return .bottomToTop
        case (UInt8(ascii: "L"), UInt8(ascii: "R")): return .leftToRight
        case (UInt8(ascii: "R"), UInt8(ascii: "L")): return .rightToLeft
        default: return nil
        }
    }
}
