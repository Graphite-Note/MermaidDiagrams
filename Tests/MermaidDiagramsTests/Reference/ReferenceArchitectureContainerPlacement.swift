/**
 * File: ReferenceArchitectureContainerPlacement.swift
 * ---------------------------------------------------
 * Layer: Tests
 * Description: 0.7.0's placement of each container's items (Pele's layout and slide), frozen as main 2a0cc65 placed them, for
 *              the frozen grid placement.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import Foundation
@testable import MermaidDiagrams

extension ReferenceArchitectureGridPlacement {
    /// Pele's `layout(c)`: each part of the container from its first unplaced item, then the parts side by side; a
    /// group's size in cells is what its parts take.
    mutating func layOut(_ container: Int) {
        let items = children[container]
        guard !items.isEmpty else { return }
        order = []
        var starts: [Int] = []
        for start in items where !isPlaced[start] {
            partStart = order.count
            starts.append(partStart)
            cells = [:]
            largeItems = []
            reaches = [:]
            put(start, column: 0, row: 0)
            followLinks()
        }
        starts.append(order.count)
        arrangeParts(starts, of: container)
    }

    /// Alignments are followed as soon as a node is placed, ahead of any edge.
    private mutating func followLinks() {
        var hintAt = partStart
        var edgeAt = partStart
        var linkAt = 0
        while true {
            if hintAt < order.count {
                let from = order[hintAt]
                hintAt += 1
                for link in links.hintLinksByItem[from] ?? [] { follow(from: from, link: link) }
                continue
            }
            guard edgeAt < order.count else { return }
            let list = links.edgeLinksByItem[order[edgeAt]] ?? []
            guard linkAt < list.count else {
                edgeAt += 1
                linkAt = 0
                continue
            }
            follow(from: order[edgeAt], link: list[linkAt])
            linkAt += 1
        }
    }

    /// The offset of `node` inside `item`, which holds it.
    func anchor(_ node: Int, in item: Int) -> (x: Int, y: Int) {
        var offset = (x: 0, y: 0)
        var current = node
        while current != item {
            offset.x += x[current]
            offset.y += y[current]
            current = nodeCount + parents[current]
        }
        return offset
    }

    /// Pele's `follow`: the link's other end placed beside `from` as its sides ask, slid clear of what is taken.
    private mutating func follow(from: Int, link index: Int) {
        let link = links.all[index]
        let isForward = link.firstItem == from
        let to = isForward ? link.secondItem : link.firstItem
        guard !isPlaced[to] else { return }
        let leaving = isForward ? link.firstSide : link.secondSide
        let entering = isForward ? link.secondSide : link.firstSide
        var (column, row, step) = cellBeside(from, to: to, link: link, isForward: isForward)
        let isFacing = leaving.step.dx + entering.step.dx == 0 && leaving.step.dy + entering.step.dy == 0
        if isFacing {
            if let middle = middleOfFacing(to, leaving: leaving, entering: entering, alongRows: step.dx != 0) {
                if step.dx != 0 { row = middle } else { column = middle }
            }
            // Taken: moved sideways, to whichever side is nearer, so that the edge can still leave straight.
            let across = (dx: step.dx == 0 ? 1 : 0, dy: step.dx == 0 ? 0 : 1)
            let forth = slide(column, row, widths[to], heights[to], across.dx, across.dy)
            let back = forth == 0 ? 0 : slide(column, row, widths[to], heights[to], -across.dx, -across.dy)
            let near = forth <= back ? forth : -back
            column += across.dx * near
            row += across.dy * near
        } else {
            let far = slide(column, row, widths[to], heights[to], step.dx, step.dy)
            column += step.dx * far
            row += step.dy * far
        }
        put(to, column: column, row: row)
    }

    /// The cell `to` would take beside `from` before sliding, and the step it is put along: out of the side the link
    /// leaves; across it for like sides, as the edge loops round; with one step back from the side it enters for a bend.
    private func cellBeside(_ from: Int, to: Int, link: ReferenceArchitectureGridLink, isForward: Bool) -> (column: Int, row: Int, step: (dx: Int, dy: Int)) {
        let leaving = isForward ? link.firstSide : link.secondSide
        let entering = isForward ? link.secondSide : link.firstSide
        let fromAnchor = anchor(isForward ? link.firstNode : link.secondNode, in: from)
        let toAnchor = anchor(isForward ? link.secondNode : link.firstNode, in: to)
        var step = leaving.step
        var shift = (dx: 0, dy: 0)
        let isFacing = leaving.step.dx + entering.step.dx == 0 && leaving.step.dy + entering.step.dy == 0
        if leaving == entering {
            step.dx = leaving.step.dx == 0 ? 1 : 0
            step.dy = 1 - step.dx
        } else if !isFacing {
            shift = (-entering.step.dx, -entering.step.dy)
        }
        if step.dx != 0 {
            return (step.dx > 0 ? x[from] + widths[from] : x[from] - widths[to], y[from] + fromAnchor.y + shift.dy - toAnchor.y, step)
        }
        return (x[from] + fromAnchor.x + shift.dx - toAnchor.x, step.dy > 0 ? y[from] + heights[from] : y[from] - heights[to], step)
    }

    /// When several placed items reach `to` through the same pair of sides, the middle of the places they ask for, so
    /// that it lines up with the middle one and not with whichever was visited first; nil for fewer than two.
    private func middleOfFacing(_ to: Int, leaving: ArchitectureSide, entering: ArchitectureSide, alongRows: Bool) -> Int? {
        guard let list = links.edgeLinksByItem[to], list.count > 1 else { return nil }
        var wanted: [Int] = []
        for index in list {
            let link = links.all[index]
            let toIsSecond = link.secondItem == to
            let other = toIsSecond ? link.firstItem : link.secondItem
            guard isPlaced[other], (toIsSecond ? link.firstSide : link.secondSide) == leaving, (toIsSecond ? link.secondSide : link.firstSide) == entering else {
                continue
            }
            let otherAnchor = anchor(toIsSecond ? link.firstNode : link.secondNode, in: other)
            let at = alongRows ? y[other] + otherAnchor.y : x[other] + otherAnchor.x
            let toAnchor = anchor(toIsSecond ? link.secondNode : link.firstNode, in: to)
            wanted.append(at - (alongRows ? toAnchor.y : toAnchor.x))
        }
        guard wanted.count > 1 else { return nil }
        wanted.sort()
        return wanted[(wanted.count - 1) >> 1]
    }

    mutating func put(_ item: Int, column: Int, row: Int) {
        x[item] = column
        y[item] = row
        isPlaced[item] = true
        order.append(item)
        guard widths[item] * heights[item] <= Self.smallBlockCells else {
            largeItems.append(item)
            return
        }
        for cellRow in row..<(row + heights[item]) {
            for cellColumn in column..<(column + widths[item]) { cells[Self.cellKey(cellColumn, cellRow)] = item }
        }
    }

    private static func cellKey(_ column: Int, _ row: Int) -> Int {
        (column + (1 << 25)) * (1 << 26) + row + (1 << 25)
    }

    private func overlaps(_ item: Int, _ column: Int, _ row: Int, _ width: Int, _ height: Int) -> Bool {
        x[item] < column + width && column < x[item] + widths[item] && y[item] < row + height && row < y[item] + heights[item]
    }

    /// The item a block at `column`, `row` of the size given would overlap, or nil.
    private func collision(_ column: Int, _ row: Int, _ width: Int, _ height: Int) -> Int? {
        if width * height > Self.smallBlockCells {
            return order[partStart...].first { item in overlaps(item, column, row, width, height) }
        }
        for cellRow in row..<(row + height) {
            for cellColumn in column..<(column + width) {
                if let hit = cells[Self.cellKey(cellColumn, cellRow)] { return hit }
            }
        }
        return largeItems.first { item in overlaps(item, column, row, width, height) }
    }

    /// Pele's `slide`: how far a block must move along a step to be clear, each step past what it hit, kept, as a later
    /// block starting from the same place cannot stop sooner.
    private mutating func slide(_ column: Int, _ row: Int, _ width: Int, _ height: Int, _ stepX: Int, _ stepY: Int) -> Int {
        let key = ReferenceArchitectureSlideKey(column: column, row: row, width: width, height: height, stepX: stepX, stepY: stepY)
        var distance = reaches[key] ?? 0
        while let hit = collision(column + distance * stepX, row + distance * stepY, width, height) {
            if stepX > 0 {
                distance = x[hit] + widths[hit] - column
            } else if stepX < 0 {
                distance = column + width - x[hit]
            } else if stepY > 0 {
                distance = y[hit] + heights[hit] - row
            } else {
                distance = row + height - y[hit]
            }
        }
        reaches[key] = distance
        return distance
    }

    /// The unconnected parts side by side, wrapping into rows no wider than the widest part or the square root of twice
    /// their area.
    private mutating func arrangeParts(_ starts: [Int], of container: Int) {
        var bounds: [(minX: Int, minY: Int, width: Int, height: Int)] = []
        var area = 0
        var widest = 0
        for part in 0..<(starts.count - 1) {
            let members = order[starts[part]..<starts[part + 1]]
            let minX = members.map { item in x[item] }.min() ?? 0
            let minY = members.map { item in y[item] }.min() ?? 0
            let maxX = members.map { item in x[item] + widths[item] }.max() ?? 0
            let maxY = members.map { item in y[item] + heights[item] }.max() ?? 0
            bounds.append((minX, minY, maxX - minX, maxY - minY))
            area += (maxX - minX) * (maxY - minY)
            widest = max(widest, maxX - minX)
        }
        let limit = max(widest, Int((Double(area) * 2).squareRoot().rounded(.up)))
        var column = 0
        var row = 0
        var shelf = 0
        var width = 0
        for (part, bound) in bounds.enumerated() {
            if column > 0, column + bound.width > limit {
                row += shelf
                column = 0
                shelf = 0
            }
            for item in order[starts[part]..<starts[part + 1]] {
                x[item] += column - bound.minX
                y[item] += row - bound.minY
            }
            column += bound.width
            shelf = max(shelf, bound.height)
            width = max(width, column)
        }
        if container < groupCount {
            widths[nodeCount + container] = width
            heights[nodeCount + container] = row + shelf
        }
    }
}
