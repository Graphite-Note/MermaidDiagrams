/**
 * File: UseCaseParser.swift
 * -------------------------
 * Layer: Core
 * Description: Reads a use case diagram's tokens as Mermaid's Chevrotain parser does (Pele's parser.ts): the same
 *              choices from the same lookahead of at most three tokens, the same token named where the text breaks,
 *              its names interned as they are met, then the drafts resolved into a diagram and its JSON read.
 *
 * Authors: Bahey Shalash
 * Version: 0.6
 * Date: 25/11/2026
 */

/// Reads a use case diagram from its keyword on. Each statement is one line; a system boundary's lines run to its
/// `end`. The text must be well formed before the JSON in it is read, as in Mermaid. An error names the line it is on.
struct UseCaseParser {
    var text: UseCaseBytes
    let tokens: UseCaseTokens
    /// The line of the whole text the keyword is on.
    let firstLine: Int
    let limits: MermaidDiagramLimits
    var index = 0
    var drafts = UseCaseDrafts()
    /// The boundary whose lines are being read, by its place among the drafts' boundaries, or -1.
    var parent: Int32 = -1
    /// Each JSON draft, by its place, and the token of its object.
    var pendingJSON: [(draft: Int, literal: Int)] = []
    /// Every name met (ids, classes, relationships' ids), numbered in the order first met. A name is made of ASCII's
    /// word characters alone, an id made from a label too, so that two names are one exactly when their bytes are.
    var nameTable = GraphDiagramNameTable(isASCII: true)
    /// Where each name's bytes are, by its number.
    var nameRanges: [MermaidTextRange] = []
    /// The labels `include` and `extend`, which the reading writes once each when a relationship asks for them.
    var semanticLabels: [MermaidTextRange?] = [nil, nil]

    /// PlantUML's statements that people are most likely to try, which Mermaid turns away, in any case.
    private static let forbiddenWords: [StaticString] = ["allowmixing", "newpage", "package", "rectangle", "skinparam"]

    /// Whether the identifier at `token` is one of `forbiddenWords` in any case. An identifier is ASCII's word
    /// characters only, so its length made lowercase is its length, and only a length of theirs (7, 9, 11) is looked up.
    private func isForbiddenWord(_ token: Int) -> Bool {
        let length = tokens.ends[token] - tokens.starts[token]
        guard length == 7 || length == 9 || length == 11 else { return false }
        return Self.forbiddenWords.contains { word in text.spellsIgnoringCase(range(of: token), word) }
    }

    static func parse(keyword: String, endingAt cursor: MermaidTextCursor, limits: MermaidDiagramLimits) throws(MermaidDiagramReadError) -> UseCaseDiagram {
        let text = UseCaseSourcePreparation.prepared(cursor.bytes[(cursor.position - keyword.utf8.count)...])
        let tokens: UseCaseTokens
        do {
            tokens = try UseCaseLexer.tokens(of: text)
        } catch {
            throw .invalidSyntax(line: cursor.line + text.line(of: error.offset) - 1, problem: .useCase(.unexpectedCharacter))
        }
        var parser = UseCaseParser(text: text, tokens: tokens, firstLine: cursor.line, limits: limits)
        parser.nameTable.reserveCapacity(tokens.kinds.count / 4 + 4)
        parser.nameRanges.reserveCapacity(tokens.kinds.count / 4 + 4)
        // A statement takes about six tokens in the documentation's examples, with a line break.
        let statementEstimate = tokens.kinds.count / 6 + 2
        parser.drafts.elements.reserveCapacity(statementEstimate)
        parser.drafts.relationships.reserveCapacity(statementEstimate)
        try parser.readDiagram()
        try parser.readJSON()
        var builder = UseCaseDiagramBuilder(drafts: parser.drafts, text: parser.text, nameRanges: parser.nameRanges)
        do {
            try builder.build(limits: limits)
        } catch {
            switch error {
            case .contradiction(let contradiction, let offset): throw parser.failure(at: offset, .contradiction(contradiction))
            case .tooManyNodes: throw .tooManyNodes(limit: limits.maximumNodeCount)
            }
        }
        var diagram = builder.diagram
        let options = MermaidConfigurationOptions(section: "usecase", in: cursor)
        diagram.nodeSpacing = Self.spacing(options.values["nodeSpacing"])
        diagram.rankSpacing = Self.spacing(options.values["rankSpacing"])
        return diagram
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

    func range(of token: Int) -> MermaidTextRange { MermaidTextRange(start: tokens.starts[token], end: tokens.ends[token]) }

    func image(_ token: Int) -> String { text.string(range(of: token)) }

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

    /// The number of the name `range` of the text spells.
    mutating func intern(_ range: MermaidTextRange) -> Int32 {
        let bytes = text.bytes
        let (number, isNew) = bytes.withUnsafeBufferPointer { buffer in nameTable.intern(buffer, range) }
        if isNew { nameRanges.append(range) }
        return Int32(number)
    }

    /// The number of the identifier at `token`.
    mutating func name(of token: Int) -> Int32 { intern(range(of: token)) }

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
            let names = try identifierList().map { token in name(of: token) }
            let styles = try styles()
            drafts.classDefinitions.append(UseCaseDraftClassDefinition(names: drafts.addNames(names), styles: styles))
        case .classKeyword:
            index += 1
            let targets = try identifierList().map { token in UseCaseDraftTarget(name: name(of: token), start: Int32(tokens.starts[token])) }
            let classes = try identifierList().map { token in name(of: token) }
            let targetStart = drafts.targets.count
            drafts.targets.append(contentsOf: targets)
            drafts.classAssignments.append(UseCaseDraftClassAssignment(targets: UseCaseListSpan(start: Int32(targetStart), count: Int32(targets.count)),
                                                                       classes: drafts.addNames(classes)))
        case .style:
            index += 1
            let target = try expect(.identifier)
            let name = name(of: target)
            drafts.styles.append(UseCaseDraftStyle(target: name, start: Int32(tokens.starts[target]), styles: try styles()))
        default: return try nameStatement()
        }
        try lineEnd()
    }

    /// `accTitle: …`, `accDescr: …` or `accDescr { … }`, its text trimmed.
    private mutating func readAccessibility() {
        let kind = current
        let written = range(of: index)
        index += 1
        let bytes = text.bytes
        let value = bytes.withUnsafeBufferPointer { buffer -> MermaidTextRange in
            func first(_ byte: UInt8) -> Int? { (written.lowerBound..<written.upperBound).first { position in buffer[position] == byte } }
            if kind == .accessibilityDescriptionBlock {
                let open = (first(UInt8(ascii: "{")) ?? written.lowerBound) + 1
                let lastClose = (written.lowerBound..<written.upperBound).last { position in buffer[position] == UInt8(ascii: "}") }
                let close = max(open, lastClose ?? written.upperBound)
                return UseCaseCharacters.trimmed(MermaidTextRange(start: open, end: close), in: buffer)
            }
            let colon = min((first(UInt8(ascii: ":")) ?? written.lowerBound) + 1, written.upperBound)
            return UseCaseCharacters.trimmed(MermaidTextRange(start: colon, end: written.upperBound), in: buffer)
        }
        let string = text.string(value)
        switch kind {
        case .accessibilityTitleLine: drafts.accessibilityTitle = string
        default: drafts.accessibilityDescription = string
        }
    }

    /// `note for Target label`.
    private mutating func note() throws(MermaidDiagramReadError) {
        index += 1
        _ = try expect(.forKeyword)
        let target = try expect(.identifier)
        let name = name(of: target)
        drafts.notes.append(UseCaseDraftNote(target: name, start: Int32(tokens.starts[target]), label: try label()))
    }

    /// `json Id@{ … }` and its classes; its object is read once the whole text is.
    private mutating func json() throws(MermaidDiagramReadError) {
        let declaration = index
        index += 1
        let literal = try expect(.jsonObjectLiteral)
        let classes = current == .classSeparator ? try classSuffix() : .empty
        var start = tokens.starts[declaration] + 4
        while UseCaseCharacters.isBlank(text[start]) { start += 1 }
        var end = start
        while UseCaseCharacters.isWord(text[end]) { end += 1 }
        let name = intern(MermaidTextRange(start: start, end: end))
        drafts.jsons.append(UseCaseDraftJSON(name: name, start: Int32(start), value: Int32(drafts.jsonValues.count), classes: classes))
        drafts.jsonValues.append(.emptyObject)
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
            let target = kind == .identifier ? name(of: first) : generatedName(content)
            let properties = try metadata()
            drafts.metadata.append(UseCaseDraftMetadata(target: target, start: Int32(content.lowerBound), properties: properties))
            return try lineEnd()
        }
        let follows = next.isIn(.followsName) || (kind == .identifier && (next == .leftParenthesis || next == .leftBracket))
        if !follows || (kind == .identifier && isForbiddenWord(first)) { throw unexpected(.statement) }
        try entity(isTopLevel: true)
    }

    /// Each JSON draft's object read, once the whole text is well formed: on the object's UTF-16 code units, as
    /// JavaScript reads it.
    private mutating func readJSON() throws(MermaidDiagramReadError) {
        for (draft, literal) in pendingJSON {
            let start = tokens.starts[literal]
            let units = Array(text.string(range(of: literal)).utf16)
            do {
                drafts.jsonValues[Int(drafts.jsons[draft].value)] = try UseCaseJSONReader.read(units[...])
            } catch {
                throw jsonFailure(literalStart: start, units: units, offset: error.offset)
            }
            guard drafts.jsonValues[Int(drafts.jsons[draft].value)].root.kind == .object else { throw failure(at: start, .jsonRootNotObject) }
        }
    }

    /// Where JSON is not JSON, in the diagram's lines and columns of UTF-16 code units: a line feed, a carriage
    /// return, or both together, end a line.
    private func jsonFailure(literalStart: Int, units: [UInt16], offset: Int) -> MermaidDiagramReadError {
        var column = text.utf16Column(of: literalStart)
        var lineBreaks = 0
        for position in 0..<min(offset, units.count) {
            let unit = units[position]
            if unit == 0x0D || (unit == 0x0A && (position == 0 || units[position - 1] != 0x0D)) {
                lineBreaks += 1
                column = 1
            } else if unit != 0x0A {
                column += 1
            }
        }
        return .invalidSyntax(line: firstLine + text.line(of: literalStart) - 1 + lineBreaks, problem: .useCase(.invalidJSON(column: column)))
    }

    /// The name of an id made from a label: each character other than a letter, a digit and `_` made `_`, code unit by
    /// code unit, so a character of four bytes in UTF-8 (two code units) makes two. A label of word characters alone
    /// is its own id, written nowhere else.
    mutating func generatedName(_ label: MermaidTextRange) -> Int32 {
        let bytes = text.bytes
        let isWordAlone = bytes.withUnsafeBufferPointer { buffer in
            (label.lowerBound..<label.upperBound).allSatisfy { position in UseCaseCharacters.isWord(buffer[position]) }
        }
        guard !isWordAlone else { return intern(label) }
        var generated: [UInt8] = []
        generated.reserveCapacity(label.count)
        for position in label.lowerBound..<label.upperBound {
            let byte = bytes[position]
            if UseCaseCharacters.isWord(byte) {
                generated.append(byte)
            } else if byte & 0xC0 != 0x80 {
                generated.append(0x5F)
                if byte >= 0xF0 { generated.append(0x5F) }
            }
        }
        return intern(text.append(generated))
    }
}
