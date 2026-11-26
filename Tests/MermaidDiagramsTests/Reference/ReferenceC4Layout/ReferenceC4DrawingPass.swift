/**
 * File: ReferenceC4DrawingPass.swift
 * ----------------------------------
 * Layer: Tests
 * Description: The 0.7.0 (de81532) C4 layout kept as the reference the flat C4 layout is checked against. The part of
 *              Pele's C4 render.ts that runs before anything is drawn: the boxes of the grid, what a label must not
 *              cover, and every relation routed, its ends found and its arrowheads, its color over a filled boundary
 *              and its casing decided.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// A relation routed, with what decides how it is painted.
struct ReferenceC4RoutedRelation {
    let relationIndex: Int
    let route: ReferenceC4Route
    let pointsAtStart: Bool
    let pointsAtEnd: Bool
    let lineColor: DiagramColor?
    let isCased: Bool
}

/// One drawing of a C4 diagram, as Pele's `draw` makes it: the grid's boxes (shapes first, boundary by boundary, then
/// the boundaries but the top level), what a label must not cover, the drawing's extent so far, and the relations.
struct ReferenceC4DrawingPass<Measurer: DiagramTextMeasuring> {
    let diagram: ReferenceC4Diagram
    let measurers: ReferenceC4Measurers<Measurer>
    let isTight: Bool
    var groups: [ReferenceC4PlacedBoundary]
    let shapes: [ReferenceC4PlacedShape]
    /// The placed shape of each of the first boxes, in the order the boundaries hold them.
    let shapeOrder: [Int]
    let boxes: [ReferenceC4RouteBox]
    /// Each group's box, nil for the top level.
    let groupBoxIndices: [Int?]
    let isCareful: Bool
    /// What a relation's label should not cover: shapes (less a margin), arrowheads, headings, and the labels placed before.
    var taken: [CGRect] = []
    var extent: CGRect
    var relations: [ReferenceC4RoutedRelation] = []
    var squeezedCount = 0

    init(diagram: ReferenceC4Diagram, measurers: ReferenceC4Measurers<Measurer>, room: CGFloat?, gap: CGFloat) {
        self.diagram = diagram
        self.measurers = measurers
        isTight = room != nil
        let grid = ReferenceC4GridPlacement(diagram: diagram, measurers: measurers, room: room, tightGap: gap).placed()
        groups = grid.groups
        shapes = grid.shapes
        shapeOrder = grid.groups.flatMap(\.shapes)
        var boxes = shapeOrder.map { index in grid.shapes[index].box }
        groupBoxIndices = grid.groups.indices.map { index -> Int? in
            guard index != 0 else { return nil }
            boxes.append(grid.groups[index].box)
            return boxes.count - 1
        }
        self.boxes = boxes
        let relationCount = diagram.relations.count
        isCareful = relationCount * (shapeOrder.count + grid.groups.count + 3 * relationCount) <= ReferenceC4Metrics.carefulPlacementBudget
        extent = CGRect(x: 0, y: 0, width: grid.groups[0].box.width, height: grid.groups[0].box.height)
        let allowance = ReferenceC4Metrics.shapeEdgeAllowance
        taken = shapeOrder.indices.map { index in boxes[index].frame.insetBy(dx: allowance, dy: allowance) }
    }

    mutating func grow(_ rectangle: CGRect) {
        let minimumX = min(extent.minX, rectangle.minX)
        let minimumY = min(extent.minY, rectangle.minY)
        extent = CGRect(x: minimumX, y: minimumY, width: max(extent.maxX, rectangle.maxX) - minimumX, height: max(extent.maxY, rectangle.maxY) - minimumY)
    }

    // MARK: - Relations

    /// Every relation routed in the order written, each kept apart from those before it. Every line is drawn before any
    /// label is placed, so that labels can keep off the arrowheads.
    mutating func routeRelations() throws(C4LayoutError) {
        let ends = try relationEnds()
        // Each relation's ends as one number, source then target, to find a relation running the opposite way.
        let boxCount = boxes.count
        var pairs = Set<Int>(minimumCapacity: ends.count)
        for (source, target) in ends { pairs.insert(source * boxCount + target) }
        let fills = boundaryFills()
        var router = ReferenceC4Router(boxes: boxes, obstacles: isCareful ? Array(shapeOrder.indices) : nil)
        for box in groupBoxIndices.compactMap({ index in index }) { router.lanes.addFrame(boxes[box]) }
        let trim = DiagramEdgeMark.lineTrim(for: .arrow)
        relations.reserveCapacity(diagram.relations.count)
        for (relationIndex, relation) in diagram.relations.enumerated() {
            let (source, target) = ends[relationIndex]
            let pointsAtStart = relation.kind.pointsAtStart
            let pointsAtEnd = relation.kind.pointsAtEnd
            let isReversed = source != target && pairs.contains(target * boxCount + source)
            let route = router.route(from: source, to: target, shift: isReversed ? ReferenceC4Metrics.pairShift : 0, startTrim: pointsAtStart ? trim : 0,
                                     endTrim: pointsAtEnd ? trim : 0)
            grow(CGRect(x: min(route.labelStretchStart.x, route.labelStretchEnd.x), y: min(route.labelStretchStart.y, route.labelStretchEnd.y),
                        width: abs(route.labelStretchEnd.x - route.labelStretchStart.x), height: abs(route.labelStretchEnd.y - route.labelStretchStart.y)))
            let arrowLength = ReferenceC4Metrics.arrowLength
            if pointsAtStart, isCareful { taken.append(CGRect(x: route.start.x - arrowLength, y: route.start.y - arrowLength, width: 2 * arrowLength, height: 2 * arrowLength)) }
            if pointsAtEnd, isCareful { taken.append(CGRect(x: route.end.x - arrowLength, y: route.end.y - arrowLength, width: 2 * arrowLength, height: 2 * arrowLength)) }
            let painting = ReferenceC4BoundaryFills.painting(of: route, lineColor: relation.lineColor, fills: fills)
            relations.append(ReferenceC4RoutedRelation(relationIndex: relationIndex, route: route, pointsAtStart: pointsAtStart, pointsAtEnd: pointsAtEnd,
                                              lineColor: painting.lineColor, isCased: painting.isCased))
        }
        squeezedCount = router.lanes.squeezedCount
    }

    /// The box of each relation's two ends: a shape's or else a boundary's of that alias, among those drawn.
    private func relationEnds() throws(C4LayoutError) -> [(Int, Int)] {
        var boxByAlias: [String: Int] = [:]
        boxByAlias.reserveCapacity(boxes.count)
        for (box, shapeIndex) in shapeOrder.enumerated() {
            let element = diagram.shapes[shapes[shapeIndex].shapeIndex].element
            if element.aliasArgument == nil { boxByAlias[element.alias] = box }
        }
        var shapeAliases = Set<String>(minimumCapacity: diagram.shapes.count + groups.count)
        for shape in diagram.shapes where shape.element.aliasArgument == nil { shapeAliases.insert(shape.element.alias) }
        for (groupIndex, group) in groups.enumerated() {
            let element = diagram.boundaries[group.boundaryIndex].element
            guard let box = groupBoxIndices[groupIndex], element.aliasArgument == nil, !shapeAliases.contains(element.alias) else { continue }
            boxByAlias[element.alias] = box
            shapeAliases.insert(element.alias)
        }
        return try diagram.relations.map { relation throws(C4LayoutError) in
            guard relation.fromArgument == nil, relation.toArgument == nil, let source = boxByAlias[relation.from], let target = boxByAlias[relation.to] else {
                throw .relationToUnknownElement(from: relation.from, to: relation.to)
            }
            return (source, target)
        }
    }

    /// The boundaries whose style fills them, by their group.
    private func boundaryFills() -> [ReferenceC4BoundaryFill] {
        groups.indices.compactMap { groupIndex in
            guard let box = groupBoxIndices[groupIndex] else { return nil }
            let element = diagram.boundaries[groups[groupIndex].boundaryIndex].element
            let look = C4ElementLook(backgroundColor: element.backgroundColor, borderColor: nil, fontColor: nil)
            return look.paintsFill ? ReferenceC4BoundaryFill(frame: boxes[box].frame, look: look) : nil
        }
    }
}
