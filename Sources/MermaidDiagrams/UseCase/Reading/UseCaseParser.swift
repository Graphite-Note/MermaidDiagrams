/**
 * File: UseCaseParser.swift
 * -------------------------
 * Layer: Core
 * Description: Reads a use case diagram's tokens as Mermaid's Chevrotain parser does (Pele's parser.ts): the same
 *              choices from the same lookahead of at most three tokens, the same token named where the text breaks,
 *              then the drafts resolved into a diagram and its JSON read.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 23/11/2026
 */

/// Reads a use case diagram from its keyword on. Each statement is one line; a system boundary's lines run to its
/// `end`. The text must be well formed before the JSON in it is read, as in Mermaid. An error names the line it is on.
struct UseCaseParser {
    let text: UseCaseCharacters
    let tokens: UseCaseTokens
    /// The line of the whole text the keyword is on.
    let firstLine: Int
    let limits: MermaidDiagramLimits
    var index = 0
    var drafts = UseCaseDrafts()
    /// The boundary whose lines are being read, by its place among the drafts' boundaries.
    var parent: Int?
    /// Each JSON draft, by its place, and the token of its object.
    var pendingJSON: [(draft: Int, literal: Int)] = []

    /// PlantUML's statements that people are most likely to try, which Mermaid turns away.
    private static let forbiddenWords: Set<String> = ["allowmixing", "newpage", "package", "rectangle", "skinparam"]

    static func parse(keyword: String, endingAt cursor: MermaidTextCursor, limits: MermaidDiagramLimits) throws(MermaidDiagramReadError) -> UseCaseDiagram {
        let written = Array(cursor.text(from: cursor.position - keyword.utf8.count, to: cursor.bytes.count).utf16)
        let text = UseCaseSourcePreparation.prepared(written)
        let tokens: UseCaseTokens
        do {
            tokens = try UseCaseLexer.tokens(of: text)
        } catch {
            throw .invalidSyntax(line: cursor.line + text.line(of: error.offset) - 1, problem: .useCase(.unexpectedCharacter))
        }
        var parser = UseCaseParser(text: text, tokens: tokens, firstLine: cursor.line, limits: limits)
        try parser.readDiagram()
        try parser.readJSON()
        do {
            var diagram = try UseCaseDiagramBuilder.diagram(from: parser.drafts, limits: limits)
            let options = MermaidConfigurationOptions(section: "usecase", in: cursor)
            diagram.nodeSpacing = Self.spacing(options.values["nodeSpacing"])
            diagram.rankSpacing = Self.spacing(options.values["rankSpacing"])
            return diagram
        } catch {
            switch error {
            case .contradiction(let contradiction, let offset): throw parser.failure(at: offset, .contradiction(contradiction))
            case .tooManyNodes: throw .tooManyNodes(limit: limits.maximumNodeCount)
            }
        }
    }

    /// The largest spacing Pele takes from the options.
    static let largestSpacing = 2_000.0

    /// An option's number above zero, cut to the largest spacing; nil for none, or a value of another kind.
    private static func spacing(_ value: MermaidConfigurationOptions.Value?) -> Double? {
        guard case .number(let number) = value, number > 0 else { return nil }
        return min(number, largestSpacing)
    }

    var current: UseCaseTokenKind { tokens.kinds[index] }

    func kind(at position: Int) -> UseCaseTokenKind { tokens.kinds[min(position, tokens.kinds.count - 1)] }

    func image(_ token: Int) -> String { text.text(from: tokens.starts[token], to: tokens.ends[token]) }

    func failure(at offset: Int, _ problem: UseCaseSyntaxProblem) -> MermaidDiagramReadError {
        .invalidSyntax(line: firstLine + text.line(of: offset) - 1, problem: .useCase(problem))
    }

    /// The grammar's error at the current token.
    func unexpected(_ expected: UseCaseExpectedSyntax) -> MermaidDiagramReadError {
        failure(at: tokens.starts[index], .unexpectedToken(found: image(index), expected: expected))
    }

    mutating func expect(_ kind: UseCaseTokenKind) throws(MermaidDiagramReadError) -> Int {
        guard current == kind else { throw unexpected(.token(kind.mermaidName)) }
        index += 1
        return index - 1
    }

    mutating func lineEnd() throws(MermaidDiagramReadError) {
        if current == .newline {
            index += 1
        } else if current != .end {
            throw unexpected(.lineEnd)
        }
    }

    /// Past the limits before anything of their counts is made: each statement that makes a node, and each
    /// relationship and note connector.
    func checkCounts() throws(MermaidDiagramReadError) {
        if drafts.nodeStatementCount > limits.maximumNodeCount { throw .tooManyNodes(limit: limits.maximumNodeCount) }
        if drafts.relationships.count + drafts.notes.count > limits.maximumEdgeCount { throw .tooManyEdges(limit: limits.maximumEdgeCount) }
    }

    private mutating func readDiagram() throws(MermaidDiagramReadError) {
        _ = try expect(.useCase)
        try lineEnd()
        while current.isIn(.line) {
            try line(isTopLevel: true)
            try checkCounts()
        }
        guard current == .end else { throw unexpected(.end) }
    }

    mutating func line(isTopLevel: Bool) throws(MermaidDiagramReadError) {
        switch current {
        case .newline: index += 1
        case .comment:
            index += 1
            try lineEnd()
        default:
            if isTopLevel {
                try topStatement()
            } else if current == .actor {
                try actors(isTopLevel: false)
            } else {
                try entity(isTopLevel: false)
            }
        }
    }

    private mutating func topStatement() throws(MermaidDiagramReadError) {
        switch current {
        case .accessibilityTitleLine, .accessibilityDescriptionLine, .accessibilityDescriptionBlock: readAccessibility()
        case .direction:
            index += 1
            switch current {
            case .topDown, .topBottom: drafts.direction = .topToBottom
            case .bottomTop: drafts.direction = .bottomToTop
            case .leftRight: drafts.direction = .leftToRight
            case .rightLeft: drafts.direction = .rightToLeft
            default: throw unexpected(.direction)
            }
            index += 1
        case .actor: return try actors(isTopLevel: true)
        case .systemBoundary: return try boundary()
        case .note: try note()
        case .jsonDeclarationStart: try json()
        case .classDefinition:
            index += 1
            let identifiers = try identifierList()
            drafts.classDefinitions.append((identifiers.map(image), try styles()))
        case .classKeyword:
            index += 1
            let targets = try identifierList()
            let classes = try identifierList()
            drafts.classAssignments.append((targets.map { token in (image(token), tokens.starts[token]) }, classes.map(image)))
        case .style:
            index += 1
            let target = try expect(.identifier)
            drafts.styles.append((image(target), tokens.starts[target], try styles()))
        default: return try nameStatement()
        }
        try lineEnd()
    }

    /// `accTitle: …`, `accDescr: …` or `accDescr { … }`, its text trimmed.
    private mutating func readAccessibility() {
        let kind = current
        let written = image(index)
        index += 1
        let units = Array(written.utf16)
        if kind == .accessibilityDescriptionBlock {
            let open = (units.firstIndex(of: UInt16(ascii: "{")) ?? 0) + 1
            let close = max(open, units.lastIndex(of: UInt16(ascii: "}")) ?? units.count)
            drafts.accessibilityDescription = UseCaseCharacters.trimmed(String(decoding: units[open..<close], as: UTF16.self))
            return
        }
        let colon = (units.firstIndex(of: UInt16(ascii: ":")) ?? 0) + 1
        let value = UseCaseCharacters.trimmed(String(decoding: units[min(colon, units.count)...], as: UTF16.self))
        if kind == .accessibilityTitleLine { drafts.accessibilityTitle = value } else { drafts.accessibilityDescription = value }
    }

    /// `note for Target label`.
    private mutating func note() throws(MermaidDiagramReadError) {
        index += 1
        _ = try expect(.forKeyword)
        let target = try expect(.identifier)
        drafts.notes.append((image(target), tokens.starts[target], try label()))
    }

    /// `json Id@{ … }` and its classes; its object is read once the whole text is.
    private mutating func json() throws(MermaidDiagramReadError) {
        let declaration = index
        index += 1
        let literal = try expect(.jsonObjectLiteral)
        var classes: [String] = []
        if current == .classSeparator { try classSuffix(&classes) }
        var start = tokens.starts[declaration] + 4
        while UseCaseCharacters.isBlank(text[start]) { start += 1 }
        var end = start
        while UseCaseCharacters.isWord(text[end]) { end += 1 }
        drafts.jsons.append(UseCaseDraftJSON(identifier: text.text(from: start, to: end), start: start, value: .emptyObject, classes: classes))
        pendingJSON.append((drafts.jsons.count - 1, literal))
    }

    /// A statement that starts with a name: metadata for it (`Id@{ … }`), or a declaration or a relationship.
    private mutating func nameStatement() throws(MermaidDiagramReadError) {
        let first = index
        let kind = current
        let next = self.kind(at: index + 1)
        if next == .metadataStart {
            guard self.kind(at: index + 2).isIn(.metadataFirst) else { throw unexpected(.statement) }
            index += 1
            let content = contentRange(of: first)
            let target = kind == .identifier ? image(first) : Self.generatedIdentifier(text.text(from: content.lowerBound, to: content.upperBound))
            drafts.metadata.append((target, content.lowerBound, try metadata()))
            return try lineEnd()
        }
        let follows = next.isIn(.followsName) || (kind == .identifier && (next == .leftParenthesis || next == .leftBracket))
        if !follows || (kind == .identifier && Self.forbiddenWords.contains(image(first).lowercased())) { throw unexpected(.statement) }
        try entity(isTopLevel: true)
    }

    /// Each JSON draft's object read, once the whole text is well formed.
    private mutating func readJSON() throws(MermaidDiagramReadError) {
        for (draft, literal) in pendingJSON {
            let start = tokens.starts[literal]
            do {
                drafts.jsons[draft].value = try UseCaseJSONReader.read(text.units[start..<tokens.ends[literal]])
            } catch {
                throw jsonFailure(literalStart: start, offset: error.offset)
            }
            guard drafts.jsons[draft].value.root.kind == .object else { throw failure(at: start, .jsonRootNotObject) }
        }
    }

    /// Where JSON is not JSON, in the diagram's lines and columns: a line feed, a carriage return, or both together,
    /// end a line.
    private func jsonFailure(literalStart: Int, offset: Int) -> MermaidDiagramReadError {
        var column = text.column(of: literalStart)
        var lineBreaks = 0
        for position in literalStart..<min(literalStart + offset, text.count) {
            let unit = text.units[position]
            if unit == 0x0D || (unit == 0x0A && (position == literalStart || text.units[position - 1] != 0x0D)) {
                lineBreaks += 1
                column = 1
            } else if unit != 0x0A {
                column += 1
            }
        }
        return .invalidSyntax(line: firstLine + text.line(of: literalStart) - 1 + lineBreaks, problem: .useCase(.invalidJSON(column: column)))
    }

    /// An id made from a label: each character other than a letter, a digit and `_` made `_`, code unit by code unit.
    static func generatedIdentifier(_ label: String) -> String {
        String(decoding: label.utf16.map { unit in UseCaseCharacters.isWord(unit) ? unit : 0x5F }, as: UTF16.self)
    }
}
