/**
 * File: ReferenceKanbanReader.swift
 * ---------------------------------
 * Layer: Tests
 * Description: The kanban reader of 0.7.0, frozen as the reference the byte reader of card metadata is checked against:
 *              its parser and board builder, which read every node's metadata into a dictionary through the whole YAML
 *              reader (its KanbanCardMetadata, frozen here; KanbanFlowReader, which both use, is unchanged).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

import Foundation
@testable import MermaidDiagrams

enum ReferenceKanbanParser {
    /// Reads the board whose keyword ends at the cursor. A board without a node is an error, as in Mermaid.
    static func parse(_ cursor: MermaidTextCursor, limits: MermaidDiagramLimits) throws(MermaidDiagramReadError) -> KanbanBoard {
        var builder = ReferenceKanbanBoardBuilder(limits: limits)
        builder.board.options = KanbanOptions(MermaidConfigurationOptions(section: "kanban", in: cursor))
        try MermaidOutlineReader.read(cursor, grammar: .kanban, into: &builder)
        guard !builder.board.columns.isEmpty else {
            var end = cursor
            end.advance(by: cursor.bytes.count)
            throw .invalidSyntax(line: end.line, problem: .expectedNode)
        }
        return builder.board
    }
}

/// Builds a board as Mermaid's kanban database does: the first node is a column and sets the columns' indentation; a
/// later node so indented is a column too, and any other a card of the last column. A node indented less than the
/// columns becomes a card, and Mermaid refuses any node after it.
struct ReferenceKanbanBoardBuilder: MermaidOutlineBuilding {
    var board = KanbanBoard()
    private let limits: MermaidDiagramLimits
    private var columnIndentation = 0
    /// The columns and cards made so far, which `MermaidDiagramLimits.maximumNodeCount` bounds: counted as they are made,
    /// as counting the board's at each node took time growing with the square of the columns.
    private var itemCount = 0
    /// The text of a node indented less than the columns, which no node may follow.
    private var misplacedText: String?

    init(limits: MermaidDiagramLimits) {
        self.limits = limits
    }

    mutating func addNode(_ definition: MindmapNodeDefinition, indentation: Int, metadata: String?, line: Int) throws(MermaidDiagramReadError) {
        let fields = try Self.fields(of: metadata, identifier: definition.identifier, line: line)
        if let misplacedText { throw .invalidSyntax(line: line, problem: .kanbanCardWithoutColumn(text: misplacedText)) }
        guard itemCount < limits.maximumNodeCount else { throw .tooManyNodes(limit: limits.maximumNodeCount) }
        itemCount += 1
        let label = fields["label"].map(MindmapNodeSyntax.label) ?? definition.label
        if fields["icon"] != nil { board.unappliedDecorationCount += 1 }
        if board.columns.isEmpty { columnIndentation = indentation }
        if indentation == columnIndentation {
            board.columns.append(KanbanColumn(identifier: definition.identifier, label: label))
            return
        }
        board.columns[board.columns.count - 1].cards.append(KanbanCard(identifier: definition.identifier, label: label, ticket: fields["ticket"],
                                                                       assignee: fields["assigned"],
                                                                       priority: fields["priority"].flatMap(KanbanPriority.init(written:))))
        if indentation < columnIndentation { misplacedText = label.spokenText }
    }

    /// An icon takes no room without the host's icons, and classes only a style sheet applies.
    mutating func decorate(_ decoration: MermaidOutlineDecoration) {
        board.unappliedDecorationCount += 1
    }

    /// Mermaid's kanban grammar has no accessibility text.
    mutating func apply(_ statement: MermaidAccessibilityStatement) {}

    /// The metadata's fields, or none. A shape named with a capital or an underscore is refused, as Mermaid refuses it.
    private static func fields(of metadata: String?, identifier: String, line: Int) throws(MermaidDiagramReadError) -> [String: String] {
        guard let metadata else { return [:] }
        let fields: [String: String]
        do {
            fields = try ReferenceKanbanCardMetadata(text: metadata).fields
        } catch {
            throw .invalidSyntax(line: line, problem: .kanbanMetadataNotYAML(identifier: identifier))
        }
        if let shape = fields["shape"], shape != shape.lowercased() || FoundationTextOnBytes.contains(shape, character: MermaidByte.underscore) {
            throw .invalidSyntax(line: line, problem: .kanbanShapeNameNotLowercase(shape))
        }
        return fields
    }
}

/// A kanban node's metadata as Pele reads it: the text on one line is a flow mapping (`{ ticket: MC-1, assigned: 'knsv' }`
/// without its braces), the text over several lines a block mapping (`key: value` a line). Each field is read as YAML's
/// JSON schema reads it and kept as JavaScript's `String` writes it, when JavaScript holds it true: no field for null,
/// `false`, `0` or empty text; a flow collection as `String` writes it (`KanbanYAMLValue.text`). A block collection under a
/// key is no field. Metadata that is not a mapping is ignored, as Pele ignores it; metadata that is not YAML is refused.
struct ReferenceKanbanCardMetadata {
    private(set) var fields: [String: String] = [:]

    init(text: String) throws(KanbanCardMetadata.Failure) {
        let bytes = Array(text.utf8)
        let first = bytes.first { byte in !MermaidByte.isWhitespace(byte) }
        if bytes.contains(MermaidByte.newline), first != MermaidByte.openingBrace, first != MermaidByte.openingBracket {
            try readBlock(bytes)
            return
        }
        let document = bytes.contains(MermaidByte.newline) ? bytes : Array("{\n".utf8) + bytes + Array("\n}".utf8)
        var reader = KanbanFlowReader(bytes: document)
        guard case .mapping(let values) = try reader.readDocument() else { return }
        fields = values
    }

    /// A block mapping: each line at the first line's indentation is `key: value`; a line indented more continues a plain
    /// value or holds a collection under a key with no value, which is no field.
    private mutating func readBlock(_ bytes: [UInt8]) throws(KanbanCardMetadata.Failure) {
        let lines = bytes.split(separator: MermaidByte.newline, omittingEmptySubsequences: false).map { line in
            line.last == MermaidByte.carriageReturn ? line.dropLast() : line
        }
        var mappingIndentation: Int?
        var lastKey: String?
        var lastValue = ""
        var continuesPlainValue = false
        for line in lines {
            let content = line.drop { byte in byte == MermaidByte.space }
            guard let first = content.first, first != UInt8(ascii: "#") else { continue }
            if first == MermaidByte.tab { throw .notYAML }
            let indentation = line.count - content.count
            let isFirst = mappingIndentation == nil
            if isFirst { mappingIndentation = indentation }
            guard let mappingIndentation, indentation >= mappingIndentation else { throw .notYAML }
            if indentation > mappingIndentation {
                guard let lastKey else { throw .notYAML }
                if continuesPlainValue { lastValue += " " + Self.withoutComment(content).trimmed; fields[lastKey] = Self.scalarText(lastValue) }
                continue
            }
            guard let (key, rest) = try Self.keyAndRest(content) else { throw .notYAML }
            lastKey = key
            let value = Self.withoutComment(rest.utf8).trimmed
            continuesPlainValue = !value.isEmpty && !"{['\"".utf8.contains(value.utf8.first ?? 0)
            lastValue = value
            if value.isEmpty {
                fields[key] = nil
            } else if continuesPlainValue {
                fields[key] = Self.scalarText(value)
            } else {
                var reader = KanbanFlowReader(bytes: Array(value.utf8))
                fields[key] = try reader.readDocument().text
            }
        }
    }

    /// `key: rest`, the key plain or quoted, the colon followed by a space or the end of the line.
    private static func keyAndRest(_ content: ArraySlice<UInt8>) throws(KanbanCardMetadata.Failure) -> (String, String)? {
        var reader = KanbanFlowReader(bytes: Array(content))
        guard let key = try reader.readKey(), reader.skipsColonBeforeValue() else { return nil }
        return (key, reader.rest)
    }

    private static func withoutComment(_ text: some Collection<UInt8>) -> String {
        var previous = MermaidByte.space
        var kept: [UInt8] = []
        for byte in text {
            if byte == UInt8(ascii: "#"), MermaidByte.isSpace(previous) { break }
            kept.append(byte)
            previous = byte
        }
        return String(decoding: kept, as: UTF8.self)
    }

    /// A plain scalar read by YAML's JSON schema, as JavaScript writes it when it holds it true.
    static func scalarText(_ written: String) -> String? {
        KanbanYAMLValue(plainScalar: written).text
    }
}

private extension String {
    var trimmed: String { FoundationTextOnBytes.trimmed(self, includingLineBreaks: false) }
}
