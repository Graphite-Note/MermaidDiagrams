/**
 * File: WardleyMapParser.swift
 * ----------------------------
 * Layer: Core
 * Description: Reads a Wardley map after its `wardley-beta` keyword as Pele's parser.ts reads Mermaid's Langium grammar:
 *              each statement by its first token, its parts in order, then Mermaid's builder fills the map.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// Reads a Wardley map's statements from its tokens (`WardleyMapLexer`), each ending at a line break or the end of the
/// text, then hands them to `WardleyMapBuilder` in Mermaid's order. A statement that starts with a name is a link.
struct WardleyMapParser {
    let tokens: [WardleyMapToken]
    let bytes: [UInt8]
    let limits: MermaidDiagramLimits
    var index = 0
    var statements = WardleyMapStatements()
    /// The things the statements make, bounded by the limits' nodes; the links bounded by its edges.
    var nodeCount = 0

    static func parse(_ cursor: MermaidTextCursor, limits: MermaidDiagramLimits) throws(MermaidDiagramReadError) -> WardleyMap {
        var parser = WardleyMapParser(tokens: try WardleyMapLexer.tokens(after: cursor), bytes: cursor.bytes, limits: limits)
        try parser.readStatements()
        var map = try WardleyMapBuilder.map(of: parser.statements, bytes: cursor.bytes)
        map.options = WardleyMapOptions(MermaidConfigurationOptions(section: "wardley-beta", in: cursor.bytes))
        return map
    }

    var current: WardleyMapTokenKind? {
        index < tokens.count ? tokens[index].kind : nil
    }

    func isAt(_ kind: WardleyMapTokenKind) -> Bool {
        current == kind
    }

    /// The text of the token at `position`.
    func text(_ position: Int) -> String {
        String(decoding: bytes[tokens[position].start..<tokens[position].end], as: UTF8.self)
    }

    mutating func take() -> String {
        index += 1
        return text(index - 1)
    }

    private mutating func readStatements() throws(MermaidDiagramReadError) {
        while let kind = current {
            let offset = tokens[index].start
            switch kind {
            case .newline:
                index += 1
                continue
            case .accessibilityDescription: statements.accessibilityDescription = nonEmpty(PlaneMapTerminalValues.accessibilityDescription(take()))
            case .accessibilityTitle: statements.accessibilityTitle = nonEmpty(PlaneMapTerminalValues.accessibilityTitle(take()))
            case .title: statements.title = nonEmpty(PlaneMapTerminalValues.title(take()))
            case .size:
                index += 1
                let pair = try readPair(of: .wholeNumber)
                statements.size = WardleyMapSize(width: pair.first, height: pair.second)
            case .evolution: try readEvolution()
            case .anchor, .accelerator, .deaccelerator, .evolve, .note: try readPlaced(kind, offset: offset)
            case .component: try readComponent(offset: offset)
            case .pipeline: try readPipeline(offset: offset)
            case .annotations:
                index += 1
                let pair = try readPair(of: nil)
                statements.annotationBoxes.append(.init(name: "", first: pair.first, second: pair.second, offset: offset))
            case .annotation: try readAnnotation(offset: offset)
            default: try readLink()
            }
            try expectLineEnd()
        }
    }

    /// `anchor`, `accelerator` and `deaccelerator` with a name and decimal coordinates, `evolve` with a name and a
    /// decimal, `note` with quoted text and decimal coordinates.
    private mutating func readPlaced(_ kind: WardleyMapTokenKind, offset: Int) throws(MermaidDiagramReadError) {
        index += 1
        if kind == .evolve {
            let name = try readName()
            statements.evolves.append(.init(name: name, first: try readDecimal(), second: 0, offset: offset))
            return
        }
        let name = kind == .note ? PlaneMapTerminalValues.string(try expect(.string, named: "STRING")) : try readName()
        let pair = try readPair(of: .decimal)
        try countNode()
        let placed = WardleyMapStatements.Placed(name: name, first: pair.first, second: pair.second, offset: offset)
        switch kind {
        case .anchor: statements.anchors.append(placed)
        case .accelerator: statements.accelerators.append(placed)
        case .deaccelerator: statements.deaccelerators.append(placed)
        default: statements.notes.append(placed)
        }
    }

    mutating func countNode() throws(MermaidDiagramReadError) {
        nodeCount += 1
        guard nodeCount <= limits.maximumNodeCount else { throw .tooManyNodes(limit: limits.maximumNodeCount) }
    }

    /// A line break, then any more, or the end of the text.
    private mutating func expectLineEnd() throws(MermaidDiagramReadError) {
        guard current != nil else { return }
        guard isAt(.newline) else { throw failure(.expectedLineEnd) }
        while isAt(.newline) { index += 1 }
    }

    /// The problem on the line of the current token, or of the last token at the end of the text.
    func failure(_ problem: WardleyMapSyntaxProblem) -> MermaidDiagramReadError {
        let offset = index < tokens.count ? tokens[index].start : tokens.last { token in token.kind != .newline }?.start ?? bytes.count
        return .invalidSyntax(line: PlaneMapByte.line(of: offset, in: bytes), problem: .wardleyMap(problem))
    }

    private func nonEmpty(_ text: String) -> String? {
        text.isEmpty ? nil : text
    }
}
