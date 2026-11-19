/**
 * File: ArchitectureGridSizes.swift
 * ---------------------------------
 * Layer: Core
 * Description: Measures an architecture diagram's grid as Pele's renderer does: each service's box (its icon square and
 *              title), the columns and rows in use and their sizes, and the gaps an edge's text widens.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// The measurers of an architecture diagram's text, made at the sizes its options set: a service's and a group's title,
/// an edge's at seven eighths, the diagram's title in bold, and an icon's text at three quarters.
struct ArchitectureMeasurers<Measurer: DiagramTextMeasuring> {
    let titleText: Measurer
    let edgeText: Measurer
    let diagramTitleText: Measurer
    let iconText: Measurer
}

/// Pele's sizes of the grid: the columns and rows that hold a node or an empty group, ranked so that empty ones take no
/// room, each as wide and tall as what it holds, and the gaps after them.
struct ArchitectureGridSizes {
    let nodeTitles: [DiagramTextBlock?]
    let boxSizes: [CGSize]
    let nodeColumns: [Int]
    let nodeRows: [Int]
    let columnOfGridColumn: [Int: Int]
    let rowOfGridRow: [Int: Int]
    var columnWidths: [CGFloat]
    var rowHeights: [CGFloat]
    var gapsAfterColumns: [CGFloat]
    var gapsAfterRows: [CGFloat]
    let edgeTitles: [DiagramTextBlock?]

    static let titleGap: CGFloat = 4

    init<Measurer: DiagramTextMeasuring>(_ diagram: ArchitectureDiagram, grid: ArchitectureGrid, measurers: ArchitectureMeasurers<Measurer>,
                                         iconSize: CGFloat, isTight: Bool) {
        let wrappingWidth = isTight ? max(iconSize, 64) : max(iconSize * 2.25, 96)
        nodeTitles = diagram.nodes.map { node in
            node.kind == .service ? PlaneMapLabel.block(node.title, measurer: measurers.titleText, maximumWidth: wrappingWidth, form: .markdown) : nil
        }
        boxSizes = nodeTitles.map { title in
            CGSize(width: max(iconSize, 2 * ((title?.size.width ?? 0) / 2).rounded(.up)),
                   height: iconSize + (title.map { block in Self.titleGap + block.size.height } ?? 0))
        }
        let emptyGroups = grid.groupIsEmpty.indices.filter { group in grid.groupIsEmpty[group] }
        columnOfGridColumn = Self.ranks(grid.nodeColumns + emptyGroups.map { group in grid.groupColumns[group] })
        rowOfGridRow = Self.ranks(grid.nodeRows + emptyGroups.map { group in grid.groupRows[group] })
        let gap = isTight ? 24 : max(40, (iconSize * 0.75).rounded())
        columnWidths = [CGFloat](repeating: 0, count: columnOfGridColumn.count)
        rowHeights = [CGFloat](repeating: 0, count: rowOfGridRow.count)
        gapsAfterColumns = [CGFloat](repeating: gap, count: columnOfGridColumn.count)
        gapsAfterRows = [CGFloat](repeating: gap, count: rowOfGridRow.count)
        let columnRanks = columnOfGridColumn
        let rowRanks = rowOfGridRow
        nodeColumns = grid.nodeColumns.map { column in columnRanks[column] ?? 0 }
        nodeRows = grid.nodeRows.map { row in rowRanks[row] ?? 0 }
        for node in diagram.nodes.indices {
            columnWidths[nodeColumns[node]] = max(columnWidths[nodeColumns[node]], boxSizes[node].width)
            rowHeights[nodeRows[node]] = max(rowHeights[nodeRows[node]], boxSizes[node].height)
        }
        for group in emptyGroups {
            let column = columnOfGridColumn[grid.groupColumns[group]] ?? 0
            let row = rowOfGridRow[grid.groupRows[group]] ?? 0
            columnWidths[column] = max(columnWidths[column], iconSize)
            rowHeights[row] = max(rowHeights[row], iconSize / 2)
        }
        edgeTitles = diagram.edges.map { edge in PlaneMapLabel.block(edge.title, measurer: measurers.edgeText, maximumWidth: 160, form: .markdown) }
        widenForEdgeTitles(diagram)
    }

    /// An edge's text needs the gap its edge crosses to hold it: the gap after the first of its columns, or its column
    /// and the gap after the first of its rows when it runs down one column.
    private mutating func widenForEdgeTitles(_ diagram: ArchitectureDiagram) {
        for (edge, title) in zip(diagram.edges, edgeTitles) {
            guard let title, title.size.width > 0 else { continue }
            let source = edge.sourceIndex
            let target = edge.targetIndex
            if nodeColumns[source] != nodeColumns[target] {
                let column = min(nodeColumns[source], nodeColumns[target])
                gapsAfterColumns[column] = max(gapsAfterColumns[column], title.size.width.rounded(.up) + 28)
            } else {
                columnWidths[nodeColumns[source]] = max(columnWidths[nodeColumns[source]], 2 * (title.size.width / 2).rounded(.up) + 8)
                if nodeRows[source] != nodeRows[target] {
                    let row = min(nodeRows[source], nodeRows[target])
                    gapsAfterRows[row] = max(gapsAfterRows[row], title.size.height.rounded(.up) + 24)
                }
            }
        }
    }

    /// Pele's `rank`: each value in use mapped to its place among them in order.
    private static func ranks(_ values: [Int]) -> [Int: Int] {
        var ranks: [Int: Int] = [:]
        for value in values.sorted() where ranks[value] == nil { ranks[value] = ranks.count }
        return ranks
    }
}
