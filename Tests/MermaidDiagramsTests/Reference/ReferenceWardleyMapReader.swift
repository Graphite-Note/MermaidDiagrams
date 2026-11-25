/**
 * File: ReferenceWardleyMapReader.swift
 * -------------------------------------
 * Layer: Tests
 * Description: 0.7.0's Wardley map parser, statement reading and plane map terminal values, frozen as main 2a0cc65
 *              read them, which the Wardley map reader is compared with.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import Foundation
@testable import MermaidDiagrams

/// Reads a Wardley map's statements from its tokens (`ReferenceWardleyMapLexer`), each ending at a line break or the end of the
/// text, then hands them to `ReferenceWardleyMapBuilder` in Mermaid's order. A statement that starts with a name is a link.
struct ReferenceWardleyMapParser {
    let tokens: [ReferenceWardleyMapToken]
    let bytes: [UInt8]
    let limits: MermaidDiagramLimits
    var index = 0
    var statements = WardleyMapStatements()
    /// The things the statements make, bounded by the limits' nodes; the links bounded by its edges.
    var nodeCount = 0

    static func parse(_ cursor: MermaidTextCursor, limits: MermaidDiagramLimits) throws(MermaidDiagramReadError) -> WardleyMap {
        var parser = ReferenceWardleyMapParser(tokens: try ReferenceWardleyMapLexer.tokens(after: cursor), bytes: cursor.bytes, limits: limits)
        try parser.readStatements()
        var map = try ReferenceWardleyMapBuilder.map(of: parser.statements, bytes: cursor.bytes)
        map.options = WardleyMapOptions(MermaidConfigurationOptions(section: "wardley-beta", in: cursor))
        return map
    }

    var current: ReferenceWardleyMapTokenKind? {
        index < tokens.count ? tokens[index].kind : nil
    }

    func isAt(_ kind: ReferenceWardleyMapTokenKind) -> Bool {
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
            case .accessibilityDescription: statements.accessibilityDescription = nonEmpty(ReferencePlaneMapTerminalValues.accessibilityDescription(take()))
            case .accessibilityTitle: statements.accessibilityTitle = nonEmpty(ReferencePlaneMapTerminalValues.accessibilityTitle(take()))
            case .title: statements.title = nonEmpty(ReferencePlaneMapTerminalValues.title(take()))
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
    private mutating func readPlaced(_ kind: ReferenceWardleyMapTokenKind, offset: Int) throws(MermaidDiagramReadError) {
        index += 1
        if kind == .evolve {
            let name = try readName()
            statements.evolves.append(.init(name: name, first: try readDecimal(), second: 0, offset: offset))
            return
        }
        let name = kind == .note ? ReferencePlaneMapTerminalValues.string(try expect(.string, named: "STRING")) : try readName()
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


extension ReferenceWardleyMapParser {
    /// A quoted string without its quotation marks, an identifier, or a name with spaces.
    mutating func readName() throws(MermaidDiagramReadError) -> String {
        switch current {
        case .string: return ReferencePlaneMapTerminalValues.string(take())
        case .identifier, .name: return take()
        default: throw failure(.expectedName)
        }
    }

    /// The token's text when it is of `kind`; an error that names Pele's token otherwise.
    mutating func expect(_ kind: ReferenceWardleyMapTokenKind, named name: String) throws(MermaidDiagramReadError) -> String {
        guard isAt(kind) else { throw failure(.expectedToken(name)) }
        return take()
    }

    mutating func readDecimal() throws(MermaidDiagramReadError) -> Double {
        Double(try expect(.decimal, named: "WARDLEY_NUMBER")) ?? .nan
    }

    mutating func readWholeNumber() throws(MermaidDiagramReadError) -> Double {
        Double(try expect(.wholeNumber, named: "INT")) ?? .infinity
    }

    /// `[first, second]`, each of `kind`, or either a decimal or a whole number when `kind` is nil.
    mutating func readPair(of kind: ReferenceWardleyMapTokenKind?) throws(MermaidDiagramReadError) -> (first: Double, second: Double) {
        _ = try expect(.openingBracket, named: "'['")
        let first = try readCoordinate(of: kind)
        _ = try expect(.comma, named: "','")
        let second = try readCoordinate(of: kind)
        _ = try expect(.closingBracket, named: "']'")
        return (first, second)
    }

    private mutating func readCoordinate(of kind: ReferenceWardleyMapTokenKind?) throws(MermaidDiagramReadError) -> Double {
        switch kind {
        case .decimal: return try readDecimal()
        case .wholeNumber: return try readWholeNumber()
        default: return isAt(.decimal) ? try readDecimal() : try readWholeNumber()
        }
    }

    /// `label [x, y]`, each a whole number with an optional minus sign.
    mutating func readLabelOffset() throws(MermaidDiagramReadError) -> WardleyMapStatements.LabelOffset {
        _ = try expect(.label, named: "KW_LABEL")
        _ = try expect(.openingBracket, named: "'['")
        let x = try readSignedWholeNumber()
        _ = try expect(.comma, named: "','")
        let y = try readSignedWholeNumber()
        _ = try expect(.closingBracket, named: "']'")
        return WardleyMapStatements.LabelOffset(x: x, y: y)
    }

    private mutating func readSignedWholeNumber() throws(MermaidDiagramReadError) -> Double {
        let isNegative = isAt(.minus)
        if isNegative { index += 1 }
        return (isNegative ? -1 : 1) * (try readWholeNumber())
    }

    /// `evolution` and two or more stages joined by `->`, each a name, `@` and its right edge, and `/` and a second name.
    mutating func readEvolution() throws(MermaidDiagramReadError) {
        index += 1
        var stages = [try readStage()]
        _ = try expect(.arrow, named: "ARROW")
        stages.append(try readStage())
        while isAt(.arrow) {
            index += 1
            guard stages.count < limits.maximumNodeCount else { throw .tooManyNodes(limit: limits.maximumNodeCount) }
            stages.append(try readStage())
        }
        statements.stages = stages
    }

    private mutating func readStage() throws(MermaidDiagramReadError) -> WardleyMapStatements.Stage {
        let name = try readName()
        var boundary: Double?
        if isAt(.atSign) {
            index += 1
            boundary = try readDecimal()
        }
        var secondName: String?
        if isAt(.slash) {
            index += 1
            secondName = try readName()
        }
        return WardleyMapStatements.Stage(name: name, boundary: boundary, secondName: secondName)
    }

    /// `component`, a name, `[visibility, evolution]`, a label offset, `(build)`, `(buy)`, `(outsource)` or `(market)`, and
    /// `inertia` or `(inertia)`, each optional in that order.
    mutating func readComponent(offset: Int) throws(MermaidDiagramReadError) {
        index += 1
        let name = try readName()
        let pair = try readPair(of: .decimal)
        let labelOffset = isAt(.label) ? try readLabelOffset() : nil
        var sourcing: WardleyMapSourcing?
        if isAt(.openingParenthesis), index + 1 < tokens.count, tokens[index + 1].kind == .sourcing {
            sourcing = WardleyMapSourcing(rawValue: text(index + 1))
            index += 2
            _ = try expect(.closingParenthesis, named: "')'")
        }
        var hasInertia = false
        if isAt(.inertia) {
            index += 1
            hasInertia = true
        } else if isAt(.openingParenthesis) {
            index += 1
            _ = try expect(.inertia, named: "KW_INERTIA")
            _ = try expect(.closingParenthesis, named: "')'")
            hasInertia = true
        }
        try countNode()
        statements.components.append(.init(name: name, visibility: pair.first, evolution: pair.second, labelOffset: labelOffset, sourcing: sourcing,
                                           hasInertia: hasInertia, offset: offset))
    }

    /// `pipeline`, its parent's name and `{`, a line break, then one or more components with one decimal each and an
    /// optional label offset, each ending its line, then `}`.
    mutating func readPipeline(offset: Int) throws(MermaidDiagramReadError) {
        index += 1
        let parent = try readName()
        _ = try expect(.openingBrace, named: "'{'")
        _ = try expect(.newline, named: "NEWLINE")
        while isAt(.newline) { index += 1 }
        var components: [WardleyMapStatements.PipelineComponent] = []
        repeat {
            let componentOffset = index < tokens.count ? tokens[index].start : bytes.count
            _ = try expect(.component, named: "KW_COMPONENT")
            let name = try readName()
            _ = try expect(.openingBracket, named: "'['")
            let evolution = try readDecimal()
            _ = try expect(.closingBracket, named: "']'")
            let labelOffset = isAt(.label) ? try readLabelOffset() : nil
            if current != nil {
                guard isAt(.newline) else { throw failure(.expectedLineEnd) }
                while isAt(.newline) { index += 1 }
            }
            try countNode()
            components.append(.init(name: name, evolution: evolution, labelOffset: labelOffset, offset: componentOffset))
        } while isAt(.component)
        _ = try expect(.closingBrace, named: "'}'")
        statements.pipelines.append(.init(parent: parent, components: components, offset: offset))
    }

    /// `annotation`, its number, `,`, its coordinates, decimal or whole, and its quoted text.
    mutating func readAnnotation(offset: Int) throws(MermaidDiagramReadError) {
        index += 1
        let number = try readWholeNumber()
        _ = try expect(.comma, named: "','")
        let pair = try readPair(of: nil)
        let text = ReferencePlaneMapTerminalValues.string(try expect(.string, named: "STRING"))
        try countNode()
        statements.annotations.append(.init(number: number, first: pair.first, second: pair.second, text: text, offset: offset))
    }

    /// A link: a name, a port, an arrow, a name, a port and a label after `;`, the ports, the arrow and the label optional.
    mutating func readLink() throws(MermaidDiagramReadError) {
        guard isAt(.string) || isAt(.identifier) || isAt(.name) else { throw failure(.expectedStatement) }
        let from = try readName()
        let fromPort = isAt(.linkPort) ? take() : nil
        let arrow = isAt(.linkArrow) || isAt(.arrow) ? take() : nil
        let to = try readName()
        let toPort = isAt(.linkPort) ? take() : nil
        let label = isAt(.linkLabel) ? PlaneMapText.trimmed(String(take().dropFirst())) : nil
        guard statements.links.count < limits.maximumEdgeCount else { throw .tooManyEdges(limit: limits.maximumEdgeCount) }
        statements.links.append(.init(from: from, fromPort: fromPort, arrow: arrow, to: to, toPort: toPort, label: label))
    }
}

/// The values of shared terminals, each from the token's text as matched.
enum ReferencePlaneMapTerminalValues {
    /// A title's text: after `title`, trimmed, runs of spaces and tabs made one space.
    static func title(_ token: String) -> String {
        PlaneMapText.singleSpaced(String(token.dropFirst("title".count)))
    }

    /// An accessibility title's text: after its colon, trimmed, runs of blanks made one.
    static func accessibilityTitle(_ token: String) -> String {
        guard let colon = token.firstIndex(of: ":") else { return "" }
        return PlaneMapText.singleSpaced(String(token[token.index(after: colon)...]))
    }

    /// An accessibility description's text: after its colon as a title's, or between its braces each line trimmed, the
    /// empty ones left out, runs of blanks made one space, joined by line breaks.
    static func accessibilityDescription(_ token: String) -> String {
        let afterKeyword = token.dropFirst("accDescr".count)
        let start = afterKeyword.drop { character in character == " " || character == "\t" }
        if start.first == ":" { return PlaneMapText.singleSpaced(String(start.dropFirst())) }
        guard let opening = token.firstIndex(of: "{"), let closing = token.lastIndex(of: "}"), opening < closing else { return "" }
        let lines = token[token.index(after: opening)..<closing].split(whereSeparator: { character in character == "\n" || character == "\r" || character == "\r\n" })
        return lines.map { line in PlaneMapText.singleSpaced(String(line)) }.filter { line in !line.isEmpty }.joined(separator: "\n")
    }

    /// A string's text without its quotation marks, each backslash replaced by the character it escapes (`\n` a line
    /// break, `\t` a tab, `\0` a null character; any other character itself).
    static func string(_ token: String) -> String {
        let inside = token.dropFirst().dropLast()
        guard inside.contains("\\") else { return String(inside) }
        var text = ""
        var isEscaping = false
        for character in inside {
            if isEscaping {
                text.append(escapes[character] ?? character)
                isEscaping = false
            } else if character == "\\" {
                isEscaping = true
            } else {
                text.append(character)
            }
        }
        return text
    }

    private static let escapes: [Character: Character] = ["b": "\u{08}", "f": "\u{0C}", "n": "\n", "r": "\r", "t": "\t", "v": "\u{0B}", "0": "\u{00}"]
}
