/**
 * File: BlockPlacementReferences.swift
 * ------------------------------------
 * Layer: Tests
 * Description: BlockViews, its measurer cache and BlockPlacement as they were at 0.6.1, kept as the references the faster
 *              ones must match number for number (TypeLayoutEquivalenceTests).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// The measuring and placing of 0.6.1 unchanged but for its comments: lists grown as they fill, the appearance of a
/// block without classes or styles looked up by its key, each cell copied whole to place it.
struct BlockViewsReference {
    private(set) var cells: [BlockCell] = []
    private(set) var views: [BlockView] = []
    private(set) var parentIndices: [Int] = []
    private(set) var cellIndicesByIdentifier: [String: Int] = [:]

    init<Measurer: DiagramTextMeasuring>(_ diagram: BlockDiagram, measurers: BlockMeasurers<Measurer>, gap: CGFloat, wrappingWidth: CGFloat,
                                         titleWidth: CGFloat) {
        var cache = BlockMeasurerCacheReference(measurers: measurers)
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

    private static func measured<Measurer: DiagramTextMeasuring>(_ block: BlockDiagramBlock, at blockIndex: Int, diagram: BlockDiagram,
                                                                 cache: inout BlockMeasurerCacheReference<Measurer>, gap: CGFloat, wrappingWidth: CGFloat,
                                                                 titleWidth: CGFloat) -> (cell: BlockCell, view: BlockView) {
        var cell = BlockCell()
        cell.span = block.kind == .space ? 1 : block.widthInColumns
        if block.kind == .space {
            cell.isSpace = true
            return (cell, BlockView(blockIndex: blockIndex, kind: .space, text: nil, appearance: BlockAppearance(), textOffset: .zero))
        }
        let appearance = cache.appearance(classNames: block.classNames, styles: block.styles, classes: diagram.classes)
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
            cell.neededHeight = shape == .cylinder ? max(size.height, textSize.height + 40) : size.height
            return (cell, BlockView(blockIndex: blockIndex, kind: .leaf(shape), text: text, appearance: appearance, textOffset: CGVector(dx: 0, dy: offset)))
        }
    }
}

struct BlockMeasurerCacheReference<Measurer: DiagramTextMeasuring> {
    let measurers: BlockMeasurers<Measurer>
    private var restyled: [BlockTextLook: Measurer] = [:]
    private var appearances: [BlockStyling: BlockAppearance] = [:]

    private struct BlockStyling: Hashable {
        let classNames: [String]?
        let styles: [String]?
    }

    private struct BlockTextLook: Hashable {
        let fontSize: CGFloat
        let isBold: Bool
        let isItalic: Bool
    }

    init(measurers: BlockMeasurers<Measurer>) {
        self.measurers = measurers
    }

    mutating func appearance(classNames: [String]?, styles: [String]?, classes: [String: BlockClassDefinition]) -> BlockAppearance {
        let styling = BlockStyling(classNames: classNames, styles: styles)
        if let known = appearances[styling] { return known }
        let made = BlockAppearance(classNames: classNames, styles: styles, classes: classes)
        appearances[styling] = made
        return made
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

struct BlockPlacementReference {
    var cells: [BlockCell]
    var views: [BlockView]
    let parentIndices: [Int]
    let gap: CGFloat
    private let neededWidths: [CGFloat]
    private(set) var contentSize = CGSize.zero
    private(set) var outlines: [BlockOutline] = []
    private(set) var obstacleIndices: [Int] = []
    private(set) var titles: [BlockObstacle] = []

    init(_ views: BlockViewsReference, gap: CGFloat) {
        cells = views.cells
        self.views = views.views
        parentIndices = views.parentIndices
        self.gap = gap
        neededWidths = views.cells.map(\.neededWidth)
    }

    mutating func place() throws(BlockLayoutError) {
        for index in cells.indices { cells[index].neededWidth = neededWidths[index] }
        contentSize = try BlockGridLayout.layout(&cells, gap: gap)
        outlines = []
        outlines.reserveCapacity(cells.count)
        obstacleIndices = []
        titles = []
        for index in cells.indices {
            let cell = cells[index]
            let drawn: CGSize
            let form: BlockOutline.Form
            switch views[index].kind {
            case .leaf(let shape):
                if BlockViews.keepsOwnSize.contains(shape) {
                    drawn = CGSize(width: cell.neededWidth, height: cell.neededHeight)
                } else {
                    drawn = CGSize(width: cell.width, height: BlockViews.onlyWidens.contains(shape) ? cell.neededHeight : cell.height)
                }
                if shape == .cylinder { views[index].textOffset.dy = FlowchartShapeGeometry.cylinderCapDepth(width: drawn.width) / 2 }
                form = shape == .circle || shape == .doubleCircle ? .round : shape == .diamond ? .diamond : .shape(shape)
                obstacleIndices.append(index)
            case .arrow(let directions):
                drawn = CGSize(width: cell.span > 1 ? cell.width : cell.neededWidth, height: cell.neededHeight)
                form = .arrow(directions.axis)
                obstacleIndices.append(index)
            case .composite, .space:
                drawn = CGSize(width: cell.width, height: cell.height)
                form = .box
                if let title = views[index].text, cell.titleHeight > 0 {
                    titles.append(BlockObstacle(center: titleCenter(of: index), size: title.size, cellIndex: nil))
                }
            }
            views[index].drawnSize = drawn
            outlines.append(BlockOutline(center: cell.center, size: drawn, form: form))
        }
    }

    func titleCenter(of index: Int) -> CGPoint {
        let cell = cells[index]
        return CGPoint(x: cell.center.x, y: cell.center.y - cell.height / 2 + (cell.titleHeight + gap) / 2 + 2)
    }

    var blockObstacles: [BlockObstacle] {
        obstacleIndices.map { index in BlockObstacle(center: outlines[index].center, size: outlines[index].size, cellIndex: index) }
    }

    mutating func clearGaps() {
        for index in cells.indices {
            cells[index].rowGaps = []
            cells[index].columnGaps = []
        }
    }
}
