/**
 * File: C4GridPlacement.swift
 * ---------------------------
 * Layer: Core
 * Description: Places a C4 diagram's shapes and boundaries on Mermaid's grid as Pele's layout.ts does: in each boundary
 *              its shapes in rows of c4ShapeInRow, stretched to their row's height, then the boundaries inside it in rows
 *              of c4BoundaryInRow, each sized around what it holds; the texts measured from the diagram's bytes into
 *              one list of lines, the shapes kept boundary by boundary and each boundary's children side by side.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 26/11/2026
 */

import CoreGraphics

/// A shape measured and placed: its texts (type, name, technology, description; nil where it has none), their height
/// together, and its box.
struct C4PlacedShape: C4GridItem {
    let shapeIndex: Int
    let type: DiagramMeasuredText?
    let name: DiagramMeasuredText?
    let technology: DiagramMeasuredText?
    let description: DiagramMeasuredText?
    let textHeight: CGFloat
    var box: C4RouteBox
}

/// A boundary placed: the boundaries it holds (side by side in the grid's list of boundaries) and its shapes (side by
/// side in the list of shapes), its heading's texts (name, type, description), the heading's height with the room under
/// it, its width, where it starts from the box's left, and the box.
struct C4PlacedBoundary: C4GridItem {
    let boundaryIndex: Int
    var firstChildGroup = 0
    var childGroupCount = 0
    var firstShape = 0
    var shapeCount = 0
    let name: DiagramMeasuredText?
    let type: DiagramMeasuredText?
    let description: DiagramMeasuredText?
    let headingHeight: CGFloat
    let headingWidth: CGFloat
    var headingLeft = C4Metrics.headingLeft
    var box = C4RouteBox(x: 0, y: 0, width: 0, height: 0, form: .rectangle)

    var childGroups: Range<Int> { firstChildGroup..<(firstChildGroup + childGroupCount) }
    var shapes: Range<Int> { firstShape..<(firstShape + shapeCount) }
}

/// What the grid's rows place: a box.
protocol C4GridItem {
    var box: C4RouteBox { get set }
}

/// The texts of a C4 diagram measured for one room, and the lines of every text the layout measures. The grid's texts
/// (each boundary's heading, each shape's texts and box, the kinds' names by width) are kept, since the tight layout
/// draws a diagram again with wider gaps in the same room and so measures them once.
struct C4GridTexts {
    var lines = DiagramMeasuredLines()
    var headings: [C4PlacedBoundary?]
    var shapes: [C4PlacedShape?]
    var kindNames: [(kind: C4ShapeKind, width: CGFloat, text: DiagramMeasuredText)] = []

    init(diagram: C4Diagram) {
        headings = Array(repeating: nil, count: diagram.boundaryRecords.count)
        shapes = Array(repeating: nil, count: diagram.shapeRecords.count)
    }
}

/// Mermaid's grid of a C4 diagram, as Pele lays it out. `room`, the width of a narrow column less the padding, makes
/// it tight: shapes narrower, rows no wider than the room, boundaries' padding smaller, headings wrapped.
struct C4GridPlacement<Measurer: DiagramTextMeasuring> {
    let diagram: C4Diagram
    let measuring: C4TextMeasuring<Measurer>
    let room: CGFloat?
    /// The gap between columns of shapes when tight.
    let tightGap: CGFloat

    /// The boundaries drawn, parents before children, the first the unnamed top level, and the shapes they hold,
    /// boundary by boundary in that order.
    func placed(measuring texts: inout C4GridTexts) -> (groups: [C4PlacedBoundary], shapes: [C4PlacedShape]) {
        let boundaryCount = diagram.boundaryRecords.count
        var groups: [C4PlacedBoundary] = []
        groups.reserveCapacity(boundaryCount)
        var groupIndexByBoundary = [Int](repeating: -1, count: boundaryCount)
        groupIndexByBoundary[0] = 0
        var depths: [Int] = [0]
        depths.reserveCapacity(boundaryCount)
        groups.append(group(for: 0, measuring: &texts))
        // A boundary that ends up inside itself is not reachable from the top, as in Mermaid.
        let children = ChildBoundaries(diagram: diagram)
        var visited = 0
        while visited < groups.count {
            groups[visited].firstChildGroup = groups.count
            for child in children.of(groups[visited].boundaryIndex) {
                groupIndexByBoundary[child] = groups.count
                depths.append(depths[visited] + 1)
                groups.append(group(for: child, measuring: &texts))
            }
            groups[visited].childGroupCount = groups.count - groups[visited].firstChildGroup
            visited += 1
        }
        var shapes = placedShapes(&groups, groupIndexByBoundary: groupIndexByBoundary, depths: depths, measuring: &texts)
        let childrenTops = size(&groups, &shapes)
        place(&groups, &shapes, childrenTops: childrenTops)
        return (groups, shapes)
    }

    /// Each boundary's shapes in the order written, boundary by boundary in the order of `groups`, measured, each
    /// group's range of them set.
    private func placedShapes(_ groups: inout [C4PlacedBoundary], groupIndexByBoundary: [Int], depths: [Int], measuring texts: inout C4GridTexts)
        -> [C4PlacedShape] {
        for shape in diagram.shapeRecords {
            let groupIndex = groupIndexByBoundary[max(Int(shape.element.parentBoundaryIndex), 0)]
            if groupIndex >= 0 { groups[groupIndex].shapeCount += 1 }
        }
        var next = 0
        var placeByGroup = [Int](repeating: 0, count: groups.count)
        for groupIndex in groups.indices {
            groups[groupIndex].firstShape = next
            placeByGroup[groupIndex] = next
            next += groups[groupIndex].shapeCount
        }
        var shapeIndexByPlace = [Int](repeating: 0, count: next)
        for (shapeIndex, shape) in diagram.shapeRecords.enumerated() {
            let groupIndex = groupIndexByBoundary[max(Int(shape.element.parentBoundaryIndex), 0)]
            guard groupIndex >= 0 else { continue }
            shapeIndexByPlace[placeByGroup[groupIndex]] = shapeIndex
            placeByGroup[groupIndex] += 1
        }
        var shapes: [C4PlacedShape] = []
        shapes.reserveCapacity(next)
        for groupIndex in groups.indices {
            let width = shapeWidth(atDepth: depths[groupIndex])
            for place in groups[groupIndex].shapes { shapes.append(measured(shapeIndexByPlace[place], width: width, measuring: &texts)) }
        }
        return shapes
    }

    private var boundaryPadding: CGFloat { room == nil ? C4Metrics.boundaryPadding : C4Metrics.tightBoundaryPadding }

    /// The boundaries written in each boundary, in the order written, side by side in one list.
    private struct ChildBoundaries {
        let starts: [Int]
        let children: [Int]

        init(diagram: C4Diagram) {
            let records = diagram.boundaryRecords
            var starts = [Int](repeating: 0, count: records.count + 1)
            for boundary in records where boundary.element.parentBoundaryIndex >= 0 { starts[Int(boundary.element.parentBoundaryIndex) + 1] += 1 }
            for index in 0..<records.count { starts[index + 1] += starts[index] }
            var next = starts
            var children = [Int](repeating: 0, count: starts[records.count])
            for (index, boundary) in records.enumerated() where boundary.element.parentBoundaryIndex >= 0 {
                let parent = Int(boundary.element.parentBoundaryIndex)
                children[next[parent]] = index
                next[parent] += 1
            }
            self.starts = starts
            self.children = children
        }

        func of(_ boundaryIndex: Int) -> ArraySlice<Int> { children[starts[boundaryIndex]..<starts[boundaryIndex + 1]] }
    }

    private func shapeWidth(atDepth depth: Int) -> CGFloat {
        guard let room else { return C4Metrics.shapeWidth }
        return max(100, min(C4Metrics.shapeWidth, room - 2 * CGFloat(depth) * boundaryPadding - 32))
    }

    /// A boundary's heading measured once for the room.
    private func group(for boundaryIndex: Int, measuring texts: inout C4GridTexts) -> C4PlacedBoundary {
        if let measured = texts.headings[boundaryIndex] { return measured }
        let measured = group(for: boundaryIndex, into: &texts.lines)
        texts.headings[boundaryIndex] = measured
        return measured
    }

    /// A boundary's heading measured: its name in bold, `[type]` and its description in the small size.
    private func group(for boundaryIndex: Int, into lines: inout DiagramMeasuredLines) -> C4PlacedBoundary {
        guard boundaryIndex != 0 else {
            return C4PlacedBoundary(boundaryIndex: 0, name: nil, type: nil, description: nil, headingHeight: boundaryPadding, headingWidth: 0)
        }
        let element = diagram.boundaryRecords[boundaryIndex].element
        let labelRoom = room.map { room in max(C4Metrics.leastRoom, room - 2 * C4Metrics.headingLeft - 2 * C4Metrics.boundaryPadding * 2) }
            ?? C4Metrics.unwrappedWidth
        let name = measuring.measure(element.label, in: diagram, with: measuring.name, maximumWidth: labelRoom, into: &lines)
        let type = measuring.measureBracketed(element.type, in: diagram, with: measuring.small, maximumWidth: labelRoom, into: &lines)
        let description = measuring.measure(element.description, in: diagram, with: measuring.small, maximumWidth: labelRoom, into: &lines)
        let height = 0 + name.measuredHeight + type.measuredHeight + description.measuredHeight
        let width = max(max(max(0, name.measuredWidth), type.measuredWidth), description.measuredWidth)
        return C4PlacedBoundary(boundaryIndex: boundaryIndex, name: name, type: type, description: description,
                                headingHeight: height > 0 ? height + C4Metrics.headingTop + C4Metrics.headingGap + C4Metrics.lane : boundaryPadding,
                                headingWidth: width)
    }

    /// A shape's texts measured in its width less its padding and a queue's ends, and its box: that width or its widest
    /// text's, and at least 64 points high, a person's head and a database's caps added. Measured once for the room.
    private func measured(_ shapeIndex: Int, width: CGFloat, measuring texts: inout C4GridTexts) -> C4PlacedShape {
        if let measured = texts.shapes[shapeIndex] { return measured }
        let measured = self.measured(shapeIndex, width: width, texts: &texts)
        texts.shapes[shapeIndex] = measured
        return measured
    }

    /// A kind's name in `width`, measured once for each kind and width.
    private func kindName(_ kind: C4ShapeKind, width: CGFloat, texts: inout C4GridTexts) -> DiagramMeasuredText {
        if let known = texts.kindNames.first(where: { known in known.kind == kind && known.width.bitPattern == width.bitPattern }) { return known.text }
        let text = measuring.measureKindName(kind, maximumWidth: width, into: &texts.lines)
        texts.kindNames.append((kind, width, text))
        return text
    }

    private func measured(_ shapeIndex: Int, width: CGFloat, texts: inout C4GridTexts) -> C4PlacedShape {
        let shape = diagram.shapeRecords[shapeIndex]
        let form = C4ShapeForm.form(of: shape, in: diagram)
        let capWidth = form == .horizontalCylinder ? C4Metrics.queueEndsWidth : 0
        let capHeight = form == .person ? C4Metrics.personHead : form == .cylinder ? C4Metrics.cylinderCapsHeight : 0
        let inner = width - 2 * C4Metrics.shapePaddingX - capWidth
        let type: DiagramMeasuredText? = kindName(shape.kind, width: inner, texts: &texts)
        let name = measuring.measure(shape.element.label, in: diagram, with: measuring.name, maximumWidth: inner, into: &texts.lines)
        let technology = measuring.measureBracketed(shape.element.technology, in: diagram, with: measuring.small, maximumWidth: inner, into: &texts.lines)
        let description = measuring.measure(shape.element.description, in: diagram, with: measuring.small, maximumWidth: inner, into: &texts.lines)
        // Added and compared in the order the texts are drawn, as a list of them was reduced.
        let textHeight = (description.measuredHeight > 0 ? C4Metrics.descriptionGap : 0) + type.measuredHeight + name.measuredHeight
            + technology.measuredHeight + description.measuredHeight
        let textWidth = max(max(max(max(0, type.measuredWidth), name.measuredWidth), technology.measuredWidth), description.measuredWidth)
        let box = C4RouteBox(x: 0, y: 0, width: max(width, textWidth + 2 * C4Metrics.shapePaddingX + capWidth),
                             height: max(C4Metrics.shapeLeastHeight, textHeight + 2 * C4Metrics.shapePaddingY + capHeight), form: form)
        return C4PlacedShape(shapeIndex: shapeIndex, type: type, name: name, technology: technology, description: description, textHeight: textHeight, box: box)
    }

    /// Each boundary sized around its rows of shapes and of boundaries, children before parents, each box placed in its
    /// boundary's own frame from (0, 0); returns where each boundary's row of boundaries starts below its shapes.
    private func size(_ groups: inout [C4PlacedBoundary], _ shapes: inout [C4PlacedShape]) -> [CGFloat] {
        var childrenTops = [CGFloat](repeating: 0, count: groups.count)
        let shapesPerRow = max(1, diagram.shapesPerRow)
        let groupsPerRow = max(1, diagram.boundariesPerRow)
        let shapeGap = room == nil ? C4Metrics.columnGap : tightGap
        for groupIndex in groups.indices.reversed() {
            let shapeRange = groups[groupIndex].shapes
            let childRange = groups[groupIndex].childGroups
            let grid = Self.rows(&shapes, shapeRange, perRow: rowCount(shapes, shapeRange, limit: shapesPerRow, gap: shapeGap), gapX: shapeGap,
                                 gapY: C4Metrics.rowGap, stretches: true)
            let children = Self.rows(&groups, childRange, perRow: rowCount(groups, childRange, limit: groupsPerRow, gap: C4Metrics.boundaryGap),
                                     gapX: C4Metrics.boundaryGap, gapY: C4Metrics.boundaryGap, stretches: false)
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
    private func rowCount<Item: C4GridItem>(_ items: [Item], _ range: Range<Int>, limit: Int, gap: CGFloat) -> Int {
        guard let room else { return limit }
        var widest: CGFloat = 1
        for index in range { widest = max(widest, items[index].box.width) }
        let fitting = ((room + gap - 2 * boundaryPadding) / (widest + gap)).rounded(.down)
        return max(1, min(limit, fitting.isFinite ? Int(max(fitting, 0)) : limit))
    }

    /// Places the boxes of `items[range]` left to right in rows of `perRow` from (0, 0), and returns the width and height
    /// the rows take. Shapes are stretched to the height of their row; boundaries keep their own.
    static func rows<Item: C4GridItem>(_ items: inout [Item], _ range: Range<Int>, perRow: Int, gapX: CGFloat, gapY: CGFloat, stretches: Bool)
        -> (width: CGFloat, height: CGFloat) {
        var width: CGFloat = 0
        var top: CGFloat = 0
        var rowStart = range.lowerBound
        while rowStart < range.upperBound {
            let rowEnd = min(range.upperBound, rowStart + perRow)
            var rowHeight: CGFloat = 0
            for index in rowStart..<rowEnd { rowHeight = max(rowHeight, items[index].box.height) }
            var left: CGFloat = 0
            for index in rowStart..<rowEnd {
                items[index].box.x = left
                items[index].box.y = top
                if stretches { items[index].box.height = rowHeight }
                left += items[index].box.width + gapX
            }
            width = max(width, left - gapX)
            top += rowHeight + gapY
            rowStart = rowEnd
        }
        return (width, range.isEmpty ? 0 : top - gapY)
    }
}
