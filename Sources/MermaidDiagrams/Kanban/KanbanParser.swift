/**
 * File: KanbanParser.swift
 * ------------------------
 * Layer: Core
 * Description: Reads a kanban board's outline into its columns and cards, as Mermaid's kanban database builds them.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 23/11/2026
 */

/// Reads a kanban board's lines after its `kanban` keyword as the outline Mermaid's mindmap and kanban grammars share
/// (`MermaidOutlineReader`), with a node's metadata straight after it (`@{ … }`). Mermaid's kanban grammar has no
/// accessibility text: `accTitle: …` is a node, as there.
enum KanbanParser {
    /// Reads the board whose keyword ends at the cursor. A board without a node is an error, as in Mermaid.
    static func parse(_ cursor: MermaidTextCursor, limits: MermaidDiagramLimits) throws(MermaidDiagramReadError) -> KanbanBoard {
        var builder = KanbanBoardBuilder(limits: limits)
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
struct KanbanBoardBuilder: MermaidOutlineBuilding {
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
            fields = try KanbanCardMetadata(text: metadata).fields
        } catch {
            throw .invalidSyntax(line: line, problem: .kanbanMetadataNotYAML(identifier: identifier))
        }
        if let shape = fields["shape"], shape != shape.lowercased() || shape.contains("_") {
            throw .invalidSyntax(line: line, problem: .kanbanShapeNameNotLowercase(shape))
        }
        return fields
    }
}
