/**
 * File: C4GridPlacement.swift
 * ---------------------------
 * Layer: Core
 * Description: Places a C4 diagram's shapes and boundaries on Mermaid's grid as Pele's layout.ts does: in each boundary
 *              its shapes in rows of c4ShapeInRow, stretched to their row's height, then the boundaries inside it in rows
 *              of c4BoundaryInRow, each sized around what it holds.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 24/11/2026
 */

import CoreGraphics

/// A shape measured and placed: its texts (type, name, technology, description; nil where it has none), their height
/// together, and its box.
struct C4PlacedShape {
    let shapeIndex: Int
    let texts: [DiagramTextBlock?]
    let textHeight: CGFloat
    var box: C4RouteBox
}

/// A boundary placed: the boundaries and shapes it holds (by their places in the grid's lists), its heading's texts
/// (name, type, description), the heading's height with the room under it, its width, where it starts from the box's
/// left, and the box.
struct C4PlacedBoundary {
    let boundaryIndex: Int
    var childGroups: [Int] = []
    var shapes: [Int] = []
    let texts: [DiagramTextBlock?]
    let headingHeight: CGFloat
    let headingWidth: CGFloat
    var headingLeft = C4Metrics.headingLeft
    var box = C4RouteBox(x: 0, y: 0, width: 0, height: 0, form: .rectangle)
}

/// The texts of a C4 diagram's grid measured for one room: each boundary's heading and each shape's texts and box, and
/// the blocks of the kinds' names by width. The tight layout draws a diagram again with wider gaps in the same room,
/// so it measures its texts once.
struct C4GridTexts {
    var headings: [C4PlacedBoundary?]
    var shapes: [C4PlacedShape?]
    var kindNames: [(kind: C4ShapeKind, width: CGFloat, block: DiagramTextBlock?)] = []

    init(diagram: C4Diagram) {
        headings = Array(repeating: nil, count: diagram.boundaryRecords.count)
        shapes = Array(repeating: nil, count: diagram.shapeRecords.count)
    }
}

/// Mermaid's grid of a C4 diagram, as Pele lays it out. `room`, the width of a narrow column less the padding, makes
/// it tight: shapes narrower, rows no wider than the room, boundaries' padding smaller, headings wrapped.
struct C4GridPlacement<Measurer: DiagramTextMeasuring> {
    let diagram: C4Diagram
    let measurers: C4Measurers<Measurer>
    let room: CGFloat?
    /// The gap between columns of shapes when tight.
    let tightGap: CGFloat

    /// The boundaries drawn, parents before children, the first the unnamed top level, and the shapes they hold.
    func placed(measuring texts: inout C4GridTexts) -> (groups: [C4PlacedBoundary], shapes: [C4PlacedShape]) {
        var groups: [C4PlacedBoundary] = []
        groups.reserveCapacity(diagram.boundaryRecords.count)
        var groupIndexByBoundary = [Int](repeating: -1, count: diagram.boundaryRecords.count)
        groupIndexByBoundary[0] = 0
        var depths: [Int] = [0]
        depths.reserveCapacity(diagram.boundaryRecords.count)
        groups.append(group(for: 0, measuring: &texts))
        // A boundary that ends up inside itself is not reachable from the top, as in Mermaid.
        let childBoundaries = childBoundaryIndices()
        // Each boundary's shapes counted first, so that each boundary's list is made once at its size.
        var shapeCounts = [Int](repeating: 0, count: diagram.boundaryRecords.count)
        for shape in diagram.shapeRecords { shapeCounts[max(Int(shape.element.parentBoundaryIndex), 0)] += 1 }
        groups[0].shapes.reserveCapacity(shapeCounts[0])
        var visited = 0
        while visited < groups.count {
            groups[visited].childGroups.reserveCapacity(childBoundaries[groups[visited].boundaryIndex].count)
            for child in childBoundaries[groups[visited].boundaryIndex] {
                groupIndexByBoundary[child] = groups.count
                groups[visited].childGroups.append(groups.count)
                depths.append(depths[visited] + 1)
                var childGroup = group(for: child, measuring: &texts)
                childGroup.shapes.reserveCapacity(shapeCounts[child])
                groups.append(childGroup)
            }
            visited += 1
        }
        var shapes: [C4PlacedShape] = []
        shapes.reserveCapacity(diagram.shapeRecords.count)
        for (shapeIndex, shape) in diagram.shapeRecords.enumerated() {
            let groupIndex = groupIndexByBoundary[max(Int(shape.element.parentBoundaryIndex), 0)]
            guard groupIndex >= 0 else { continue }
            groups[groupIndex].shapes.append(shapes.count)
            shapes.append(measured(shapeIndex, width: shapeWidth(atDepth: depths[groupIndex]), measuring: &texts))
        }
        let childrenTops = size(&groups, &shapes)
        place(&groups, &shapes, childrenTops: childrenTops)
        return (groups, shapes)
    }

    private var boundaryPadding: CGFloat { room == nil ? C4Metrics.boundaryPadding : C4Metrics.tightBoundaryPadding }

    /// The boundaries written in each boundary, in the order written.
    private func childBoundaryIndices() -> [[Int]] {
        var children = [[Int]](repeating: [], count: diagram.boundaryRecords.count)
        for (index, boundary) in diagram.boundaryRecords.enumerated() where boundary.element.parentBoundaryIndex >= 0 {
            children[Int(boundary.element.parentBoundaryIndex)].append(index)
        }
        return children
    }

    private func shapeWidth(atDepth depth: Int) -> CGFloat {
        guard let room else { return C4Metrics.shapeWidth }
        return max(100, min(C4Metrics.shapeWidth, room - 2 * CGFloat(depth) * boundaryPadding - 32))
    }

    /// A boundary's heading measured once for the room.
    private func group(for boundaryIndex: Int, measuring texts: inout C4GridTexts) -> C4PlacedBoundary {
        if let measured = texts.headings[boundaryIndex] { return measured }
        let measured = group(for: boundaryIndex)
        texts.headings[boundaryIndex] = measured
        return measured
    }

    /// A boundary's heading measured: its name in bold, `[type]` and its description in the small size.
    private func group(for boundaryIndex: Int) -> C4PlacedBoundary {
        guard boundaryIndex != 0 else {
            return C4PlacedBoundary(boundaryIndex: 0, texts: [], headingHeight: boundaryPadding, headingWidth: 0)
        }
        let element = diagram.boundaryRecords[boundaryIndex].element
        let labelRoom = room.map { room in max(C4Metrics.leastRoom, room - 2 * C4Metrics.headingLeft - 2 * C4Metrics.boundaryPadding * 2) }
            ?? C4Metrics.unwrappedWidth
        let texts = [C4TextLabel.block(element.label, in: diagram, measurer: measurers.name, maximumWidth: labelRoom),
                     C4TextLabel.bracketedBlock(element.type, in: diagram, measurer: measurers.small, maximumWidth: labelRoom),
                     C4TextLabel.block(element.description, in: diagram, measurer: measurers.small, maximumWidth: labelRoom)]
        let height = texts.reduce(0) { sum, text in sum + text.measuredHeight }
        let width = texts.reduce(0) { widest, text in max(widest, text.measuredWidth) }
        return C4PlacedBoundary(boundaryIndex: boundaryIndex, texts: texts,
                                headingHeight: height > 0 ? height + C4Metrics.headingTop + C4Metrics.headingGap + C4Metrics.lane : boundaryPadding,
                                headingWidth: width)
    }

    /// A shape's texts measured in its width less its padding and a queue's ends, and its box: that width or its widest
    /// text's, and at least 64 points high, a person's head and a database's caps added.
    private func measured(_ shapeIndex: Int, width: CGFloat, measuring texts: inout C4GridTexts) -> C4PlacedShape {
        if let measured = texts.shapes[shapeIndex] { return measured }
        let measured = self.measured(shapeIndex, width: width, kindNames: &texts.kindNames)
        texts.shapes[shapeIndex] = measured
        return measured
    }

    /// The block of a kind's name in `width`, measured once for each kind and width.
    private func kindName(_ kind: C4ShapeKind, width: CGFloat, in kindNames: inout [(kind: C4ShapeKind, width: CGFloat, block: DiagramTextBlock?)])
        -> DiagramTextBlock? {
        if let known = kindNames.first(where: { known in known.kind == kind && known.width.bitPattern == width.bitPattern }) { return known.block }
        let block = C4TextLabel.block(kind.guillemetedName, measurer: measurers.smallest, maximumWidth: width)
        kindNames.append((kind, width, block))
        return block
    }

    private func measured(_ shapeIndex: Int, width: CGFloat, kindNames: inout [(kind: C4ShapeKind, width: CGFloat, block: DiagramTextBlock?)])
        -> C4PlacedShape {
        let shape = diagram.shapeRecords[shapeIndex]
        let form = C4ShapeForm.form(of: shape, in: diagram)
        let capWidth = form == .horizontalCylinder ? C4Metrics.queueEndsWidth : 0
        let capHeight = form == .person ? C4Metrics.personHead : form == .cylinder ? C4Metrics.cylinderCapsHeight : 0
        let inner = width - 2 * C4Metrics.shapePaddingX - capWidth
        let texts = [kindName(shape.kind, width: inner, in: &kindNames),
                     C4TextLabel.block(shape.element.label, in: diagram, measurer: measurers.name, maximumWidth: inner),
                     C4TextLabel.bracketedBlock(shape.element.technology, in: diagram, measurer: measurers.small, maximumWidth: inner),
                     C4TextLabel.block(shape.element.description, in: diagram, measurer: measurers.small, maximumWidth: inner)]
        let textHeight = texts.reduce(texts[3].measuredHeight > 0 ? C4Metrics.descriptionGap : 0) { sum, text in sum + text.measuredHeight }
        let textWidth = texts.reduce(0) { widest, text in max(widest, text.measuredWidth) }
        let box = C4RouteBox(x: 0, y: 0, width: max(width, textWidth + 2 * C4Metrics.shapePaddingX + capWidth),
                             height: max(C4Metrics.shapeLeastHeight, textHeight + 2 * C4Metrics.shapePaddingY + capHeight), form: form)
        return C4PlacedShape(shapeIndex: shapeIndex, texts: texts, textHeight: textHeight, box: box)
    }

    /// Each boundary sized around its rows of shapes and of boundaries, children before parents, each box placed in its
    /// boundary's own frame from (0, 0); returns where each boundary's row of boundaries starts below its shapes.
    private func size(_ groups: inout [C4PlacedBoundary], _ shapes: inout [C4PlacedShape]) -> [CGFloat] {
        var childrenTops = [CGFloat](repeating: 0, count: groups.count)
        let shapesPerRow = max(1, diagram.shapesPerRow)
        let groupsPerRow = max(1, diagram.boundariesPerRow)
        let shapeGap = room == nil ? C4Metrics.columnGap : tightGap
        for groupIndex in groups.indices.reversed() {
            var shapeBoxes = groups[groupIndex].shapes.map { index in shapes[index].box }
            var childBoxes = groups[groupIndex].childGroups.map { index in groups[index].box }
            let grid = Self.rows(&shapeBoxes, perRow: rowCount(shapeBoxes, limit: shapesPerRow, gap: shapeGap), gapX: shapeGap, gapY: C4Metrics.rowGap,
                                 stretches: true)
            let children = Self.rows(&childBoxes, perRow: rowCount(childBoxes, limit: groupsPerRow, gap: C4Metrics.boundaryGap),
                                     gapX: C4Metrics.boundaryGap, gapY: C4Metrics.boundaryGap, stretches: false)
            for (offset, index) in groups[groupIndex].shapes.enumerated() { shapes[index].box = shapeBoxes[offset] }
            for (offset, index) in groups[groupIndex].childGroups.enumerated() { groups[index].box = childBoxes[offset] }
            let between = grid.height > 0 && children.height > 0 ? C4Metrics.boundaryGap : 0
            let frame = groupIndex == 0 ? 0 : boundaryPadding
            childrenTops[groupIndex] = grid.height + between
            let headingSpan = groups[groupIndex].headingWidth + 2 * C4Metrics.headingLeft - 2 * frame
            groups[groupIndex].box.width = max(grid.width, children.width, headingSpan) + 2 * frame
            groups[groupIndex].box.height = (frame == 0 ? 0 : groups[groupIndex].headingHeight) + grid.height + between + children.height + frame
        }
        return childrenTops
    }

    /// Each box moved from its boundary's frame onto the page, parents before children.
    private func place(_ groups: inout [C4PlacedBoundary], _ shapes: inout [C4PlacedShape], childrenTops: [CGFloat]) {
        for groupIndex in groups.indices {
            let box = groups[groupIndex].box
            let left = box.x + (groupIndex == 0 ? 0 : boundaryPadding)
            let top = box.y + (groupIndex == 0 ? 0 : groups[groupIndex].headingHeight)
            for index in groups[groupIndex].shapes {
                shapes[index].box.x += left
                shapes[index].box.y += top
            }
            for index in groups[groupIndex].childGroups {
                groups[index].box.x += left
                groups[index].box.y += top + childrenTops[groupIndex]
            }
        }
    }

    /// How many boxes a row holds: the diagram's count, or in a narrow column as many of the widest as the room takes.
    private func rowCount(_ boxes: [C4RouteBox], limit: Int, gap: CGFloat) -> Int {
        guard let room else { return limit }
        let widest = boxes.reduce(CGFloat(1)) { widest, box in max(widest, box.width) }
        let fitting = ((room + gap - 2 * boundaryPadding) / (widest + gap)).rounded(.down)
        return max(1, min(limit, fitting.isFinite ? Int(max(fitting, 0)) : limit))
    }

    /// Places boxes left to right in rows of `perRow` from (0, 0), and returns the width and height the rows take. Shapes
    /// are stretched to the height of their row; boundaries keep their own.
    static func rows(_ boxes: inout [C4RouteBox], perRow: Int, gapX: CGFloat, gapY: CGFloat, stretches: Bool) -> (width: CGFloat, height: CGFloat) {
        var width: CGFloat = 0
        var top: CGFloat = 0
        var rowStart = 0
        while rowStart < boxes.count {
            let rowEnd = min(boxes.count, rowStart + perRow)
            let rowHeight = boxes[rowStart..<rowEnd].reduce(0) { tallest, box in max(tallest, box.height) }
            var left: CGFloat = 0
            for index in rowStart..<rowEnd {
                boxes[index].x = left
                boxes[index].y = top
                if stretches { boxes[index].height = rowHeight }
                left += boxes[index].width + gapX
            }
            width = max(width, left - gapX)
            top += rowHeight + gapY
            rowStart = rowEnd
        }
        return (width, boxes.isEmpty ? 0 : top - gapY)
    }
}
