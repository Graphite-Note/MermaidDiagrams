/**
 * File: ReferenceRequirementParser.swift
 * --------------------------------------
 * Layer: Tests
 * Description: 0.7.0's RequirementParser, kept unchanged but for its names as the reference the requirement reader on
 *              bytes is compared with (RequirementReadingEquivalenceTests).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

@testable import MermaidDiagrams

/// Reads a requirement diagram over `ReferenceRequirementLexer`'s tokens, statement by statement as Pele's `parser.ts` reads them,
/// and hands them to `ReferenceRequirementDiagramBuilder`. Where the grammar breaks, the error names the line of the token found
/// and what was expected there (`RequirementSyntaxProblem`), or the text no rule of the lexer reads.
struct ReferenceRequirementParser {
    private let bytes: [UInt8]
    private let tokens: [ReferenceRequirementToken]
    private var index = 0
    private var builder: ReferenceRequirementDiagramBuilder
    private let limits: MermaidDiagramLimits
    private let prepared: ReferenceRequirementPreparedSource

    /// A field's value as written: text, or one of the words of `risk` and `verifymethod`.
    private enum FieldValue {
        case text(String), risk(RequirementRisk), verificationMethod(RequirementVerificationMethod)
    }

    /// Reads the requirement diagram whose keyword, `keyword` as written, ends at the cursor. Any keyword that starts with
    /// `requirement` names a requirement diagram, as Pele detects one, and its lexer then reads the keyword itself, in the
    /// text as Pele hands it to its parser (`ReferenceRequirementSourcePreparation`).
    static func parse(_ cursor: MermaidTextCursor, keyword: String, limits: MermaidDiagramLimits) throws(MermaidDiagramReadError) -> RequirementDiagram {
        let prepared = ReferenceRequirementSourcePreparation.prepared(cursor.bytes, from: cursor.position - keyword.utf8.count)
        var parser = ReferenceRequirementParser(bytes: prepared.bytes, tokens: ReferenceRequirementLexer.tokens(of: prepared.bytes, from: prepared.start),
                                       builder: ReferenceRequirementDiagramBuilder(limits: limits), limits: limits, prepared: prepared)
        guard parser.kind == .diagramKeyword else { throw parser.failure(.expectedKeyword) }
        parser.index += 1
        try parser.expect(.lineBreak, else: .expectedLineBreak)
        try parser.readStatements()
        return parser.builder.diagram
    }

    private init(bytes: [UInt8], tokens: [ReferenceRequirementToken], builder: ReferenceRequirementDiagramBuilder, limits: MermaidDiagramLimits,
                 prepared: ReferenceRequirementPreparedSource) {
        self.bytes = bytes
        self.prepared = prepared
        self.tokens = tokens
        self.builder = builder
        self.limits = limits
    }

    private var kind: ReferenceRequirementTokenKind { tokens[min(index, tokens.count - 1)].kind }

    private var text: String {
        String(decoding: bytes[tokens[min(index, tokens.count - 1)].textRange], as: UTF8.self)
    }

    private mutating func readStatements() throws(MermaidDiagramReadError) {
        while true {
            switch kind {
            case .endOfText: return
            case .lineBreak: index += 1
            case .accessibilityTitle, .accessibilityDescription, .accessibilityDescriptionBlockValue: try readAccessibilityStatement()
            case .direction(let direction):
                index += 1
                builder.setDirection(direction)
            case .requirementKind(let requirementKind):
                index += 1
                try readNode(requirementKind)
            case .element:
                index += 1
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
            index += 1
            builder.setAccessibilityTitle(Self.trimmed(try expect(.accessibilityTitleValue, else: .expectedStatement)))
        case .accessibilityDescription:
            index += 1
            builder.setAccessibilityDescription(Self.trimmed(try expect(.accessibilityDescriptionValue, else: .expectedStatement)))
        default:
            builder.setAccessibilityDescription(Self.trimmed(text))
            index += 1
        }
    }

    /// A requirement of `requirementKind`, or an element when it is nil: its name, its classes, its body.
    private mutating func readNode(_ requirementKind: RequirementKind?) throws(MermaidDiagramReadError) {
        let name = try readName()
        let classNames = try readClassesBeforeBody()
        try readBody(ofRequirement: requirementKind != nil)
        let statementIndex = index - 1
        do {
            if let requirementKind { try builder.addRequirement(named: name, kind: requirementKind) } else { try builder.addElement(named: name) }
            if let classNames { try builder.setClasses(names: [name], classNames: classNames) }
        } catch {
            throw refused(error, at: statementIndex)
        }
    }

    /// `:::` and classes then `{`, or `{` alone, then a line break.
    private mutating func readClassesBeforeBody() throws(MermaidDiagramReadError) -> [String]? {
        var classNames: [String]?
        if kind == .styleSeparator {
            index += 1
            classNames = try readNameList()
            try expect(.openingBrace, else: .expectedOpeningBrace)
        } else {
            try expect(.openingBrace, else: .expectedOpeningBrace)
        }
        try expect(.lineBreak, else: .expectedLineBreak)
        return classNames
    }

    /// A body to its closing brace. The grammar is right recursive, so Mermaid applies the fields last to first, and the
    /// first of two repeated fields wins.
    private mutating func readBody(ofRequirement isRequirement: Bool) throws(MermaidDiagramReadError) {
        var fields: [(ReferenceRequirementFieldName, FieldValue)] = []
        while true {
            if kind == .closingBrace {
                index += 1
                break
            }
            if kind == .lineBreak {
                index += 1
                continue
            }
            guard case .field(let field) = kind, field.isRequirementField == isRequirement else {
                throw failure(isRequirement ? .expectedRequirementField : .expectedElementField)
            }
            index += 1
            try expect(.fieldSeparator, else: .expectedColon)
            fields.append((field, try readFieldValue(of: field)))
            try expect(.lineBreak, else: .expectedLineBreak)
        }
        for (field, value) in fields.reversed() {
            switch value {
            case .text(let text): builder.setPendingField(field, text: text)
            case .risk(let risk): builder.setPendingRisk(risk)
            case .verificationMethod(let method): builder.setPendingVerificationMethod(method)
            }
        }
    }

    private mutating func readFieldValue(of field: ReferenceRequirementFieldName) throws(MermaidDiagramReadError) -> FieldValue {
        switch (field, kind) {
        case (.risk, .risk(let risk)):
            index += 1
            return .risk(risk)
        case (.risk, _): throw failure(.expectedRisk)
        case (.verificationMethod, .verificationMethod(let method)):
            index += 1
            return .verificationMethod(method)
        case (.verificationMethod, _): throw failure(.expectedVerificationMethod)
        default: return .text(try readName())
        }
    }

    /// `style`, `classDef` or `class`, the names, then the declarations or the classes.
    private mutating func readStyleStatement() throws(MermaidDiagramReadError) {
        let statement = kind
        let statementIndex = index
        index += 1
        let names = try readNameList()
        let values = statement == .classAssignment ? try readNameList() : try readDeclarations()
        do {
            switch statement {
            case .style: try builder.setStyle(names: names, declarations: values)
            case .classDefinition: try builder.defineClasses(names: names, declarations: values)
            default: try builder.setClasses(names: names, classNames: values)
            }
        } catch {
            throw refused(error, at: statementIndex)
        }
    }

    /// A name at a statement's start: `:::` and classes, or a relation, `- kind ->` or `<- kind -`, and its other end.
    private mutating func readNameStatement() throws(MermaidDiagramReadError) {
        let name = text
        let statementIndex = index
        index += 1
        let next = kind
        switch next {
        case .styleSeparator:
            index += 1
            let classNames = try readNameList()
            do { try builder.setClasses(names: [name], classNames: classNames) } catch { throw refused(error, at: statementIndex) }
        case .leftArrowEnd, .line:
            index += 1
            guard case .relation(let relation) = kind else { throw failure(.expectedRelationKind) }
            index += 1
            try expect(next == .line ? .rightArrowEnd : .line, else: .expectedArrow)
            let other = try readName()
            do {
                if next == .line { try builder.addRelation(relation, from: name, to: other) } else { try builder.addRelation(relation, from: other, to: name) }
            } catch {
                throw refused(error, at: statementIndex)
            }
        default: throw failure(.expectedNameStatement)
        }
    }
}

extension ReferenceRequirementParser {
    /// A name, unquoted or quoted.
    private mutating func readName() throws(MermaidDiagramReadError) -> String {
        guard kind == .unquotedText || kind == .quotedText else { throw failure(.expectedName) }
        defer { index += 1 }
        return text
    }

    /// Names separated by commas: words of a style statement, unquoted or quoted text.
    private mutating func readNameList() throws(MermaidDiagramReadError) -> [String] {
        var names: [String] = []
        while true {
            guard kind == .styleWord || kind == .unquotedText || kind == .quotedText else { throw failure(.expectedNameList) }
            names.append(text)
            index += 1
            guard kind == .comma else { return names }
            index += 1
        }
    }

    /// Declarations separated by commas, each the parts of a style statement run together.
    private mutating func readDeclarations() throws(MermaidDiagramReadError) -> [String] {
        var declarations: [String] = []
        while true {
            guard kind.isStylePart else { throw failure(.expectedStyle) }
            let start = index
            while kind.isStylePart { index += 1 }
            declarations.append(tokens[start..<index].map { token in String(decoding: bytes[token.textRange], as: UTF8.self) }.joined())
            guard kind == .comma else { return declarations }
            index += 1
        }
    }

    /// The token's text when it is of `expected`; otherwise the syntax error `problem`.
    @discardableResult
    private mutating func expect(_ expected: ReferenceRequirementTokenKind, else problem: RequirementSyntaxProblem) throws(MermaidDiagramReadError) -> String {
        guard kind == expected else { throw failure(problem) }
        defer { index += 1 }
        return text
    }

    /// The 1-based line of the current token.
    private var currentLine: Int { line(ofToken: index) }

    /// The 1-based line of a token, counted only for an error.
    private func line(ofToken tokenIndex: Int) -> Int {
        let position = tokens[min(tokenIndex, tokens.count - 1)].start
        return 1 + prepared.removedLineBreakCount(before: position)
            + bytes[..<min(position, bytes.count)].reduce(0) { count, byte in byte == MermaidByte.newline ? count + 1 : count }
    }

    /// The error at the current token: the text no rule reads where the lexer stopped, else `problem`.
    private func failure(_ problem: RequirementSyntaxProblem) -> MermaidDiagramReadError {
        guard kind == .unreadable else { return .invalidSyntax(line: currentLine, problem: .requirement(problem)) }
        var cursor = MermaidTextCursor(bytes: bytes)
        cursor.advance(by: tokens[min(index, tokens.count - 1)].start)
        return .invalidSyntax(line: currentLine, problem: .unexpectedText(cursor.excerpt()))
    }

    /// The error of a statement the builder refused, at the line of the statement's first token.
    private func refused(_ refusal: ReferenceRequirementDiagramBuilder.Refusal, at tokenIndex: Int) -> MermaidDiagramReadError {
        switch refusal {
        case .tooManyNodes: .tooManyNodes(limit: limits.maximumNodeCount)
        case .tooManyEdges: .tooManyEdges(limit: limits.maximumEdgeCount)
        case .tooManyStyleCopies:
            .invalidSyntax(line: line(ofToken: tokenIndex),
                           problem: .requirement(.tooManyStyleCopies(limit: ReferenceRequirementDiagramBuilder.maximumStyleCopyCount)))
        }
    }

    /// The text without JavaScript's whitespace at its ends, as `trim` leaves it.
    static func trimmed(_ text: String) -> String {
        String(decoding: JavaScriptWhitespace.trimmed(Array(text.utf8)[...]), as: UTF8.self)
    }
}
