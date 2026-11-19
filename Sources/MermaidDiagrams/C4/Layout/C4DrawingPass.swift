/**
 * File: C4DrawingPass.swift
 * -------------------------
 * Layer: Core
 * Description: The part of Pele's C4 render.ts that runs before anything is drawn: the boxes of the grid, what a label
 *              must not cover, and every relation routed, its ends found and its arrowheads, its color over a filled
 *              boundary and its casing decided.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// Why a C4 diagram was not laid out.
public enum C4LayoutError: Error, Equatable, Sendable {
    /// A relation names an end that is no shape or boundary drawn, as Pele refuses it: its from and to as written.
    case relationToUnknownElement(from: String, to: String)
}

/// A relation routed, with what decides how it is painted.
struct C4RoutedRelation {
    let relationIndex: Int
    let route: C4Route
    let pointsAtStart: Bool
    let pointsAtEnd: Bool
    let lineColor: DiagramColor?
    let isCased: Bool
}

/// One drawing of a C4 diagram, as Pele's `draw` makes it: the grid's boxes (shapes first, boundary by boundary, then
/// the boundaries but the top level), what a label must not cover, the drawing's extent so far, and the relations.
struct C4DrawingPass<Measurer: DiagramTextMeasuring> {
    let diagram: C4Diagram
    let measurers: C4Measurers<Measurer>
    let isTight: Bool
    var groups: [C4PlacedBoundary]
    let shapes: [C4PlacedShape]
    /// The placed shape of each of the first boxes, in the order the boundaries hold them.
    let shapeOrder: [Int]
    let boxes: [C4RouteBox]
    /// Each group's box, nil for the top level.
    let groupBoxIndices: [Int?]
    let isCareful: Bool
    /// What a relation's label should not cover: shapes (less a margin), arrowheads, headings, and the labels placed before.
    var taken: [CGRect] = []
    var extent: CGRect
    var relations: [C4RoutedRelation] = []
    var squeezedCount = 0

    init(diagram: C4Diagram, measurers: C4Measurers<Measurer>, room: CGFloat?, gap: CGFloat) {
        self.diagram = diagram
        self.measurers = measurers
        isTight = room != nil
        let grid = C4GridPlacement(diagram: diagram, measurers: measurers, room: room, tightGap: gap).placed()
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
        isCareful = relationCount * (shapeOrder.count + grid.groups.count + 3 * relationCount) <= C4Metrics.carefulPlacementBudget
        extent = CGRect(x: 0, y: 0, width: grid.groups[0].box.width, height: grid.groups[0].box.height)
        let allowance = C4Metrics.shapeEdgeAllowance
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
        var targetsBySource: [Int: Set<Int>] = [:]
        for (source, target) in ends { targetsBySource[source, default: []].insert(target) }
        let fills = boundaryFills()
        var router = C4Router(boxes: boxes, obstacles: isCareful ? Array(shapeOrder.indices) : nil)
        for box in groupBoxIndices.compactMap({ index in index }) { router.lanes.addFrame(boxes[box]) }
        let trim = DiagramEdgeMark.lineTrim(for: .arrow)
        for (relationIndex, relation) in diagram.relations.enumerated() {
            let (source, target) = ends[relationIndex]
            let pointsAtStart = relation.kind.pointsAtStart
            let pointsAtEnd = relation.kind.pointsAtEnd
            let isReversed = source != target && targetsBySource[target]?.contains(source) == true
            let route = router.route(from: source, to: target, shift: isReversed ? C4Metrics.pairShift : 0, startTrim: pointsAtStart ? trim : 0,
                                     endTrim: pointsAtEnd ? trim : 0)
            grow(CGRect(x: min(route.labelStretchStart.x, route.labelStretchEnd.x), y: min(route.labelStretchStart.y, route.labelStretchEnd.y),
                        width: abs(route.labelStretchEnd.x - route.labelStretchStart.x), height: abs(route.labelStretchEnd.y - route.labelStretchStart.y)))
            let arrowLength = C4Metrics.arrowLength
            if pointsAtStart, isCareful { taken.append(CGRect(x: route.start.x - arrowLength, y: route.start.y - arrowLength, width: 2 * arrowLength, height: 2 * arrowLength)) }
            if pointsAtEnd, isCareful { taken.append(CGRect(x: route.end.x - arrowLength, y: route.end.y - arrowLength, width: 2 * arrowLength, height: 2 * arrowLength)) }
            let painting = C4BoundaryFills.painting(of: route, lineColor: relation.lineColor, fills: fills)
            relations.append(C4RoutedRelation(relationIndex: relationIndex, route: route, pointsAtStart: pointsAtStart, pointsAtEnd: pointsAtEnd,
                                              lineColor: painting.lineColor, isCased: painting.isCased))
        }
        squeezedCount = router.lanes.squeezedCount
    }

    /// The box of each relation's two ends: a shape's or else a boundary's of that alias, among those drawn.
    private func relationEnds() throws(C4LayoutError) -> [(Int, Int)] {
        var boxByAlias: [String: Int] = [:]
        for (box, shapeIndex) in shapeOrder.enumerated() {
            let element = diagram.shapes[shapes[shapeIndex].shapeIndex].element
            if element.aliasArgument == nil { boxByAlias[element.alias] = box }
        }
        var shapeAliases = Set(diagram.shapes.filter { shape in shape.element.aliasArgument == nil }.map(\.element.alias))
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
    private func boundaryFills() -> [C4BoundaryFill] {
        groups.indices.compactMap { groupIndex in
            guard let box = groupBoxIndices[groupIndex] else { return nil }
            let element = diagram.boundaries[groups[groupIndex].boundaryIndex].element
            let look = C4ElementLook(backgroundColor: element.backgroundColor, borderColor: nil, fontColor: nil)
            return look.paintsFill ? C4BoundaryFill(frame: boxes[box].frame, look: look) : nil
        }
    }
}
