/**
 * File: BlockPlacement.swift
 * --------------------------
 * Layer: Core
 * Description: A block diagram's grid placed, as Pele's `place` does after each change of its gaps: the grid laid out
 *              from the blocks' own widths, each block's drawn size, and what edges and their text must stay clear of.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 26/11/2026
 */

import CoreGraphics

/// A rectangle an edge's text must not cover: a block's (by its cell) or a composite's title's.
struct BlockObstacle {
    let center: CGPoint
    let size: CGSize
    /// The cell of the block it is, nil for a title.
    let cellIndex: Int?
}

/// The grid and what is drawn on it, laid out again whenever a gap is widened.
struct BlockPlacement {
    var cells: [BlockCell]
    var views: [BlockView]
    let parentIndices: [Int]
    let gap: CGFloat
    /// Each cell's width before the layout: the layout keeps the widest a container has been, so each run starts again
    /// from these.
    private let neededWidths: [CGFloat]
    private(set) var contentSize = CGSize.zero
    /// Each cell's outline, as drawn.
    private(set) var outlines: [BlockOutline] = []
    /// The cells of the blocks and arrows, which edges are routed round.
    private(set) var obstacleIndices: [Int] = []
    /// The composites' titles.
    private(set) var titles: [BlockObstacle] = []

    init(_ views: BlockViews, gap: CGFloat) {
        cells = views.cells
        self.views = views.views
        parentIndices = views.parentIndices
        self.gap = gap
        neededWidths = views.cells.map(\.neededWidth)
    }

    /// Lays the grid out with the gaps set and works out each block's drawn size; the content's size.
    mutating func place() throws(BlockLayoutError) {
        for index in cells.indices { cells[index].neededWidth = neededWidths[index] }
        contentSize = try BlockGridLayout.layout(&cells, gap: gap)
        outlines.removeAll(keepingCapacity: true)
        outlines.reserveCapacity(cells.count)
        obstacleIndices.removeAll(keepingCapacity: true)
        obstacleIndices.reserveCapacity(cells.count)
        titles.removeAll(keepingCapacity: true)
        for index in cells.indices {
            // The cell's sizes and place read one by one: a copy of the cell would retain each of its lists.
            let cell = (neededWidth: cells[index].neededWidth, neededHeight: cells[index].neededHeight, width: cells[index].width,
                        height: cells[index].height, span: cells[index].span, center: cells[index].center, titleHeight: cells[index].titleHeight)
            let drawn: CGSize
            let form: BlockOutline.Form
            switch views[index].kind {
            case .leaf(let shape):
                if BlockViews.keepsItsOwnSize(shape) {
                    drawn = CGSize(width: cell.neededWidth, height: cell.neededHeight)
                } else {
                    drawn = CGSize(width: cell.width, height: BlockViews.onlyWidensItself(shape) ? cell.neededHeight : cell.height)
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

    /// Where a composite's title is drawn: centered, half its band and gap below its top, and 2 points more.
    func titleCenter(of index: Int) -> CGPoint {
        let cell = cells[index]
        return CGPoint(x: cell.center.x, y: cell.center.y - cell.height / 2 + (cell.titleHeight + gap) / 2 + 2)
    }

    /// The obstacles the blocks are, by their cells.
    var blockObstacles: [BlockObstacle] {
        obstacleIndices.map { index in BlockObstacle(center: outlines[index].center, size: outlines[index].size, cellIndex: index) }
    }

    /// Clears every gap a widening set.
    mutating func clearGaps() {
        for index in cells.indices {
            cells[index].rowGaps = []
            cells[index].columnGaps = []
        }
    }
}
