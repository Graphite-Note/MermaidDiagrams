/**
 * File: RequirementParser.swift
 * -----------------------------
 * Layer: Core
 * Description: Reads a requirement diagram's statements as Pele's parser reads them, over the lexer's tokens taken one
 *              at a time from the text's borrowed bytes: requirements, elements, relations, styles, classes, the
 *              direction and the accessibility text, each error at its line.
 *
 * Authors: Bahey Shalash
 * Version: 0.5
 * Date: 25/11/2026
 */

/// Reads a requirement diagram over `RequirementLexer`'s tokens, statement by statement as Pele's `parser.ts` reads them,
/// and hands them to `RequirementDiagramBuilder`. Where the grammar breaks, the error names the line of the token found
/// and what was expected there (`RequirementSyntaxProblem`), or the text no rule of the lexer reads. Names and texts stay
/// byte ranges of the text until the diagram keeps them.
struct RequirementParser {
    private var lexer: RequirementLexer
    private var token: RequirementToken
    var builder: RequirementDiagramBuilder
    private let prepared: RequirementPreparedSource
    /// The names and values of the statement being read, kept between statements so that their room is made once.
    private var names: [Range<Int>] = []
    private var values: [Range<Int>] = []
    private var declarationBytes: [UInt8] = []

    /// Reads the requirement diagram whose keyword, `keyword` as written, ends at the cursor. Any keyword that starts with
    /// `requirement` names a requirement diagram, as Pele detects one, and its lexer then reads the keyword itself, in the
    /// text as Pele hands it to its parser (`RequirementSourcePreparation`).
    static func parse(_ cursor: MermaidTextCursor, keyword: String, limits: MermaidDiagramLimits) throws(MermaidDiagramReadError) -> RequirementDiagram {
        let prepared = RequirementSourcePreparation.prepared(cursor.bytes, from: cursor.position - keyword.utf8.count)
        return try prepared.bytes.withUnsafeBufferPointer { bytes throws(MermaidDiagramReadError) in
            var parser = RequirementParser(prepared: prepared, bytes: bytes, limits: limits)
            guard parser.kind == .diagramKeyword else { throw parser.failure(.expectedKeyword) }
            parser.advance()
            try parser.expect(.lineBreak, else: .expectedLineBreak)
            try parser.readStatements()
            return parser.builder.diagram
        }
    }

    private init(prepared: RequirementPreparedSource, bytes: UnsafeBufferPointer<UInt8>, limits: MermaidDiagramLimits) {
        self.prepared = prepared
        lexer = RequirementLexer(bytes: bytes, start: prepared.start)
        token = lexer.next()
        builder = RequirementDiagramBuilder(limits: limits, bytes: bytes, isASCII: GraphDiagramNameTable.isASCII(bytes))
    }

    var kind: RequirementTokenKind { token.kind }

    var bytes: UnsafeBufferPointer<UInt8> { lexer.bytes }

    mutating func advance() {
        token = lexer.next()
    }

    private mutating func readStatements() throws(MermaidDiagramReadError) {
        while true {
            switch kind {
            case .endOfText: return
            case .lineBreak: advance()
            case .accessibilityTitle, .accessibilityDescription, .accessibilityDescriptionBlockValue: try readAccessibilityStatement()
            case .direction(let direction):
                advance()
                builder.setDirection(direction)
            case .requirementKind(let requirementKind):
                advance()
                try readNode(requirementKind)
            case .element:
                advance()
                try readNode(nil)
            case .style, .classDefinition, .classAssignment: try readStyleStatement()
            case .unquotedText, .quotedText: try readNameStatement()
            default: throw failure(.expectedStatement)
            }
        }
    }

    private mutating func readAccessibilityStatement() throws(MermaidDiagramReadError) {
        switch kind {
        case .accessibilityTitle:
            advance()
            builder.setAccessibilityTitle(trimmedText(try expect(.accessibilityTitleValue, else: .expectedStatement)))
        case .accessibilityDescription:
            advance()
            builder.setAccessibilityDescription(trimmedText(try expect(.accessibilityDescriptionValue, else: .expectedStatement)))
        default:
            builder.setAccessibilityDescription(trimmedText(token.textRange))
            advance()
        }
    }

    /// A requirement of `requirementKind`, or an element when it is nil: its name, its classes, its body.
    private mutating func readNode(_ requirementKind: RequirementKind?) throws(MermaidDiagramReadError) {
        let name = try readName()
        let hasClasses = try readClassesBeforeBody()
        let fields = try readBody(ofRequirement: requirementKind != nil)
        // The statement's last token, the body's closing brace, is on the line its refusal names.
        let statementStart = lastTokenStart
        do {
            if let requirementKind { try builder.addRequirement(named: name, kind: requirementKind, fields: fields) } else {
                try builder.addElement(named: name, fields: fields)
            }
            if hasClasses { try builder.setClasses(names: [name], classNames: values) }
        } catch {
            throw refused(error, at: statementStart)
        }
    }

    /// `:::` and classes then `{`, or `{` alone, then a line break; the classes are left in `values`.
    private mutating func readClassesBeforeBody() throws(MermaidDiagramReadError) -> Bool {
        var hasClasses = false
        if kind == .styleSeparator {
            advance()
            try readNameList(into: .values)
            hasClasses = true
        }
        try expect(.openingBrace, else: .expectedOpeningBrace)
        try expect(.lineBreak, else: .expectedLineBreak)
        return hasClasses
    }

    /// A body to its closing brace. The grammar is right recursive, so Mermaid applies the fields last to first, and the
    /// first of two repeated fields wins.
    private mutating func readBody(ofRequirement isRequirement: Bool) throws(MermaidDiagramReadError) -> RequirementBodyFields {
        var fields = RequirementBodyFields()
        while true {
            if kind == .closingBrace {
                lastTokenStart = token.start
                advance()
                return fields
            }
            if kind == .lineBreak {
                advance()
                continue
            }
            guard case .field(let field) = kind, field.isRequirementField == isRequirement else {
                throw failure(isRequirement ? .expectedRequirementField : .expectedElementField)
            }
            advance()
            try expect(.fieldSeparator, else: .expectedColon)
            try readFieldValue(of: field, into: &fields)
            try expect(.lineBreak, else: .expectedLineBreak)
        }
    }

    private mutating func readFieldValue(of field: RequirementFieldName, into fields: inout RequirementBodyFields) throws(MermaidDiagramReadError) {
        switch (field, kind) {
        case (.risk, .risk(let risk)):
            advance()
            if fields.risk == nil { fields.risk = risk }
        case (.risk, _): throw failure(.expectedRisk)
        case (.verificationMethod, .verificationMethod(let method)):
            advance()
            if fields.verificationMethod == nil { fields.verificationMethod = method }
        case (.verificationMethod, _): throw failure(.expectedVerificationMethod)
        case (.identifier, _): Self.keepFirst(try readName(), in: &fields.identifier)
        case (.text, _): Self.keepFirst(try readName(), in: &fields.text)
        case (.type, _): Self.keepFirst(try readName(), in: &fields.type)
        case (.documentReference, _): Self.keepFirst(try readName(), in: &fields.documentReference)
        }
    }

    /// Keeps a field's value read unless one was read before it in the body.
    private static func keepFirst(_ value: Range<Int>, in field: inout Range<Int>?) {
        if field == nil { field = value }
    }

    /// `style`, `classDef` or `class`, the names, then the declarations or the classes.
    private mutating func readStyleStatement() throws(MermaidDiagramReadError) {
        let statement = kind
        let statementStart = token.start
        advance()
        try readNameList(into: .names)
        if statement == .classAssignment {
            try readNameList(into: .values)
            do { try builder.setClasses(names: names, classNames: values) } catch { throw refused(error, at: statementStart) }
            return
        }
        let declarations = try readDeclarations()
        do {
            if statement == .style { try builder.setStyle(names: names, declarations: declarations) } else {
                try builder.defineClasses(names: names, declarations: declarations)
            }
        } catch {
            throw refused(error, at: statementStart)
        }
    }

    /// A name at a statement's start: `:::` and classes, or a relation, `- kind ->` or `<- kind -`, and its other end.
    private mutating func readNameStatement() throws(MermaidDiagramReadError) {
        let name = token.textRange
        let statementStart = token.start
        advance()
        let next = kind
        switch next {
        case .styleSeparator:
            advance()
            try readNameList(into: .values)
            do { try builder.setClasses(names: [name], classNames: values) } catch { throw refused(error, at: statementStart) }
        case .leftArrowEnd, .line:
            advance()
            guard case .relation(let relation) = kind else { throw failure(.expectedRelationKind) }
            advance()
            try expect(next == .line ? .rightArrowEnd : .line, else: .expectedArrow)
            let other = try readName()
            do {
                if next == .line { try builder.addRelation(relation, from: name, to: other) } else { try builder.addRelation(relation, from: other, to: name) }
            } catch {
                throw refused(error, at: statementStart)
            }
        default: throw failure(.expectedNameStatement)
        }
    }

    /// Where the last token a statement ends with starts: the line a refusal of a node names.
    private var lastTokenStart = 0
}

extension RequirementParser {
    /// A name, unquoted or quoted.
    private mutating func readName() throws(MermaidDiagramReadError) -> Range<Int> {
        guard kind == .unquotedText || kind == .quotedText else { throw failure(.expectedName) }
        defer { advance() }
        return token.textRange
    }

    /// Which of the statement's lists a list of names is read into.
    private enum NameList {
        case names, values
    }

    /// Names separated by commas: words of a style statement, unquoted or quoted text. The list is taken out while it is
    /// read, so that it is changed in place.
    private mutating func readNameList(into which: NameList) throws(MermaidDiagramReadError) {
        var list: [Range<Int>] = []
        switch which {
        case .names: swap(&list, &names)
        case .values: swap(&list, &values)
        }
        list.removeAll(keepingCapacity: true)
        while true {
            guard kind == .styleWord || kind == .unquotedText || kind == .quotedText else { throw failure(.expectedNameList) }
            list.append(token.textRange)
            advance()
            guard kind == .comma else { break }
            advance()
        }
        switch which {
        case .names: swap(&list, &names)
        case .values: swap(&list, &values)
        }
    }

    /// Declarations separated by commas, each the parts of a style statement run together.
    private mutating func readDeclarations() throws(MermaidDiagramReadError) -> [String] {
        var declarations: [String] = []
        while true {
            guard kind.isStylePart else { throw failure(.expectedStyle) }
            declarationBytes.removeAll(keepingCapacity: true)
            while kind.isStylePart {
                declarationBytes.append(contentsOf: UnsafeBufferPointer(rebasing: bytes[token.textRange]))
                advance()
            }
            declarations.append(String(decoding: declarationBytes, as: UTF8.self))
            guard kind == .comma else { return declarations }
            advance()
        }
    }

    /// The token's text range when it is of `expected`; otherwise the syntax error `problem`.
    @discardableResult
    private mutating func expect(_ expected: RequirementTokenKind, else problem: RequirementSyntaxProblem) throws(MermaidDiagramReadError) -> Range<Int> {
        guard kind == expected else { throw failure(problem) }
        defer { advance() }
        return token.textRange
    }

    /// The text of `range` without JavaScript's whitespace at its ends, as `trim` leaves it.
    private func trimmedText(_ range: Range<Int>) -> String {
        builder.string(RequirementLexer.trimmed(bytes, range))
    }

    /// The 1-based line of the text at `position`, counted only for an error.
    private func line(at position: Int) -> Int {
        1 + prepared.removedLineBreakCount(before: position) + MermaidSourceText.line(at: min(position, bytes.count), in: bytes) - 1
    }

    /// The error at the current token: the text no rule reads where the lexer stopped, else `problem`.
    func failure(_ problem: RequirementSyntaxProblem) -> MermaidDiagramReadError {
        guard kind == .unreadable else { return .invalidSyntax(line: line(at: token.start), problem: .requirement(problem)) }
        return .invalidSyntax(line: line(at: token.start), problem: .unexpectedText(MermaidSourceText.excerpt(at: token.start, in: bytes)))
    }

    /// The error of a statement the builder refused, at the line of the text at `position`.
    private func refused(_ refusal: RequirementDiagramBuilder.Refusal, at position: Int) -> MermaidDiagramReadError {
        switch refusal {
        case .tooManyNodes: .tooManyNodes(limit: builder.limits.maximumNodeCount)
        case .tooManyEdges: .tooManyEdges(limit: builder.limits.maximumEdgeCount)
        case .tooManyStyleCopies:
            .invalidSyntax(line: line(at: position), problem: .requirement(.tooManyStyleCopies(limit: RequirementDiagramBuilder.maximumStyleCopyCount)))
        }
    }
}
