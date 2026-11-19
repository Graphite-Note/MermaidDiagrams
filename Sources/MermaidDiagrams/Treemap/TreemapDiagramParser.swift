/**
 * File: TreemapDiagramParser.swift
 * --------------------------------
 * Layer: Core
 * Description: Reads a treemap's rows after its `treemap` keyword and builds its hierarchy and its classes' styles.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// Reads the rows after the `treemap` or `treemap-beta` keyword as Mermaid's grammar does. A row is its indentation (spaces or
/// tabs, counted as characters), then a quoted name and, for a leaf, `:` or `,` and a value, then `:::class` to name a class;
/// or `classDef name declarations`. `title …`, `accTitle: …`, `accDescr: …` and `accDescr { … }` may come between rows. A
/// row belongs to the nearest section above it that is indented less. `%%` starts a comment.
struct TreemapDiagramParser {
    private var cursor: MermaidTextCursor
    private var diagram = TreemapDiagram()
    private var statements = MermaidTitleStatements()
    /// The sections still open: their node's index and the indentation they were written at, innermost last.
    private var openSections: [(nodeIndex: Int, level: Int)] = []
    private var classDefinitions: [TreemapClassDefinition] = []
    private let limits: MermaidDiagramLimits

    private init(cursor: MermaidTextCursor, limits: MermaidDiagramLimits) {
        self.cursor = cursor
        self.limits = limits
    }

    static func parse(_ cursor: MermaidTextCursor, limits: MermaidDiagramLimits) throws(MermaidDiagramReadError) -> TreemapDiagram {
        var parser = TreemapDiagramParser(cursor: cursor, limits: limits)
        parser.diagram.options = TreemapOptions(MermaidConfigurationOptions(section: "treemap", in: cursor.bytes))
        try parser.readRows()
        parser.finish()
        return parser.diagram
    }

    private mutating func readRows() throws(MermaidDiagramReadError) {
        while true {
            TreemapRowTokens.skipHidden(&cursor)
            guard !cursor.isAtEnd else { return }
            // The titles' tokens begin with the blank before them.
            var lookahead = cursor
            lookahead.skipSpaces()
            if try statements.read(&lookahead) {
                cursor = lookahead
                continue
            }
            let level = TreemapRowTokens.readIndentation(&cursor) ?? 0
            TreemapRowTokens.skipHidden(&cursor)
            if let definition = TreemapRowTokens.readClassDefinition(&cursor) {
                guard classDefinitions.count < limits.maximumNodeCount else { throw .tooManyNodes(limit: limits.maximumNodeCount) }
                classDefinitions.append(definition)
            } else if let name = try TreemapRowTokens.readQuotedName(&cursor) {
                try readItem(named: name, level: level)
            } else {
                throw .invalidSyntax(line: cursor.line, problem: .treemap(.expectedNameOrClassDefinition))
            }
        }
    }

    /// What follows a row's name: a leaf's `:` or `,` and its value (the blank before the separator and the one after it
    /// allowed), or nothing for a section; then `:::` and a class's name.
    private mutating func readItem(named name: String, level: Int) throws(MermaidDiagramReadError) {
        var value: Double?
        var isSection = true
        if skipsSeparator() {
            isSection = false
            TreemapRowTokens.skipHidden(&cursor)
            _ = TreemapRowTokens.readIndentation(&cursor)
            TreemapRowTokens.skipHidden(&cursor)
            guard let read = TreemapRowTokens.readValue(&cursor) else { throw .invalidSyntax(line: cursor.line, problem: .treemap(.expectedValue)) }
            value = read
        }
        var className: String?
        var lookahead = cursor
        TreemapRowTokens.skipHidden(&lookahead)
        if lookahead.hasPrefix(Self.styleSeparator) {
            lookahead.advance(by: Self.styleSeparator.count)
            TreemapRowTokens.skipHidden(&lookahead)
            guard let read = TreemapRowTokens.readClassName(&lookahead) else { throw .invalidSyntax(line: lookahead.line, problem: .treemap(.expectedClassName)) }
            className = read
            cursor = lookahead
        }
        try add(TreemapNode(name: name, value: value, isSection: isSection, parentIndex: nil, className: className), level: level)
    }

    /// Moves past a `:` (not the start of `:::`) or a `,` that comes after the name, with a blank or line breaks before it; false,
    /// with the cursor where it was, when something else comes.
    private mutating func skipsSeparator() -> Bool {
        var lookahead = cursor
        TreemapRowTokens.skipHidden(&lookahead)
        if TreemapRowTokens.readIndentation(&lookahead) != nil { TreemapRowTokens.skipHidden(&lookahead) }
        guard let byte = lookahead.peek(), byte == MermaidByte.comma || (byte == MermaidByte.colon && !lookahead.hasPrefix(Self.styleSeparator)) else {
            return false
        }
        lookahead.advance()
        cursor = lookahead
        return true
    }

    /// Adds the node under the nearest open section indented less, and opens it if it is a section.
    private mutating func add(_ node: TreemapNode, level: Int) throws(MermaidDiagramReadError) {
        guard diagram.nodes.count < limits.maximumNodeCount else { throw .tooManyNodes(limit: limits.maximumNodeCount) }
        while let last = openSections.last, last.level >= level { openSections.removeLast() }
        let index = diagram.nodes.count
        diagram.nodes.append(TreemapNode(name: node.name, value: node.value, isSection: node.isSection, parentIndex: openSections.last?.nodeIndex,
                                         className: node.className))
        if node.isSection { openSections.append((index, level)) }
    }

    /// The titles, and each class's style from every `classDef` of the text, a later one over an earlier.
    private mutating func finish() {
        diagram.title = statements.title
        diagram.accessibilityTitle = statements.accessibilityTitle
        diagram.accessibilityDescription = statements.accessibilityDescription
        for definition in classDefinitions {
            let (style, unappliedCount) = TreemapClassStyle.reading(definition.styleText ?? "")
            diagram.classStyles[definition.name] = (diagram.classStyles[definition.name] ?? DiagramElementStyle()).overridden(by: style)
            diagram.unappliedStatementCount += unappliedCount
        }
    }

    private static let styleSeparator = Array(":::".utf8)
}
