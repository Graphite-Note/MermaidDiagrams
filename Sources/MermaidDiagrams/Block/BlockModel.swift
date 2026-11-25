/**
 * File: BlockModel.swift
 * ----------------------
 * Layer: Core
 * Description: A block diagram as its reader leaves it: flat lists of small records over one block of bytes, the text
 *              read and the identifiers the reading made, with every identifier interned, so that the layout reads
 *              blocks, edges and classes without a String, an array per block or a dictionary keyed by text.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics

/// A run of a block model's bytes.
struct BlockText: Equatable, BitwiseCopyable {
    var start: Int32
    var count: Int32

    static let empty = BlockText(start: 0, count: 0)

    init(start: Int, count: Int) {
        self.start = Int32(truncatingIfNeeded: start)
        self.count = Int32(truncatingIfNeeded: count)
    }

    var lowerBound: Int { Int(start) }
    var upperBound: Int { Int(start) + Int(count) }
}

/// A run of a model's list of texts or of indices: `count` entries from `first`.
struct BlockSlice: Equatable, BitwiseCopyable {
    var first: Int32
    var count: Int32

    static let empty = BlockSlice(first: 0, count: 0)

    init(first: Int, count: Int) {
        self.first = Int32(truncatingIfNeeded: first)
        self.count = Int32(truncatingIfNeeded: count)
    }

    var range: Range<Int> { Int(first)..<(Int(first) + Int(count)) }
}

/// What a block is drawn as, `BlockKind` without its shape: the shape is the record's own.
enum BlockKindCode: UInt8, BitwiseCopyable {
    case unshaped, shape, arrow, composite, space
}

/// A block of the model: `BlockDiagramBlock` as plain values, its texts runs of the model's bytes, its lists slices of
/// the model's lists, its classes a chain through `BlockModel.classLinks`.
struct BlockRecord: BitwiseCopyable {
    var identifier: BlockText
    /// The identifier's place in the model's interned identifiers.
    var identifierNumber: Int32
    var kind: BlockKindCode
    /// The index in `FlowchartNodeShape.allCases` of a shaped block's shape.
    var shapeIndex: UInt8
    var label: BlockText
    /// The blocks it holds, a slice of `BlockModel.childIndices`.
    var children: BlockSlice = .empty
    var columns: Int = 0
    var hasColumns = false
    var widthInColumns: Int
    /// Its arrow's directions, a slice of `BlockModel.texts`.
    var directions: BlockSlice
    /// The first and last link of its class names in `BlockModel.classLinks`, -1 for none (no class statement named it).
    var firstClassLink: Int32 = -1
    var lastClassLink: Int32 = -1
    /// Its style's declarations, a slice of `BlockModel.texts`, nil when no style statement set them.
    var styles: BlockSlice?
    var colorIndex: Int32 = -1

    var blockKind: BlockKind {
        switch kind {
        case .unshaped: .unshaped
        case .shape: .shape(BlockModel.shapes[Int(shapeIndex)])
        case .arrow: .arrow
        case .composite: .composite
        case .space: .space
        }
    }

    var shape: FlowchartNodeShape { BlockModel.shapes[Int(shapeIndex)] }
    var hasStyling: Bool { firstClassLink >= 0 || styles != nil }
}

/// An edge of the model, its texts runs of the model's bytes.
struct BlockEdgeRecord: BitwiseCopyable {
    /// How many edges joined the same two identifiers up to this one, the number Pele's identifier starts with.
    var ordinal: Int32
    var source: BlockText
    var target: BlockText
    var sourceNumber: Int32
    var targetNumber: Int32
    var label: BlockText
    var sourceArrowhead: UInt8
    var targetArrowhead: UInt8
    var isThick: Bool
    var isDotted: Bool
}

/// A class name a block was given, and the next one it was given after, -1 at the last.
struct BlockClassLink: BitwiseCopyable {
    var name: BlockText
    var next: Int32
}

/// A `classDef`: its name, the place of its declarations in `BlockModel.texts`, kept in order of the statements.
struct BlockClassRecord {
    var name: BlockText
    var styles: [BlockText]
}

/// A block diagram read: every block (the root first, each container naming its children by their place), the edges,
/// the classes, the identifiers interned, over one block of bytes holding the text read and the texts the reading made.
/// Made once by the reader and never changed after, so diagrams share it.
final class BlockModel: Sendable {
    let bytes: [UInt8]
    let blocks: [BlockRecord]
    let edges: [BlockEdgeRecord]
    let classes: [BlockClassRecord]
    /// Each class's place in `classes` by its name's interned number in `classNames`, -1 where a name has no class.
    let classIndicesByNameNumber: [Int32]
    let classNames: BlockNameTable
    /// The children of the containers, each container's a slice.
    let childIndices: [Int32]
    /// The texts lists hold: arrows' directions and styles' declarations.
    let texts: [BlockText]
    let classLinks: [BlockClassLink]
    /// How many identifiers were interned.
    let identifierCount: Int
    /// The number `root` was interned with, when a block or an edge was written with it; -2 when none was.
    let rootIdentifierNumber: Int32

    static let shapes = FlowchartNodeShape.allCases
    static let arrowheads = FlowchartArrowhead.allCases

    init(bytes: [UInt8], blocks: [BlockRecord], edges: [BlockEdgeRecord], classes: [BlockClassRecord], classIndicesByNameNumber: [Int32],
         classNames: BlockNameTable, childIndices: [Int32], texts: [BlockText], classLinks: [BlockClassLink], identifiers: BlockNameTable) {
        self.bytes = bytes
        self.blocks = blocks
        self.edges = edges
        self.classes = classes
        self.classIndicesByNameNumber = classIndicesByNameNumber
        self.classNames = classNames
        self.childIndices = childIndices
        self.texts = texts
        self.classLinks = classLinks
        identifierCount = identifiers.count
        rootIdentifierNumber = identifiers.number(ofBytes: Self.rootIdentifierBytes, in: bytes).map(Int32.init) ?? -2
    }

    static let rootIdentifierBytes = Array("root".utf8)

    /// The text block of the label `text` holds, measured as `PlaneMapLabel.block` measures a String: nil for an empty
    /// text or one that decodes to nothing.
    func textBlock(of text: BlockText, measurer: some DiagramTextMeasuring, maximumWidth: CGFloat) -> DiagramTextBlock? {
        guard text.count > 0 else { return nil }
        let label = bytes.withUnsafeBufferPointer { buffer in
            DiagramLabelDecoder.label(fromUTF8: UnsafeBufferPointer(rebasing: buffer[text.lowerBound..<text.upperBound]), form: .plain)
        }
        guard !label.isEmpty else { return nil }
        return PlaneMapLabel.block(label, measurer: measurer, maximumWidth: maximumWidth)
    }

    func string(_ text: BlockText) -> String {
        bytes.withUnsafeBufferPointer { buffer in
            String(decoding: UnsafeBufferPointer(rebasing: buffer[text.lowerBound..<text.upperBound]), as: UTF8.self)
        }
    }

    func strings(_ slice: BlockSlice) -> [String] {
        texts[slice.range].map(string)
    }

    /// The class names of `block` in the order given, nil when none was.
    func classNames(of block: BlockRecord) -> [String]? {
        guard block.firstClassLink >= 0 else { return nil }
        var names: [String] = []
        var link = Int(block.firstClassLink)
        while link >= 0 {
            names.append(string(classLinks[link].name))
            link = Int(classLinks[link].next)
        }
        return names
    }

    /// The classes by name, as the diagram's `classes` gives them: made when a block's look needs them.
    func classDictionary() -> [String: BlockClassDefinition] {
        var classes: [String: BlockClassDefinition] = [:]
        classes.reserveCapacity(self.classes.count)
        for record in self.classes { classes[string(record.name)] = BlockClassDefinition(styles: record.styles.map(string)) }
        return classes
    }

    /// A block's identifier: its run of the bytes, `root` for the root.
    func identifier(of block: BlockRecord) -> String {
        block.identifierNumber < 0 ? Self.rootIdentifier : string(block.identifier)
    }

    static let rootIdentifier = "root"

    func edgeIdentifier(_ edge: BlockEdgeRecord) -> String {
        "\(edge.ordinal)-" + string(edge.source) + "-" + string(edge.target)
    }
}

extension BlockModel {
    /// The block at `index` as the diagram's `blocks` gives it.
    func block(at index: Int) -> BlockDiagramBlock {
        let record = blocks[index]
        var block = BlockDiagramBlock(identifier: identifier(of: record), kind: record.blockKind, label: string(record.label),
                                      widthInColumns: record.widthInColumns, directions: strings(record.directions))
        block.childIndices = childIndices[record.children.range].map(Int.init)
        block.columns = record.hasColumns ? record.columns : nil
        block.classNames = classNames(of: record)
        block.styles = record.styles.map(strings)
        block.colorIndex = record.colorIndex >= 0 ? Int(record.colorIndex) : nil
        return block
    }

    func edge(_ record: BlockEdgeRecord) -> BlockDiagramEdge {
        BlockDiagramEdge(identifier: edgeIdentifier(record), sourceIdentifier: string(record.source), targetIdentifier: string(record.target),
                         label: string(record.label), sourceArrowhead: Self.arrowheads[Int(record.sourceArrowhead)],
                         targetArrowhead: Self.arrowheads[Int(record.targetArrowhead)], isThick: record.isThick, isDotted: record.isDotted)
    }
}
