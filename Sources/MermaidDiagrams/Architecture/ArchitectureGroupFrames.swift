/**
 * File: ArchitectureGroupFrames.swift
 * -----------------------------------
 * Layer: Core
 * Description: The room round an architecture diagram's groups as Pele's renderer keeps it, on the rows and columns at
 *              their edges, a group sharing an edge with one inside it standing further out, and where each column, row
 *              and group then lies.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// Each group's columns and rows, its title's band, its insets, and the columns' and rows' places once the insets and
/// gaps are kept.
struct ArchitectureGroupFrames {
    let firstColumns: [Int]
    let lastColumns: [Int]
    let firstRows: [Int]
    let lastRows: [Int]
    let titles: [DiagramTextBlock?]
    /// The width and height of each group's head: its icon badge and its title.
    let headWidths: [CGFloat]
    let headHeights: [CGFloat]
    /// The side of a group's icon: five quarters of the text's size.
    let badge: CGFloat
    private(set) var insets: [(left: CGFloat, right: CGFloat, top: CGFloat, bottom: CGFloat)]
    private(set) var columnLefts: [CGFloat] = []
    private(set) var rowTops: [CGFloat] = []
    private(set) var innerSize = CGSize.zero
    let sizes: ArchitectureGridSizes

    init<Measurer: DiagramTextMeasuring>(_ diagram: ArchitectureDiagram, grid: ArchitectureGrid, sizes: ArchitectureGridSizes,
                                         measurers: ArchitectureMeasurers<Measurer>, padding: CGFloat, badge: CGFloat, titleWidth: CGFloat) {
        self.sizes = sizes
        self.badge = badge
        let groups = diagram.groups.indices
        firstColumns = groups.map { group in sizes.columnOfGridColumn[grid.groupColumns[group]] ?? 0 }
        lastColumns = groups.map { group in sizes.columnOfGridColumn[grid.groupColumns[group] + grid.groupColumnCounts[group] - 1] ?? 0 }
        firstRows = groups.map { group in sizes.rowOfGridRow[grid.groupRows[group]] ?? 0 }
        lastRows = groups.map { group in sizes.rowOfGridRow[grid.groupRows[group] + grid.groupRowCounts[group] - 1] ?? 0 }
        let titles = diagram.groups.map { group in PlaneMapLabel.block(group.title, measurer: measurers.titleText, maximumWidth: titleWidth, form: .markdown) }
        self.titles = titles
        headWidths = groups.map { group in
            let titleWidth = titles[group]?.size.width ?? 0
            let icon = diagram.groups[group].icon == nil ? 0 : badge
            return titleWidth + icon + (titleWidth > 0 && icon > 0 ? 6 : 0)
        }
        headHeights = groups.map { group in max(titles[group]?.size.height ?? 0, diagram.groups[group].icon == nil ? 0 : badge) }
        insets = Array(repeating: (0, 0, 0, 0), count: diagram.groups.count)
        settleInsets(diagram, padding: padding)
    }

    /// Children come after their parents, so walking backwards settles every group before the one that holds it.
    private mutating func settleInsets(_ diagram: ArchitectureDiagram, padding: CGFloat) {
        var columnLeftRooms = [CGFloat](repeating: 0, count: sizes.columnWidths.count)
        var columnRightRooms = columnLeftRooms
        var rowTopRooms = [CGFloat](repeating: 0, count: sizes.rowHeights.count)
        var rowBottomRooms = rowTopRooms
        for group in diagram.groups.indices.reversed() {
            let left = padding + insets[group].left
            var right = padding + insets[group].right
            let top = (headHeights[group] > 0 ? max(padding, headHeights[group] + 12) : padding) + insets[group].top
            let bottom = padding + insets[group].bottom
            if headWidths[group] > 0 {
                var inner = left + right
                for column in firstColumns[group]...lastColumns[group] {
                    inner += sizes.columnWidths[column]
                    if column < lastColumns[group] { inner += columnRightRooms[column] + sizes.gapsAfterColumns[column] + columnLeftRooms[column + 1] }
                }
                if headWidths[group] + 20 > inner { right += (headWidths[group] + 20 - inner).rounded(.up) }
            }
            insets[group] = (left, right, top, bottom)
            columnLeftRooms[firstColumns[group]] = max(columnLeftRooms[firstColumns[group]], left)
            columnRightRooms[lastColumns[group]] = max(columnRightRooms[lastColumns[group]], right)
            rowTopRooms[firstRows[group]] = max(rowTopRooms[firstRows[group]], top)
            rowBottomRooms[lastRows[group]] = max(rowBottomRooms[lastRows[group]], bottom)
            guard let parent = diagram.groups[group].parentIndex else { continue }
            if firstColumns[parent] == firstColumns[group] { insets[parent].left = max(insets[parent].left, left) }
            if lastColumns[parent] == lastColumns[group] { insets[parent].right = max(insets[parent].right, right) }
            if firstRows[parent] == firstRows[group] { insets[parent].top = max(insets[parent].top, top) }
            if lastRows[parent] == lastRows[group] { insets[parent].bottom = max(insets[parent].bottom, bottom) }
        }
        place(columnLeftRooms, columnRightRooms, rowTopRooms, rowBottomRooms)
    }

    private mutating func place(_ columnLeftRooms: [CGFloat], _ columnRightRooms: [CGFloat], _ rowTopRooms: [CGFloat], _ rowBottomRooms: [CGFloat]) {
        var width: CGFloat = 0
        for column in sizes.columnWidths.indices {
            columnLefts.append(width + columnLeftRooms[column])
            width = columnLefts[column] + sizes.columnWidths[column] + columnRightRooms[column]
                + (column < sizes.columnWidths.count - 1 ? sizes.gapsAfterColumns[column] : 0)
        }
        var height: CGFloat = 0
        for row in sizes.rowHeights.indices {
            rowTops.append(height + rowTopRooms[row])
            height = rowTops[row] + sizes.rowHeights[row] + rowBottomRooms[row] + (row < sizes.rowHeights.count - 1 ? sizes.gapsAfterRows[row] : 0)
        }
        innerSize = CGSize(width: width, height: height)
    }

    /// A group's box.
    func frame(of group: Int) -> CGRect {
        let left = columnLefts[firstColumns[group]] - insets[group].left
        let right = columnLefts[lastColumns[group]] + sizes.columnWidths[lastColumns[group]] + insets[group].right
        let top = rowTops[firstRows[group]] - insets[group].top
        let bottom = rowTops[lastRows[group]] + sizes.rowHeights[lastRows[group]] + insets[group].bottom
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    /// The middle of a node's column, and the top of its row.
    func nodeAnchor(_ node: Int) -> CGPoint {
        let column = sizes.nodeColumns[node]
        return CGPoint(x: columnLefts[column] + sizes.columnWidths[column] / 2, y: rowTops[sizes.nodeRows[node]])
    }
}
