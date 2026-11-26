/**
 * File: EntityRelationshipParser.swift
 * ------------------------------------
 * Layer: Core
 * Description: Reads an entity relationship diagram's statements after its keyword, on the text's borrowed bytes, its
 *              names byte ranges until the diagram keeps them.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.6
 * Date: 26/11/2026
 */

/// Reads an entity relationship diagram's statements after its `erDiagram` keyword, as Mermaid's grammar does:
/// entities, with an alias (`p[Person]`), classes (`:::name`) and attributes (`{ … }`); relationships
/// (`A ||--o{ B : label`); groups (`subgraph … end`); `direction`; accessibility text; and the statements that only
/// style the diagram, which are counted and left. A statement needs no separator before the next one.
struct EntityRelationshipParser {
    private var lexer: EntityRelationshipLexer
    private var builder: EntityRelationshipDiagramBuilder
    /// The token being looked at, and the position of its first byte.
    private var current: EntityRelationshipToken = .endOfText
    private var currentStart: Int

    /// Reads the diagram whose keyword ends at the cursor, on the cursor's bytes, borrowed.
    static func parse(_ cursor: MermaidTextCursor, limits: MermaidDiagramLimits) throws(MermaidDiagramReadError) -> EntityRelationshipDiagram {
        try cursor.bytes.withUnsafeBufferPointer { buffer throws(MermaidDiagramReadError) in
            let bytes = GraphDiagramBytes(buffer, position: cursor.position)
            return try EntityRelationshipReadingScratch.withLists(isASCII: bytes.isASCII) { lists throws(MermaidDiagramReadError) in
                var parser = EntityRelationshipParser(lexer: EntityRelationshipLexer(bytes: bytes),
                                                      builder: EntityRelationshipDiagramBuilder(limits: limits, bytes: bytes), currentStart: bytes.position)
                swap(&parser.builder.lists, &lists)
                defer { swap(&lists, &parser.builder.lists) }
                parser.builder.reserveNames()
                try parser.advance()
                try parser.readStatements()
                return parser.builder.finished(text: cursor.bytes)
            }
        }
    }

    private var bytes: GraphDiagramBytes { lexer.bytes }

    /// The line of the token being looked at, counted only for an error.
    private var currentLine: Int { lexer.bytes.line(at: currentStart) }

    private mutating func advance() throws(MermaidDiagramReadError) {
        (current, currentStart) = try lexer.readToken()
    }

    private mutating func readStatements() throws(MermaidDiagramReadError) {
        while true {
            switch current {
            case .endOfText:
                if let identifier = builder.innermostOpenSubgraphIdentifier {
                    throw .invalidSyntax(line: currentLine, problem: .unclosedSubgraph(identifier: identifier))
                }
                return
            case .lineBreak: try advance()
            case .name: try readEntityStatement()
            case .keyword(let keyword): try readKeywordStatement(keyword)
            case .accessibilityTitle(let title):
                builder.setAccessibilityTitle(title)
                try advance()
            case .accessibilityDescription(let description):
                builder.setAccessibilityDescription(description)
                try advance()
            case .direction(let direction):
                builder.setDirection(direction)
                try advance()
            case .quotedText, .cardinality, .identification, .openingBrace, .openingBracket, .closingBracket, .classSeparator, .colon, .comma,
                 .unexpectedCharacter:
                throw unexpectedToken()
            }
        }
    }

    private mutating func readKeywordStatement(_ keyword: EntityRelationshipKeyword) throws(MermaidDiagramReadError) {
        switch keyword {
        case .diagram: throw unexpectedToken()
        case .style, .classDefinition:
            // Styles take the rest of their line, and are not applied yet.
            lexer.bytes.skipToEndOfLine()
            builder.countUnappliedStatement()
            try advance()
        case .classAssignment:
            try advance()
            try readClassNames()
            try readClassNames()
            builder.countUnappliedStatement()
        case .subgraph: try readSubgraphOpening()
        case .end:
            guard builder.closeSubgraph() else { throw .invalidSyntax(line: currentLine, problem: .endWithoutSubgraph) }
            try advance()
        }
    }

    /// An entity, with an alias, classes and attributes, or the first entity of a relationship.
    private mutating func readEntityStatement() throws(MermaidDiagramReadError) {
        let name = try readName()
        if current == .openingBracket { return try readAliasedEntity(name) }
        try readClassShorthand()
        if case .cardinality(let firstCardinality) = current { return try readRelationship(from: name, firstCardinality: firstCardinality) }
        let firstAttribute = builder.attributeCount
        try readAttributeBlock(of: name)
        let index = try builder.entityIndex(for: name)
        builder.giveAttributes(from: firstAttribute, toEntityAt: index)
        builder.noteNameInOpenSubgraph(name.range)
    }

    /// `name[alias]`, then classes and attributes. As in Mermaid, no relationship follows an alias in one statement.
    private mutating func readAliasedEntity(_ name: EntityRelationshipName) throws(MermaidDiagramReadError) {
        let opening = currentStart
        try advance()
        guard case .name(let aliasRange, let aliasForm) = current else { throw unclosedAlias(opening: opening) }
        try advance()
        guard current == .closingBracket else { throw unclosedAlias(opening: opening) }
        try advance()
        try readClassShorthand()
        let firstAttribute = builder.attributeCount
        try readAttributeBlock(of: name)
        let index = try builder.entityIndex(for: name)
        builder.setAlias(EntityRelationshipName(range: aliasRange, form: aliasForm), ofEntityAt: index)
        builder.giveAttributes(from: firstAttribute, toEntityAt: index)
        builder.noteNameInOpenSubgraph(name.range)
    }

    /// The rest of `first ||--o{ second : label`, from its first cardinality.
    private mutating func readRelationship(from first: EntityRelationshipName,
                                           firstCardinality: EntityRelationshipCardinality) throws(MermaidDiagramReadError) {
        try advance()
        guard case .identification(let identification) = current else { throw problem(.expectedRelationshipLine) }
        try advance()
        guard case .cardinality(let secondCardinality) = current else { throw problem(.expectedCardinality) }
        try advance()
        guard case .name = current else { throw problem(.expectedNode) }
        let second = try readName()
        try readClassShorthand()
        guard current == .colon else { throw problem(.expectedRelationshipLabel) }
        try advance()
        let label = try readRelationshipLabel()
        let firstIndex = try builder.entityIndex(for: first)
        let secondIndex = try builder.entityIndex(for: second)
        try builder.addRelationship(EntityRelationshipRelationshipRecord(firstEntityIndex: Int32(firstIndex), secondEntityIndex: Int32(secondIndex),
                                                                         firstEntityCardinality: firstCardinality, secondEntityCardinality: secondCardinality,
                                                                         identification: identification, label: label))
        builder.noteNamesInOpenSubgraph(first.range, second.range)
    }

    /// A word, a quoted name or other quoted text, by its range, read as its form draws it; a number is no label in
    /// Mermaid's grammar.
    private mutating func readRelationshipLabel() throws(MermaidDiagramReadError) -> EntityRelationshipText {
        let label: EntityRelationshipText
        switch current {
        case .name(let range, let form) where form != .number: label = EntityRelationshipText(name: range, form: form)
        case .quotedText(let range): label = EntityRelationshipText(range: range, kind: .markdown)
        case .name, .cardinality, .identification, .keyword, .accessibilityTitle, .accessibilityDescription, .direction, .openingBrace,
             .openingBracket, .closingBracket, .classSeparator, .colon, .comma, .lineBreak, .endOfText, .unexpectedCharacter:
            throw problem(.expectedRelationshipLabel)
        }
        try advance()
        return label
    }

    /// The `{ … }` after an entity, its rows appended to the builder's attributes, or nothing when there is none.
    private mutating func readAttributeBlock(of name: EntityRelationshipName) throws(MermaidDiagramReadError) {
        guard current == .openingBrace else { return }
        try EntityRelationshipAttributeSyntax.readBlock(&lexer.bytes, entity: name.range, into: &builder.lists)
        try advance()
    }

    /// `subgraph name` or `subgraph name [title words]`, alone on its line.
    private mutating func readSubgraphOpening() throws(MermaidDiagramReadError) {
        try advance()
        guard case .name(let identifier, _) = current else { throw problem(.expectedNode) }
        try advance()
        // Pele's database keeps a group's title as Markdown, whether it is the identifier or the words in brackets.
        var title = DiagramLabelDecoder.label(from: bytes.text(identifier), form: .markdown)
        if current == .openingBracket {
            let opening = currentStart
            try advance()
            var words: [String] = []
            while case .name(let word, _) = current {
                words.append(bytes.text(word))
                try advance()
            }
            guard !words.isEmpty, current == .closingBracket else { throw unclosedAlias(opening: opening) }
            title = DiagramLabelDecoder.label(from: words.joined(separator: " "), form: .markdown)
            try advance()
        }
        guard current == .lineBreak || current == .endOfText else { throw unexpectedToken() }
        builder.openSubgraph(identifier: identifier, title: title)
    }

    /// `:::first,second` after an entity's name: classes, counted and not applied.
    private mutating func readClassShorthand() throws(MermaidDiagramReadError) {
        guard current == .classSeparator else { return }
        try advance()
        try readClassNames()
        builder.countUnappliedStatement()
    }

    /// Bare names joined by commas, as `class` and `:::` list entities and classes.
    private mutating func readClassNames() throws(MermaidDiagramReadError) {
        while true {
            guard case .name(_, .bare) = current else {
                throw current == .lineBreak || current == .endOfText ? problem(.expectedNode) : unexpectedToken()
            }
            try advance()
            guard current == .comma else { return }
            try advance()
        }
    }

    private mutating func readName() throws(MermaidDiagramReadError) -> EntityRelationshipName {
        guard case .name(let text, let form) = current else { throw unexpectedToken() }
        try advance()
        return EntityRelationshipName(range: text, form: form)
    }

    private func problem(_ problem: MermaidSyntaxProblem) -> MermaidDiagramReadError {
        .invalidSyntax(line: currentLine, problem: problem)
    }

    /// The token where none of its kind may stand, by its first characters.
    private func unexpectedToken() -> MermaidDiagramReadError {
        problem(.unexpectedText(bytes.excerpt(at: currentStart)))
    }

    /// An alias or a title whose `[` the text ends without closing, or closes after more than a name.
    private func unclosedAlias(opening: Int) -> MermaidDiagramReadError {
        switch current {
        case .lineBreak, .endOfText: .invalidSyntax(line: bytes.line(at: opening), problem: .unclosedShape(closingText: "]"))
        case .name, .quotedText, .cardinality, .identification, .keyword, .accessibilityTitle, .accessibilityDescription, .direction, .openingBrace,
             .openingBracket, .closingBracket, .classSeparator, .colon, .comma, .unexpectedCharacter:
            unexpectedToken()
        }
    }
}
