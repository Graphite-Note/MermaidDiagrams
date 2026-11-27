/**
 * File: EntityRelationshipAttributeTable.swift
 * --------------------------------------------
 * Layer: Core
 * Description: An entity's attribute rows laid out as a table, each column as wide as its widest cell, each row as tall
 *              as its tallest cell, every cell's lines starting at its column's left edge, the rows and their lines
 *              written into the layout's lists when the box is placed.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.5
 * Date: 26/11/2026
 */

import CoreGraphics

/// An entity's attribute rows as a table, as Pele lays it out: each column as wide as its widest cell, a column no
/// cell fills taking no room, 16 points between columns, and the box's spare width shared between the columns; each
/// row as tall as its tallest cell, at least one line, and 9 points more. A cell's lines start at its column's left
/// edge, and the first line of every cell of a row sits on one baseline. Rows are added as their cells are measured,
/// their widths and heights taken in the order 0.7.0 took them.
struct EntityRelationshipAttributeTable {
    static let columnGap: CGFloat = 16
    static let rowPadding: CGFloat = 9
    /// A row's cells: type, name, keys, comment.
    static let cellsPerRow = EntityRelationshipColumn.allCases.count

    /// The height of one line of the rows' text, which every cell's first line is centered on.
    let rowLineHeight: CGFloat
    private(set) var columnWidths = EntityRelationshipColumnWidths()
    /// The rows' heights added up from the first.
    private(set) var height: CGFloat = 0

    init(rowLineHeight: CGFloat) {
        self.rowLineHeight = rowLineHeight
    }

    /// A row of the four cells, in column order; its height.
    mutating func addRow(_ type: DiagramMeasuredText, _ name: DiagramMeasuredText, _ keys: DiagramMeasuredText, _ comment: DiagramMeasuredText) -> CGFloat {
        // The tallest cell as `max()` of the row's heights finds it, 0 for none.
        var tallest = type.size.height
        columnWidths.type = max(columnWidths.type, type.size.width)
        tallest = max(tallest, type.size.height)
        columnWidths.name = max(columnWidths.name, name.size.width)
        tallest = max(tallest, name.size.height)
        columnWidths.keys = max(columnWidths.keys, keys.size.width)
        tallest = max(tallest, keys.size.height)
        columnWidths.comment = max(columnWidths.comment, comment.size.width)
        tallest = max(tallest, comment.size.height)
        let rowHeight = max(rowLineHeight, tallest) + Self.rowPadding
        height += rowHeight
        return rowHeight
    }

    /// The width of the filled columns and the gaps between them.
    var filledWidth: CGFloat {
        Self.filledWidth(of: columnWidths)
    }

    static func filledWidth(of columnWidths: EntityRelationshipColumnWidths) -> CGFloat {
        var total: CGFloat = 0
        var filledCount = 0
        for column in 0..<cellsPerRow where columnWidths[column] > 0 {
            total += columnWidths[column]
            filledCount += 1
        }
        return total + CGFloat(max(filledCount - 1, 0)) * columnGap
    }

    /// `box`'s rows placed in it from `box.headerHeight`, the columns starting `inset` from its left side, then moved by
    /// `firstOffset` and by `secondOffset`, each place found and moved as `translated(by:)` moves it: each row appended to
    /// `rows`, each line of its cells to `cellTexts`, a block of its own starting at its column's left edge.
    static func placeRows(of box: EntityRelationshipMeasuredBox, inset: CGFloat, measured: EntityRelationshipMeasurement, movedBy firstOffset: CGVector,
                          then secondOffset: CGVector, rows: inout [EntityRelationshipPlacedRow], cellTexts: inout [EntityRelationshipPlacedCell]) {
        let lefts = columnLefts(of: box.columnWidths, width: box.size.width, inset: inset)
        var rowTop = box.headerHeight
        for row in box.rowIndices {
            let firstCellText = cellTexts.count
            for column in 0..<cellsPerRow {
                let cell = measured.cells[row * cellsPerRow + column]
                let baselineShift = (box.rowFontSize - cell.fontSize) * DiagramTextDrawing.baselineShiftRatio
                let firstLineCenterY = rowTop + rowPadding / 2 + box.rowLineHeight / 2 + baselineShift
                let left = lefts[column]
                // Each line as a text of its own that starts at the column's left edge, the first centered on the row's
                // first line and each next one a line lower.
                for index in 0..<Int(cell.lineCount) {
                    let lineWidth = measured.lines[Int(cell.firstLine) + index].width
                    let center = CGPoint(x: left + lineWidth / 2, y: firstLineCenterY + CGFloat(index) * cell.lineHeight)
                    let line = DiagramMeasuredText(firstLine: cell.firstLine + Int32(index), lineCount: 1, width: lineWidth, height: cell.lineHeight,
                                                   lineHeight: cell.lineHeight, fontSize: cell.fontSize,
                                                   center: center.translated(by: firstOffset).translated(by: secondOffset))
                    cellTexts.append(EntityRelationshipPlacedCell(column: Int8(column), text: line))
                }
            }
            let rowHeight = measured.rowHeights[row]
            let frame = CGRect(x: 0, y: rowTop, width: box.size.width, height: rowHeight)
            rows.append(EntityRelationshipPlacedRow(frame: frame.offsetBy(dx: firstOffset.dx, dy: firstOffset.dy).offsetBy(dx: secondOffset.dx, dy: secondOffset.dy),
                                                    firstCellText: Int32(firstCellText), cellTextCount: Int32(cellTexts.count - firstCellText)))
            rowTop += rowHeight
        }
    }

    /// Each column's left edge: the spare width beyond the filled columns is shared between them.
    private static func columnLefts(of columnWidths: EntityRelationshipColumnWidths, width: CGFloat, inset: CGFloat) -> EntityRelationshipColumnWidths {
        var filledCount = 0
        for column in 0..<cellsPerRow where columnWidths[column] > 0 { filledCount += 1 }
        let spare = filledCount > 0 ? (width - filledWidth(of: columnWidths) - 2 * inset) / CGFloat(filledCount) : 0
        var left = inset
        var lefts = EntityRelationshipColumnWidths()
        for column in 0..<cellsPerRow {
            lefts[column] = left
            if columnWidths[column] > 0 { left += columnWidths[column] + spare + columnGap }
        }
        return lefts
    }
}
