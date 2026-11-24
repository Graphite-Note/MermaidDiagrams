/**
 * File: BlockDiagram.swift
 * ------------------------
 * Layer: Core
 * Description: A block diagram read from Mermaid text: its blocks in their nested grids, its edges, its classes and
 *              styles, as Pele's block database keeps them, a view over the flat model the reader leaves.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

import CoreGraphics

/// A block diagram (`block` or `block-beta`), as Pele's `BlockDb` holds it once its statements are set into their
/// hierarchy: every block kept in one list, the diagram's root first, each container naming its children by their place
/// in the list, so that nesting thousands deep is never a nesting of values. A block is drawn when the root reaches it
/// through its containers' children; a block only a `class` or `style` statement named, or the composite a later block
/// of the same identifier made, stays in the list unreached, as Pele's map keeps it.
public struct BlockDiagram: Equatable, Sendable {
    public internal(set) var title: String?
    /// The front matter's or a directive's `block.padding`, between 0 and 200, or nil for Pele's 12 points.
    public internal(set) var padding: CGFloat?
    /// The blocks, edges and classes as plain records over the text's bytes, which the layout reads; the lists below
    /// are made from it when read.
    let model: BlockModel

    /// The root's place in `blocks`: always the first.
    public static let rootIndex = 0

    init(model: BlockModel) {
        self.model = model
    }

    /// A diagram of these values, as 0.7.0's reader made them.
    init(blocks: [BlockDiagramBlock], edges: [BlockDiagramEdge], classes: [String: BlockClassDefinition]) {
        model = BlockModel(blocks: blocks, edges: edges, classes: classes)
    }

    /// Every block, the root at `rootIndex`, made from the model when read.
    public var blocks: [BlockDiagramBlock] { model.blocks.indices.map(model.block(at:)) }
    /// The edges in the order written, each link of a statement with several (`A --> B --> C`) its own.
    public var edges: [BlockDiagramEdge] { model.edges.map(model.edge) }
    /// The classes `classDef` defines, by name.
    public var classes: [String: BlockClassDefinition] { model.classDictionary() }

    /// Two diagrams are equal when their titles, padding, blocks, edges and classes are.
    public static func == (first: BlockDiagram, second: BlockDiagram) -> Bool {
        first.title == second.title && first.padding == second.padding && first.blocks == second.blocks && first.edges == second.edges
            && first.classes == second.classes
    }

    /// The blocks the root holds, each container's after its own, outermost first: what is laid out, breadth first.
    var reachableBlockIndices: [Int] {
        var order = [Self.rootIndex]
        var next = 0
        while next < order.count {
            order.append(contentsOf: model.childIndices[model.blocks[order[next]].children.range].lazy.map(Int.init))
            next += 1
        }
        return order
    }
}

/// A block, a composite holding others, an arrow or a space.
public struct BlockDiagramBlock: Equatable, Sendable {
    public internal(set) var identifier: String
    public internal(set) var kind: BlockKind
    /// The text written in its brackets, as written (entity codes and `<br>` are read when it is laid out); its
    /// identifier when it has none, and empty for a composite without a title.
    public internal(set) var label: String
    /// The blocks it holds, by their place in `BlockDiagram.blocks`, in the order written.
    public internal(set) var childIndices: [Int]
    /// The `columns` statement of a container: a count, or nil for `columns auto` and for none, one row of every child.
    /// A count written past `Int`'s range is kept as `Int.max`; zero is kept, and refused when laid out, as in Pele.
    public internal(set) var columns: Int?
    /// How many columns it spans (`id:3`), as written; laid out at least one and at most a thousand or the columns left.
    public internal(set) var widthInColumns: Int
    /// An arrow's directions as written (`right`, `x`, ` up `).
    public internal(set) var directions: [String]
    /// The classes `class` statements gave it, in order; nil when none did.
    public internal(set) var classNames: [String]?
    /// The declarations of its `style` statement, split at commas as Pele splits them; nil without one.
    public internal(set) var styles: [String]?
    /// A composite's place in the order composites are declared, which colors it in a theme with a palette.
    public internal(set) var colorIndex: Int?

    init(identifier: String, kind: BlockKind, label: String, widthInColumns: Int = 1, directions: [String] = []) {
        self.identifier = identifier
        self.kind = kind
        self.label = label
        self.childIndices = []
        self.columns = nil
        self.widthInColumns = widthInColumns
        self.directions = directions
    }
}

/// What a block is drawn as.
public enum BlockKind: Equatable, Sendable {
    /// No brackets (`id`): a rectangle, Pele's `na`.
    case unshaped
    /// A flowchart's bracket shape (`id["text"]`, `id(("text"))`): one of the fourteen classic shapes.
    case shape(FlowchartNodeShape)
    /// A block arrow (`id<["text"]>(right)`).
    case arrow
    /// A block holding others (`block … end`, `block:id … end`).
    case composite
    /// An empty cell (`space`, `space:3`, one block per cell).
    case space
}

/// An edge between two blocks, by their identifiers.
public struct BlockDiagramEdge: Equatable, Sendable {
    /// Pele's: the count of edges so far between the same ends and the ends' identifiers (`1-A-B`).
    public let identifier: String
    public let sourceIdentifier: String
    public let targetIdentifier: String
    /// The text written in quotation marks on the link (`-- "text" -->`), or empty.
    public let label: String
    public let sourceArrowhead: FlowchartArrowhead
    public let targetArrowhead: FlowchartArrowhead
    /// `==`: a line 2.5 points wide.
    public let isThick: Bool
    /// `.-`: a dotted line.
    public let isDotted: Bool
}

/// A `classDef`: its declarations split at commas, as Pele's `addStyleClass` keeps them.
public struct BlockClassDefinition: Equatable, Sendable {
    public internal(set) var styles: [String]
}

/// What broke a block diagram's syntax, beyond text the lexer does not read.
public enum BlockSyntaxProblem: Equatable, Sendable {
    /// The text does not start with `block` or `block-beta`.
    case expectedKeyword
    /// A statement was expected: a block, `columns`, `space`, `block`, `classDef`, `class` or `style`, or `end` when a
    /// composite is open.
    case expectedStatement
    /// A block's identifier was expected: after a link, or after `block:`.
    case expectedBlockIdentifier
    /// Text in quotation marks was expected: inside a block's brackets, an arrow's, or on a link after `--`.
    case expectedQuotedText
    /// The bracket that closes a block's shape was expected after its text.
    case expectedClosingBracket
    /// An arrow's direction (`right`, `left`, `up`, `down`, `x`, `y`) was expected inside its parentheses.
    case expectedArrowDirection
    /// The `)` that closes an arrow's directions was expected.
    case expectedArrowEnd
    /// The rest of a labelled link (`-->`) was expected after its text.
    case expectedLink
    /// A class's name was expected after `classDef`, or its declarations after the name.
    case expectedClassDefinition
    /// Blocks and a class's name were expected after `class`, or blocks and declarations after `style`.
    case expectedStyleTarget
    /// The text ends inside a composite: `end` was expected.
    case unclosedComposite
}
