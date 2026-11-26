/**
 * File: BlockViews.swift
 * ----------------------
 * Layer: Core
 * Description: Measures a block diagram's blocks as Pele's block renderer does before it lays them out: each block's
 *              text, its shape's or arrow's size around it, a composite's title and the room around it.
 *
 * Authors: Bahey Shalash
 * Version: 0.5
 * Date: 26/11/2026
 */

import CoreGraphics

/// The measurers of a block diagram's text: a block's at the diagram's size, an edge's at seven eighths of it, the title
/// in bold, and a block's in the size, bold and italic its style asks for, made only for a block whose style asks.
struct BlockMeasurers<Measurer: DiagramTextMeasuring> {
    let nodeText: Measurer
    let edgeText: Measurer
    let titleText: Measurer
    let restyled: (_ fontSize: CGFloat, _ isBold: Bool, _ isItalic: Bool) -> Measurer
}

/// A block as Pele's renderer sees it, Pele's `View` beside its `Cell`.
struct BlockView {
    enum Kind: Equatable {
        case leaf(FlowchartNodeShape)
        case arrow(BlockArrowDirections)
        case composite
        case space
    }

    let blockIndex: Int
    let kind: Kind
    /// Its text at its own size, nil for none; a composite's is its title.
    let text: DiagramTextBlock?
    let appearance: BlockAppearance
    /// How far its text's center is from its center.
    var textOffset: CGVector
    /// The size it is drawn at, which for a circle or a diamond is its own in a larger cell.
    var drawnSize = CGSize.zero
}

/// Pele's `view` over every block the root reaches, breadth first: the cells the grid lays out and the views beside them.
struct BlockViews {
    private(set) var cells: [BlockCell] = []
    private(set) var views: [BlockView] = []
    /// Each cell's container's place, -1 for the root.
    private(set) var parentIndices: [Int] = []
    /// The cell of each block drawn (not a space), by its identifier's interned number, -1 for none; the last block of
    /// an identifier reached has it.
    private(set) var cellIndicesByIdentifierNumber: [Int32]
    /// The cell of the block drawn under the root's identifier, `root`, which no number names: the root, or the last
    /// block written `root` reached.
    private(set) var rootIdentifierCellIndex = -1

    /// Shapes kept at their own size in a larger cell, where the others stretch to fill it.
    static let keepsOwnSize: Set<FlowchartNodeShape> = [.circle, .doubleCircle, .diamond]
    /// Shapes that only widen, as their slants and curves are set by their height.
    static let onlyWidens: Set<FlowchartNodeShape> = [.stadium, .hexagon, .asymmetric, .leanRight, .leanLeft, .trapezoid, .invertedTrapezoid]

    /// Whether `shape` is one of `keepsOwnSize`, told without hashing it.
    static func keepsItsOwnSize(_ shape: FlowchartNodeShape) -> Bool {
        switch shape {
        case .circle, .doubleCircle, .diamond: true
        default: false
        }
    }

    /// Whether `shape` is one of `onlyWidens`, told without hashing it.
    static func onlyWidensItself(_ shape: FlowchartNodeShape) -> Bool {
        switch shape {
        case .stadium, .hexagon, .asymmetric, .leanRight, .leanLeft, .trapezoid, .invertedTrapezoid: true
        default: false
        }
    }

    init<Measurer: DiagramTextMeasuring>(_ diagram: BlockDiagram, measurers: BlockMeasurers<Measurer>, gap: CGFloat, wrappingWidth: CGFloat,
                                         titleWidth: CGFloat) {
        var cache = BlockMeasurerCache(measurers: measurers, model: diagram.model)
        self.init(diagram, cache: &cache, gap: gap, wrappingWidth: wrappingWidth, titleWidth: titleWidth)
    }

    /// The views of `diagram`, its blocks' looks and their measurers kept in `cache`, which the layout goes on using.
    init<Measurer: DiagramTextMeasuring>(_ diagram: BlockDiagram, cache: inout BlockMeasurerCache<Measurer>, gap: CGFloat, wrappingWidth: CGFloat,
                                         titleWidth: CGFloat) {
        let model = diagram.model
        var queue = [(block: BlockDiagram.rootIndex, parent: -1)]
        queue.reserveCapacity(model.blocks.count)
        cells.reserveCapacity(model.blocks.count)
        views.reserveCapacity(model.blocks.count)
        parentIndices.reserveCapacity(model.blocks.count)
        cellIndicesByIdentifierNumber = Array(repeating: -1, count: model.edges.isEmpty ? 0 : model.identifierCount)
        var next = 0
        while next < queue.count {
            let (blockIndex, parent) = queue[next]
            next += 1
            let block = model.blocks[blockIndex]
            let (measuredCell, view) = Self.measured(block, at: blockIndex, model: model, cache: &cache, gap: gap, wrappingWidth: wrappingWidth,
                                                     titleWidth: titleWidth)
            var cell = consume measuredCell
            if blockIndex == BlockDiagram.rootIndex { (cell.neededWidth, cell.neededHeight) = (0, 0) }
            let index = cells.count
            if parent >= 0 { cells[parent].childIndices.append(index) }
            let kind = view.kind
            cells.append(consume cell)
            views.append(consume view)
            parentIndices.append(parent)
            if kind != .space { recordCell(index, of: block, in: model) }
            if kind == .composite {
                cells[index].childIndices.reserveCapacity(Int(block.children.count))
                for child in model.childIndices[block.children.range] { queue.append((Int(child), index)) }
            }
        }
    }

    /// The cell of `block`, kept by its identifier's number for the edges to find, when the diagram has edges.
    private mutating func recordCell(_ index: Int, of block: BlockRecord, in model: BlockModel) {
        if block.identifierNumber < 0 || block.identifierNumber == model.rootIdentifierNumber { rootIdentifierCellIndex = index }
        guard block.identifierNumber >= 0, Int(block.identifierNumber) < cellIndicesByIdentifierNumber.count else { return }
        cellIndicesByIdentifierNumber[Int(block.identifierNumber)] = Int32(index)
    }

    /// The cell of each block drawn (not a space) by its identifier, the last block of an identifier reached having it:
    /// what the numbers keep, as text, for tests.
    func cellIndicesByIdentifier(in diagram: BlockDiagram) -> [String: Int] {
        var cellIndices: [String: Int] = [:]
        for (index, view) in views.enumerated() where view.kind != .space {
            cellIndices[diagram.model.identifier(of: diagram.model.blocks[view.blockIndex])] = index
        }
        return cellIndices
    }

    /// The cell of the block drawn under the identifier numbered `number` in the diagram's edges, nil for none.
    func cellIndex(ofIdentifierNumber number: Int32, in model: BlockModel) -> Int? {
        if number == model.rootIdentifierNumber { return rootIdentifierCellIndex >= 0 ? rootIdentifierCellIndex : nil }
        guard number >= 0, Int(number) < cellIndicesByIdentifierNumber.count else { return nil }
        let index = cellIndicesByIdentifierNumber[Int(number)]
        return index >= 0 ? Int(index) : nil
    }

    /// A block's cell and view, measured.
    private static func measured<Measurer: DiagramTextMeasuring>(_ block: BlockRecord, at blockIndex: Int, model: BlockModel,
                                                                 cache: inout BlockMeasurerCache<Measurer>, gap: CGFloat, wrappingWidth: CGFloat,
                                                                 titleWidth: CGFloat) -> (cell: BlockCell, view: BlockView) {
        var cell = BlockCell()
        cell.span = block.kind == .space ? 1 : block.widthInColumns
        if block.kind == .space {
            cell.isSpace = true
            return (cell, BlockView(blockIndex: blockIndex, kind: .space, text: nil, appearance: BlockAppearance(), textOffset: .zero))
        }
        let appearance = cache.appearance(of: block)
        let measurer = cache.measurer(for: appearance)
        switch block.kind {
        case .composite:
            cell.columns = block.hasColumns ? block.columns : -1
            let title = model.textBlock(of: block.label, measurer: measurer, maximumWidth: titleWidth)
            let titleHeight = title.map { text in text.size.height + 4 } ?? 0
            cell.titleHeight = titleHeight
            cell.neededWidth = (title?.size.width ?? 0) + 2 * gap
            cell.neededHeight = titleHeight + 2 * gap
            return (cell, BlockView(blockIndex: blockIndex, kind: .composite, text: title, appearance: appearance, textOffset: .zero))
        case .arrow:
            let text = model.textBlock(of: block.label, measurer: measurer, maximumWidth: wrappingWidth)
            let directions = BlockArrowDirections(written: model.strings(block.directions))
            let isBlank = text?.lines.allSatisfy { line in line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? true
            let (size, offset) = BlockArrowShape.size(of: directions, textSize: isBlank ? .zero : text?.size ?? .zero)
            (cell.neededWidth, cell.neededHeight) = (size.width, size.height)
            return (cell, BlockView(blockIndex: blockIndex, kind: .arrow(directions), text: text, appearance: appearance, textOffset: offset))
        default:
            let shape = block.kind == .shape ? block.shape : FlowchartNodeShape.rectangle
            let text = model.textBlock(of: block.label, measurer: measurer, maximumWidth: wrappingWidth)
            let textSize = text?.size ?? .zero
            let (size, offset) = FlowchartShapeGeometry.size(of: shape, textSize: textSize)
            cell.neededWidth = size.width
            // A cylinder's caps deepen as it widens, so it is sized for the deepest ones.
            cell.neededHeight = shape == .cylinder ? max(size.height, textSize.height + 40) : size.height
            return (cell, BlockView(blockIndex: blockIndex, kind: .leaf(shape), text: text, appearance: appearance, textOffset: CGVector(dx: 0, dy: offset)))
        }
    }
}

/// The measurer of each look a block's text asks for, made once: the diagram's own for the usual one.
struct BlockMeasurerCache<Measurer: DiagramTextMeasuring> {
    let measurers: BlockMeasurers<Measurer>
    /// The measurer of a block's text at the diagram's size and its size, kept apart from `measurers` so that a block
    /// measured in the usual look copies the measurer alone.
    private let nodeText: Measurer
    private let nodeTextSize: CGFloat
    private let model: BlockModel?
    /// The diagram's classes by name, made when the first block that has classes or a style is met.
    private var classes: [String: BlockClassDefinition]?
    private var restyled: [BlockTextLook: Measurer] = [:]
    /// The appearance of each pair of class names and styles met, read once: blocks of one class share theirs.
    private var appearances: [BlockStyling: BlockAppearance] = [:]
    /// The appearance of a block with neither classes nor styles, most blocks: read once, without hashing its key.
    private var plainAppearance: BlockAppearance?

    private struct BlockStyling: Hashable {
        let classNames: [String]?
        let styles: [String]?
    }

    private struct BlockTextLook: Hashable {
        let fontSize: CGFloat
        let isBold: Bool
        let isItalic: Bool
    }

    init(measurers: BlockMeasurers<Measurer>, model: BlockModel? = nil) {
        self.measurers = measurers
        nodeText = measurers.nodeText
        nodeTextSize = measurers.nodeText.fontSize
        self.model = model
    }

    /// The appearance of `block` of the cache's model: the usual one, or that of its classes and style.
    mutating func appearance(of block: BlockRecord) -> BlockAppearance {
        guard let model else { return BlockAppearance() }
        guard block.hasStyling || !model.classes.isEmpty else { return BlockAppearance() }
        if classes == nil { classes = model.classDictionary() }
        return appearance(classNames: model.classNames(of: block), styles: block.styles.map(model.strings), classes: classes ?? [:])
    }

    /// The appearance of a block of `classNames` with `styles`, the diagram's classes being `classes` for every call.
    mutating func appearance(classNames: [String]?, styles: [String]?, classes: [String: BlockClassDefinition]) -> BlockAppearance {
        if classNames == nil, styles == nil {
            if let plainAppearance { return plainAppearance }
            let made = BlockAppearance(classNames: nil, styles: nil, classes: classes)
            plainAppearance = made
            return made
        }
        let styling = BlockStyling(classNames: classNames, styles: styles)
        if let known = appearances[styling] { return known }
        let made = BlockAppearance(classNames: classNames, styles: styles, classes: classes)
        appearances[styling] = made
        return made
    }

    mutating func measurer(for appearance: BlockAppearance) -> Measurer {
        let fontSize = appearance.fontSize ?? nodeTextSize
        guard fontSize != nodeTextSize || appearance.isBold || appearance.isItalic else { return nodeText }
        let look = BlockTextLook(fontSize: fontSize, isBold: appearance.isBold, isItalic: appearance.isItalic)
        if let known = restyled[look] { return known }
        let made = measurers.restyled(fontSize, appearance.isBold, appearance.isItalic)
        restyled[look] = made
        return made
    }
}
