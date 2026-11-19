/**
 * File: BlockViews.swift
 * ----------------------
 * Layer: Core
 * Description: Measures a block diagram's blocks as Pele's block renderer does before it lays them out: each block's
 *              text, its shape's or arrow's size around it, a composite's title and the room around it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
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
    /// The cell of each block drawn (not a space), by its identifier.
    private(set) var cellIndicesByIdentifier: [String: Int] = [:]

    /// Shapes kept at their own size in a larger cell, where the others stretch to fill it.
    static let keepsOwnSize: Set<FlowchartNodeShape> = [.circle, .doubleCircle, .diamond]
    /// Shapes that only widen, as their slants and curves are set by their height.
    static let onlyWidens: Set<FlowchartNodeShape> = [.stadium, .hexagon, .asymmetric, .leanRight, .leanLeft, .trapezoid, .invertedTrapezoid]

    init<Measurer: DiagramTextMeasuring>(_ diagram: BlockDiagram, measurers: BlockMeasurers<Measurer>, gap: CGFloat, wrappingWidth: CGFloat,
                                         titleWidth: CGFloat) {
        var cache = BlockMeasurerCache(measurers: measurers)
        var queue = [(block: BlockDiagram.rootIndex, parent: -1)]
        var next = 0
        while next < queue.count {
            let (blockIndex, parent) = queue[next]
            next += 1
            let block = diagram.blocks[blockIndex]
            let measured = Self.measured(block, at: blockIndex, diagram: diagram, cache: &cache, gap: gap, wrappingWidth: wrappingWidth,
                                         titleWidth: titleWidth)
            var cell = measured.cell
            if blockIndex == BlockDiagram.rootIndex { (cell.neededWidth, cell.neededHeight) = (0, 0) }
            let index = cells.count
            if parent >= 0 { cells[parent].childIndices.append(index) }
            cells.append(cell)
            views.append(measured.view)
            parentIndices.append(parent)
            if measured.view.kind != .space { cellIndicesByIdentifier[block.identifier] = index }
            if measured.view.kind == .composite { queue += block.childIndices.map { child in (child, index) } }
        }
    }

    /// A block's cell and view, measured.
    private static func measured<Measurer: DiagramTextMeasuring>(_ block: BlockDiagramBlock, at blockIndex: Int, diagram: BlockDiagram,
                                                                 cache: inout BlockMeasurerCache<Measurer>, gap: CGFloat, wrappingWidth: CGFloat,
                                                                 titleWidth: CGFloat) -> (cell: BlockCell, view: BlockView) {
        var cell = BlockCell()
        cell.span = block.kind == .space ? 1 : block.widthInColumns
        if block.kind == .space {
            cell.isSpace = true
            return (cell, BlockView(blockIndex: blockIndex, kind: .space, text: nil, appearance: BlockAppearance(), textOffset: .zero))
        }
        let appearance = BlockAppearance(classNames: block.classNames, styles: block.styles, classes: diagram.classes)
        let measurer = cache.measurer(for: appearance)
        switch block.kind {
        case .composite:
            cell.columns = block.columns ?? -1
            let title = PlaneMapLabel.block(block.label, measurer: measurer, maximumWidth: titleWidth)
            let titleHeight = title.map { text in text.size.height + 4 } ?? 0
            cell.titleHeight = titleHeight
            cell.neededWidth = (title?.size.width ?? 0) + 2 * gap
            cell.neededHeight = titleHeight + 2 * gap
            return (cell, BlockView(blockIndex: blockIndex, kind: .composite, text: title, appearance: appearance, textOffset: .zero))
        case .arrow:
            let text = PlaneMapLabel.block(block.label, measurer: measurer, maximumWidth: wrappingWidth)
            let directions = BlockArrowDirections(written: block.directions)
            let isBlank = text?.lines.allSatisfy { line in line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? true
            let (size, offset) = BlockArrowShape.size(of: directions, textSize: isBlank ? .zero : text?.size ?? .zero)
            (cell.neededWidth, cell.neededHeight) = (size.width, size.height)
            return (cell, BlockView(blockIndex: blockIndex, kind: .arrow(directions), text: text, appearance: appearance, textOffset: offset))
        default:
            let shape = if case .shape(let shape) = block.kind { shape } else { FlowchartNodeShape.rectangle }
            let text = PlaneMapLabel.block(block.label, measurer: measurer, maximumWidth: wrappingWidth)
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
    private var restyled: [BlockTextLook: Measurer] = [:]

    private struct BlockTextLook: Hashable {
        let fontSize: CGFloat
        let isBold: Bool
        let isItalic: Bool
    }

    init(measurers: BlockMeasurers<Measurer>) {
        self.measurers = measurers
    }

    mutating func measurer(for appearance: BlockAppearance) -> Measurer {
        let fontSize = appearance.fontSize ?? measurers.nodeText.fontSize
        guard fontSize != measurers.nodeText.fontSize || appearance.isBold || appearance.isItalic else { return measurers.nodeText }
        let look = BlockTextLook(fontSize: fontSize, isBold: appearance.isBold, isItalic: appearance.isItalic)
        if let known = restyled[look] { return known }
        let made = measurers.restyled(fontSize, appearance.isBold, appearance.isItalic)
        restyled[look] = made
        return made
    }
}
