/**
 * File: BlockGridLayout.swift
 * ---------------------------
 * Layer: Core
 * Description: Places a block diagram's blocks in their containers' grids as Pele's block layout does: each child in its
 *              cell, columns as wide as the widest block, rows as tall as the tallest, room left over shared out.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// A block in the grid, Pele's `Cell`: what the layout is given (its children, columns, span and the size its content
/// needs) and what it gives back (its cell, center and size).
struct BlockCell {
    /// The cells it holds, by their place in the layout's list.
    var childIndices: [Int] = []
    /// Its grid's width: a count, or -1 to put every child on one row.
    var columns = -1
    var span = 1
    var isSpace = false
    /// The height kept above a container's grid for its title.
    var titleHeight: CGFloat = 0
    /// The size its content needs: given for a leaf, worked out for a container.
    var neededWidth: CGFloat = 0
    var neededHeight: CGFloat = 0
    var column = 0
    var row = 0
    var columnCount = 0
    var rowHeights: [CGFloat] = []
    /// The extra room after each row or column, which a widened gap adds; zero where none is set.
    var rowGaps: [CGFloat] = []
    var columnGaps: [CGFloat] = []
    var center = CGPoint.zero
    var width: CGFloat = 0
    var height: CGFloat = 0
}

/// Why a block diagram's grid is not laid out.
public enum BlockLayoutError: Error, Equatable, Sendable {
    /// A container's `columns` is zero, or a number past what JavaScript holds, which Pele refuses as Mermaid does
    /// ("Columns must be an integer !== 0").
    case columnsNotAnInteger
}

/// Pele's `layout.ts` over a list of cells whose first is the root and whose every container comes before its children,
/// in the order they are reached breadth first: measured from the last to the first, so that a container is measured
/// after what it holds, then arranged from the first to the last.
enum BlockGridLayout {
    /// The most columns a block spans: Mermaid lets a block stick out of the grid; here it stops at a thousand, or at the
    /// last column.
    static let largestSpan = 1_000

    /// Lays `cells` out in place, `gap` between cells and inside each container's border, the root without a border at
    /// the origin; the root's size.
    static func layout(_ cells: inout [BlockCell], gap: CGFloat) throws(BlockLayoutError) -> CGSize {
        for index in cells.indices.reversed() where !cells[index].childIndices.isEmpty {
            try measure(&cells, at: index, gap: gap, inset: index == 0 ? 0 : gap)
        }
        cells[0].width = cells[0].neededWidth
        cells[0].height = cells[0].neededHeight
        cells[0].center = CGPoint(x: cells[0].width / 2, y: cells[0].height / 2)
        for index in cells.indices where !cells[index].childIndices.isEmpty {
            arrange(&cells, at: index, gap: gap, inset: index == 0 ? 0 : gap)
        }
        return CGSize(width: cells[0].width, height: cells[0].height)
    }

    /// Pele's `calculateBlockPosition`: the column and row of the cell at `position` in a grid of `columns`.
    static func position(columns: Int, position: Int) throws(BlockLayoutError) -> (column: Int, row: Int) {
        guard columns != 0 else { throw .columnsNotAnInteger }
        if columns < 0 { return (position, 0) }
        return (position % columns, position / columns)
    }

    /// Pele's `measure`: each child in its cell, the container sized. A row that holds a plain block is as tall as the
    /// tallest block of the container, as in Mermaid; a row of nothing but containers as tall as they need.
    private static func measure(_ cells: inout [BlockCell], at index: Int, gap: CGFloat, inset: CGFloat) throws(BlockLayoutError) {
        let columns = cells[index].columns
        var heights: [CGFloat] = []
        var position = 0
        var columnCount = 0
        var columnWidth: CGFloat = 0
        var tallest: CGFloat = 0
        for child in cells[index].childIndices {
            let (column, row) = try Self.position(columns: columns, position: position)
            var span = cells[child].span >= 1 ? min(cells[child].span, largestSpan) : 1
            if columns > 0, span > columns - column { span = columns - column }
            cells[child].span = span
            cells[child].column = column
            cells[child].row = row
            position += span
            columnCount = max(columnCount, column + span)
            if row == heights.count { heights.append(0) }
            if cells[child].childIndices.isEmpty {
                heights[row] = -1
            } else if heights[row] >= 0, cells[child].neededHeight > heights[row] {
                heights[row] = cells[child].neededHeight
            }
            guard !cells[child].isSpace else { continue }
            columnWidth = max(columnWidth, (cells[child].neededWidth - gap * CGFloat(span - 1)) / CGFloat(span))
            tallest = max(tallest, cells[child].neededHeight)
        }
        var height = CGFloat(heights.count - 1) * gap + cells[index].rowGaps.reduce(0, +)
        for row in heights.indices {
            if heights[row] < 0 { heights[row] = tallest }
            height += heights[row]
        }
        let gridWidth = CGFloat(columnCount) * columnWidth + CGFloat(columnCount - 1) * gap + cells[index].columnGaps.reduce(0, +)
        cells[index].columnCount = columnCount
        cells[index].rowHeights = heights
        cells[index].neededWidth = max(cells[index].neededWidth, gridWidth + 2 * inset)
        cells[index].neededHeight = height + 2 * inset + cells[index].titleHeight
    }

    /// Pele's `arrange`: each child given its cell, the room the container has beyond what it needs shared out in
    /// proportion to the rows' heights.
    private static func arrange(_ cells: inout [BlockCell], at index: Int, gap: CGFloat, inset: CGFloat) {
        let box = cells[index]
        let heights = box.rowHeights
        let columnWidth = (box.width - 2 * inset - CGFloat(box.columnCount - 1) * gap - box.columnGaps.reduce(0, +)) / CGFloat(box.columnCount)
        let room = box.height - 2 * inset - box.titleHeight - CGFloat(heights.count - 1) * gap - box.rowGaps.reduce(0, +)
        var offsets: [CGFloat] = []
        if !box.columnGaps.isEmpty {
            var sum: CGFloat = 0
            for column in 0..<box.columnCount {
                offsets.append(sum)
                sum += gapAt(box.columnGaps, column)
            }
        }
        let needed = heights.reduce(0, +)
        let scale = needed > 0 ? room / needed : 0
        let share = needed > 0 ? 0 : room / CGFloat(heights.count)
        let left = box.center.x - box.width / 2 + inset
        var top = box.center.y - box.height / 2 + inset + box.titleHeight
        var row = 0
        for child in box.childIndices {
            while row < cells[child].row {
                top += heights[row] * scale + share + gap + gapAt(box.rowGaps, row)
                row += 1
            }
            let column = cells[child].column
            let span = cells[child].span
            let before = gapAt(offsets, column)
            let width = columnWidth * CGFloat(span) + gap * CGFloat(span - 1) + gapAt(offsets, column + span - 1) - before
            cells[child].width = width
            cells[child].height = heights[row] * scale + share
            cells[child].center = CGPoint(x: left + CGFloat(column) * (columnWidth + gap) + before + width / 2, y: top + cells[child].height / 2)
        }
    }

    /// The gap at `index`, zero past the gaps set.
    static func gapAt(_ gaps: [CGFloat], _ index: Int) -> CGFloat {
        index >= 0 && index < gaps.count ? gaps[index] : 0
    }
}
