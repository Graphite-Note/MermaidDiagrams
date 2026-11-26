/**
 * File: ReferenceC4GridPlacement.swift
 * ------------------------------------
 * Layer: Tests
 * Description: The 0.7.0 (de81532) C4 layout kept as the reference the flat C4 layout is checked against. Places a C4
 *              diagram's shapes and boundaries on Mermaid's grid as Pele's layout.ts does: in each boundary its shapes
 *              in rows of c4ShapeInRow, stretched to their row's height, then the boundaries inside it in rows of
 *              c4BoundaryInRow, each sized around what it holds.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// A shape measured and placed: its texts (type, name, technology, description; nil where it has none), their height
/// together, and its box.
struct ReferenceC4PlacedShape {
    let shapeIndex: Int
    let texts: [DiagramTextBlock?]
    let textHeight: CGFloat
    var box: ReferenceC4RouteBox
}

/// A boundary placed: the boundaries and shapes it holds (by their places in the grid's lists), its heading's texts
/// (name, type, description), the heading's height with the room under it, its width, where it starts from the box's
/// left, and the box.
struct ReferenceC4PlacedBoundary {
    let boundaryIndex: Int
    var childGroups: [Int] = []
    var shapes: [Int] = []
    let texts: [DiagramTextBlock?]
    let headingHeight: CGFloat
    let headingWidth: CGFloat
    var headingLeft = ReferenceC4Metrics.headingLeft
    var box = ReferenceC4RouteBox(x: 0, y: 0, width: 0, height: 0, form: .rectangle)
}

/// Mermaid's grid of a C4 diagram, as Pele lays it out. `room`, the width of a narrow column less the padding, makes
/// it tight: shapes narrower, rows no wider than the room, boundaries' padding smaller, headings wrapped.
struct ReferenceC4GridPlacement<Measurer: DiagramTextMeasuring> {
    let diagram: ReferenceC4Diagram
    let measurers: ReferenceC4Measurers<Measurer>
    let room: CGFloat?
    /// The gap between columns of shapes when tight.
    let tightGap: CGFloat

    /// The boundaries drawn, parents before children, the first the unnamed top level, and the shapes they hold.
    func placed() -> (groups: [ReferenceC4PlacedBoundary], shapes: [ReferenceC4PlacedShape]) {
        var groups: [ReferenceC4PlacedBoundary] = []
        var groupIndexByBoundary: [Int: Int] = [0: 0]
        var depths: [Int] = [0]
        groups.append(group(for: 0))
        // A boundary that ends up inside itself is not reachable from the top, as in Mermaid.
        let childBoundaries = childBoundaryIndices()
        var visited = 0
        while visited < groups.count {
            for child in childBoundaries[groups[visited].boundaryIndex] {
                groupIndexByBoundary[child] = groups.count
                groups[visited].childGroups.append(groups.count)
                depths.append(depths[visited] + 1)
                groups.append(group(for: child))
            }
            visited += 1
        }
        var shapes: [ReferenceC4PlacedShape] = []
        for (shapeIndex, shape) in diagram.shapes.enumerated() {
            guard let groupIndex = groupIndexByBoundary[shape.element.parentBoundaryIndex ?? 0] else { continue }
            groups[groupIndex].shapes.append(shapes.count)
            shapes.append(measured(shapeIndex, width: shapeWidth(atDepth: depths[groupIndex])))
        }
        let childrenTops = size(&groups, &shapes)
        place(&groups, &shapes, childrenTops: childrenTops)
        return (groups, shapes)
    }

    private var boundaryPadding: CGFloat { room == nil ? ReferenceC4Metrics.boundaryPadding : ReferenceC4Metrics.tightBoundaryPadding }

    /// The boundaries written in each boundary, in the order written.
    private func childBoundaryIndices() -> [[Int]] {
        var children = [[Int]](repeating: [], count: diagram.boundaries.count)
        for (index, boundary) in diagram.boundaries.enumerated() {
            if let parent = boundary.element.parentBoundaryIndex { children[parent].append(index) }
        }
        return children
    }

    private func shapeWidth(atDepth depth: Int) -> CGFloat {
        guard let room else { return ReferenceC4Metrics.shapeWidth }
        return max(100, min(ReferenceC4Metrics.shapeWidth, room - 2 * CGFloat(depth) * boundaryPadding - 32))
    }

    /// A boundary's heading measured: its name in bold, `[type]` and its description in the small size.
    private func group(for boundaryIndex: Int) -> ReferenceC4PlacedBoundary {
        guard boundaryIndex != 0 else {
            return ReferenceC4PlacedBoundary(boundaryIndex: 0, texts: [], headingHeight: boundaryPadding, headingWidth: 0)
        }
        let element = diagram.boundaries[boundaryIndex].element
        let labelRoom = room.map { room in max(ReferenceC4Metrics.leastRoom, room - 2 * ReferenceC4Metrics.headingLeft - 2 * ReferenceC4Metrics.boundaryPadding * 2) }
            ?? ReferenceC4Metrics.unwrappedWidth
        let texts = [ReferenceC4TextLabel.block(element.label, measurer: measurers.name, maximumWidth: labelRoom),
                     ReferenceC4TextLabel.block(element.type.flatMap { type in type.isEmpty ? nil : "[" + type + "]" }, measurer: measurers.small, maximumWidth: labelRoom),
                     ReferenceC4TextLabel.block(element.description, measurer: measurers.small, maximumWidth: labelRoom)]
        let height = texts.reduce(0) { sum, text in sum + text.measuredHeight }
        let width = texts.reduce(0) { widest, text in max(widest, text.measuredWidth) }
        return ReferenceC4PlacedBoundary(boundaryIndex: boundaryIndex, texts: texts,
                                headingHeight: height > 0 ? height + ReferenceC4Metrics.headingTop + ReferenceC4Metrics.headingGap + ReferenceC4Metrics.lane : boundaryPadding,
                                headingWidth: width)
    }

    /// A shape's texts measured in its width less its padding and a queue's ends, and its box: that width or its widest
    /// text's, and at least 64 points high, a person's head and a database's caps added.
    private func measured(_ shapeIndex: Int, width: CGFloat) -> ReferenceC4PlacedShape {
        let shape = diagram.shapes[shapeIndex]
        let form = C4ShapeForm.referenceForm(of: shape)
        let capWidth = form == .horizontalCylinder ? ReferenceC4Metrics.queueEndsWidth : 0
        let capHeight = form == .person ? ReferenceC4Metrics.personHead : form == .cylinder ? ReferenceC4Metrics.cylinderCapsHeight : 0
        let inner = width - 2 * ReferenceC4Metrics.shapePaddingX - capWidth
        let technology = shape.element.technology.flatMap { technology in technology.isEmpty ? nil : "[" + technology + "]" }
        let texts = [ReferenceC4TextLabel.block(shape.kind.guillemetedName, measurer: measurers.smallest, maximumWidth: inner),
                     ReferenceC4TextLabel.block(shape.element.label, measurer: measurers.name, maximumWidth: inner),
                     ReferenceC4TextLabel.block(technology, measurer: measurers.small, maximumWidth: inner),
                     ReferenceC4TextLabel.block(shape.element.description, measurer: measurers.small, maximumWidth: inner)]
        let textHeight = texts.reduce(texts[3].measuredHeight > 0 ? ReferenceC4Metrics.descriptionGap : 0) { sum, text in sum + text.measuredHeight }
        let textWidth = texts.reduce(0) { widest, text in max(widest, text.measuredWidth) }
        let box = ReferenceC4RouteBox(x: 0, y: 0, width: max(width, textWidth + 2 * ReferenceC4Metrics.shapePaddingX + capWidth),
                             height: max(ReferenceC4Metrics.shapeLeastHeight, textHeight + 2 * ReferenceC4Metrics.shapePaddingY + capHeight), form: form)
        return ReferenceC4PlacedShape(shapeIndex: shapeIndex, texts: texts, textHeight: textHeight, box: box)
    }

    /// Each boundary sized around its rows of shapes and of boundaries, children before parents, each box placed in its
    /// boundary's own frame from (0, 0); returns where each boundary's row of boundaries starts below its shapes.
    private func size(_ groups: inout [ReferenceC4PlacedBoundary], _ shapes: inout [ReferenceC4PlacedShape]) -> [CGFloat] {
        var childrenTops = [CGFloat](repeating: 0, count: groups.count)
        let shapesPerRow = max(1, diagram.shapesPerRow)
        let groupsPerRow = max(1, diagram.boundariesPerRow)
        let shapeGap = room == nil ? ReferenceC4Metrics.columnGap : tightGap
        for groupIndex in groups.indices.reversed() {
            var shapeBoxes = groups[groupIndex].shapes.map { index in shapes[index].box }
            var childBoxes = groups[groupIndex].childGroups.map { index in groups[index].box }
            let grid = Self.rows(&shapeBoxes, perRow: rowCount(shapeBoxes, limit: shapesPerRow, gap: shapeGap), gapX: shapeGap, gapY: ReferenceC4Metrics.rowGap,
                                 stretches: true)
            let children = Self.rows(&childBoxes, perRow: rowCount(childBoxes, limit: groupsPerRow, gap: ReferenceC4Metrics.boundaryGap),
                                     gapX: ReferenceC4Metrics.boundaryGap, gapY: ReferenceC4Metrics.boundaryGap, stretches: false)
            for (offset, index) in groups[groupIndex].shapes.enumerated() { shapes[index].box = shapeBoxes[offset] }
            for (offset, index) in groups[groupIndex].childGroups.enumerated() { groups[index].box = childBoxes[offset] }
            let between = grid.height > 0 && children.height > 0 ? ReferenceC4Metrics.boundaryGap : 0
            let frame = groupIndex == 0 ? 0 : boundaryPadding
            childrenTops[groupIndex] = grid.height + between
            let headingSpan = groups[groupIndex].headingWidth + 2 * ReferenceC4Metrics.headingLeft - 2 * frame
            groups[groupIndex].box.width = max(grid.width, children.width, headingSpan) + 2 * frame
            groups[groupIndex].box.height = (frame == 0 ? 0 : groups[groupIndex].headingHeight) + grid.height + between + children.height + frame
        }
        return childrenTops
    }

    /// Each box moved from its boundary's frame onto the page, parents before children.
    private func place(_ groups: inout [ReferenceC4PlacedBoundary], _ shapes: inout [ReferenceC4PlacedShape], childrenTops: [CGFloat]) {
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
    private func rowCount(_ boxes: [ReferenceC4RouteBox], limit: Int, gap: CGFloat) -> Int {
        guard let room else { return limit }
        let widest = boxes.reduce(CGFloat(1)) { widest, box in max(widest, box.width) }
        let fitting = ((room + gap - 2 * boundaryPadding) / (widest + gap)).rounded(.down)
        return max(1, min(limit, fitting.isFinite ? Int(max(fitting, 0)) : limit))
    }

    /// Places boxes left to right in rows of `perRow` from (0, 0), and returns the width and height the rows take. Shapes
    /// are stretched to the height of their row; boundaries keep their own.
    static func rows(_ boxes: inout [ReferenceC4RouteBox], perRow: Int, gapX: CGFloat, gapY: CGFloat, stretches: Bool) -> (width: CGFloat, height: CGFloat) {
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
