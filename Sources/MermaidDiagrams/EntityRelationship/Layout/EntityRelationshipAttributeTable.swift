/**
 * File: EntityRelationshipAttributeTable.swift
 * --------------------------------------------
 * Layer: Core
 * Description: An entity's attribute rows laid out as a table, each column as wide as its widest cell, each row as tall
 *              as its tallest cell, every cell's lines starting at its column's left edge.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.4
 * Date: 25/11/2026
 */

import CoreGraphics

/// An entity's attribute rows as a table, as Pele lays it out: each column as wide as its widest cell, a column no
/// cell fills taking no room, 16 points between columns, and the box's spare width shared between the columns; each
/// row as tall as its tallest cell, at least one line, and 9 points more. A cell's lines start at its column's left
/// edge, and the first line of every cell of a row sits on one baseline.
struct EntityRelationshipAttributeTable {
    static let columnGap: CGFloat = 16
    static let rowPadding: CGFloat = 9
    /// A row's cells: type, name, keys, comment.
    static let cellsPerRow = EntityRelationshipColumn.allCases.count
    /// The columns in order, made once rather than for each row.
    private static let columns = EntityRelationshipColumn.allCases

    /// The rows' cells, `cellsPerRow` of them for each row in column order.
    let cells: [DiagramTextBlock]
    let columnWidths: [CGFloat]
    let rowHeights: [CGFloat]
    /// The height of one line of the rows' text, which every cell's first line is centered on.
    let rowLineHeight: CGFloat

    init(cells: [DiagramTextBlock], rowLineHeight: CGFloat) {
        self.cells = cells
        self.rowLineHeight = rowLineHeight
        var columnWidths = [CGFloat](repeating: 0, count: Self.cellsPerRow)
        var rowHeights: [CGFloat] = []
        rowHeights.reserveCapacity(cells.count / Self.cellsPerRow)
        var rowStart = 0
        while rowStart + Self.cellsPerRow <= cells.count {
            // The tallest cell as `max()` of the row's heights finds it, 0 for none.
            var tallest = cells[rowStart].size.height
            for column in 0..<Self.cellsPerRow {
                let cell = cells[rowStart + column]
                columnWidths[column] = max(columnWidths[column], cell.size.width)
                tallest = max(tallest, cell.size.height)
            }
            rowHeights.append(max(rowLineHeight, tallest) + Self.rowPadding)
            rowStart += Self.cellsPerRow
        }
        self.columnWidths = columnWidths
        self.rowHeights = rowHeights
    }

    /// The width of the filled columns and the gaps between them.
    var filledWidth: CGFloat {
        var total: CGFloat = 0
        var filledCount = 0
        for width in columnWidths where width > 0 {
            total += width
            filledCount += 1
        }
        return total + CGFloat(max(filledCount - 1, 0)) * Self.columnGap
    }

    var height: CGFloat {
        rowHeights.reduce(0, +)
    }

    /// The rows placed in a box `width` wide from `top`, the columns starting `inset` from its left side, then moved by
    /// `firstOffset` and by `secondOffset`, each place found and moved as `translated(by:)` moves it.
    /// - Parameter rowFontSize: The size of the rows' text, whose baseline the smaller keys share.
    func rows(top: CGFloat, width: CGFloat, inset: CGFloat, rowFontSize: CGFloat, movedBy firstOffset: CGVector,
              then secondOffset: CGVector) -> [EntityRelationshipLayoutRow] {
        let lefts = columnLefts(width: width, inset: inset)
        var rowTop = top
        var rows: [EntityRelationshipLayoutRow] = []
        rows.reserveCapacity(rowHeights.count)
        for rowIndex in rowHeights.indices {
            var lineCount = 0
            for column in 0..<Self.cellsPerRow { lineCount += cells[rowIndex * Self.cellsPerRow + column].lineCount }
            var texts: [EntityRelationshipLayoutCellText] = []
            texts.reserveCapacity(lineCount)
            for (columnIndex, column) in Self.columns.enumerated() {
                let cell = cells[rowIndex * Self.cellsPerRow + columnIndex]
                let baselineShift = (rowFontSize - cell.fontSize) * DiagramTextDrawing.baselineShiftRatio
                let firstLineCenterY = rowTop + Self.rowPadding / 2 + rowLineHeight / 2 + baselineShift
                let left = lefts[columnIndex]
                // Each line as a block of its own that starts at the column's left edge, the first centered on the row's
                // first line and each next one a line lower.
                for index in 0..<cell.lineCount {
                    let center = CGPoint(x: left + cell.lineWidth(at: index) / 2, y: firstLineCenterY + CGFloat(index) * cell.lineHeight)
                    texts.append(EntityRelationshipLayoutCellText(column: column, text: cell.plainLineBlock(at: index, center: center
                        .translated(by: firstOffset).translated(by: secondOffset))))
                }
            }
            let frame = CGRect(x: 0, y: rowTop, width: width, height: rowHeights[rowIndex])
            rows.append(EntityRelationshipLayoutRow(frame: frame.offsetBy(dx: firstOffset.dx, dy: firstOffset.dy).offsetBy(dx: secondOffset.dx, dy: secondOffset.dy),
                                                    texts: texts))
            rowTop += rowHeights[rowIndex]
        }
        return rows
    }

    /// Each column's left edge: the spare width beyond the filled columns is shared between them.
    private func columnLefts(width: CGFloat, inset: CGFloat) -> [CGFloat] {
        var filledCount = 0
        for columnWidth in columnWidths where columnWidth > 0 { filledCount += 1 }
        let spare = filledCount > 0 ? (width - filledWidth - 2 * inset) / CGFloat(filledCount) : 0
        var left = inset
        return columnWidths.map { columnWidth in
            let columnLeft = left
            if columnWidth > 0 { left += columnWidth + spare + Self.columnGap }
            return columnLeft
        }
    }
}
