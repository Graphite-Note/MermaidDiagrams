/**
 * File: C4DrawingPass.swift
 * -------------------------
 * Layer: Core
 * Description: The part of Pele's C4 render.ts that runs before anything is drawn: the boxes of the grid, what a label
 *              must not cover, and every relation routed, its ends found and its arrowheads, its color over a filled
 *              boundary and its casing decided.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 24/11/2026
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
    let textColor: DiagramColor?
    let isCased: Bool
}

/// The colors relations' styles write, each value read once for a drawing: a diagram's relations share a few.
struct C4StyleColors {
    private var known: [(value: String, property: String, color: DiagramColor?)] = []

    /// `C4ElementLook.color(value, property:)`, read once for each value and property.
    mutating func color(_ value: String?, property: String) -> DiagramColor? {
        guard let value, !value.isEmpty else { return nil }
        if let found = known.first(where: { entry in entry.value == value && entry.property == property }) { return found.color }
        let color = C4ElementLook.color(value, property: property)
        known.append((value, property, color))
        return color
    }
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

    init(diagram: C4Diagram, measurers: C4Measurers<Measurer>, room: CGFloat?, gap: CGFloat, texts: inout C4GridTexts) {
        self.diagram = diagram
        self.measurers = measurers
        isTight = room != nil
        let grid = C4GridPlacement(diagram: diagram, measurers: measurers, room: room, tightGap: gap).placed(measuring: &texts)
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
        let relationCount = diagram.relationRecords.count
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
        // Each relation's ends as one number, source then target, to find a relation running the opposite way.
        let boxCount = boxes.count
        var pairs = Set<Int>(minimumCapacity: ends.count)
        for (source, target) in ends { pairs.insert(source * boxCount + target) }
        let fills = boundaryFills()
        var router = C4Router(boxes: boxes, obstacles: isCareful ? Array(shapeOrder.indices) : nil)
        for box in groupBoxIndices.compactMap({ index in index }) { router.lanes.addFrame(boxes[box]) }
        let trim = DiagramEdgeMark.lineTrim(for: .arrow)
        var colors = C4StyleColors()
        relations.reserveCapacity(diagram.relationRecords.count)
        for (relationIndex, relation) in diagram.relationRecords.enumerated() {
            let (source, target) = ends[relationIndex]
            let pointsAtStart = relation.kind.pointsAtStart
            let pointsAtEnd = relation.kind.pointsAtEnd
            let isReversed = source != target && pairs.contains(target * boxCount + source)
            let route = router.route(from: source, to: target, shift: isReversed ? C4Metrics.pairShift : 0, startTrim: pointsAtStart ? trim : 0,
                                     endTrim: pointsAtEnd ? trim : 0)
            grow(CGRect(x: min(route.labelStretchStart.x, route.labelStretchEnd.x), y: min(route.labelStretchStart.y, route.labelStretchEnd.y),
                        width: abs(route.labelStretchEnd.x - route.labelStretchStart.x), height: abs(route.labelStretchEnd.y - route.labelStretchStart.y)))
            let arrowLength = C4Metrics.arrowLength
            if pointsAtStart, isCareful { taken.append(CGRect(x: route.start.x - arrowLength, y: route.start.y - arrowLength, width: 2 * arrowLength, height: 2 * arrowLength)) }
            if pointsAtEnd, isCareful { taken.append(CGRect(x: route.end.x - arrowLength, y: route.end.y - arrowLength, width: 2 * arrowLength, height: 2 * arrowLength)) }
            let lineColor = diagram.string(relation.lineColor)
            let painting = C4BoundaryFills.painting(of: route, lineColor: lineColor, ownColor: colors.color(lineColor, property: "stroke"), fills: fills)
            relations.append(C4RoutedRelation(relationIndex: relationIndex, route: route, pointsAtStart: pointsAtStart, pointsAtEnd: pointsAtEnd,
                                              lineColor: painting.lineColor, textColor: colors.color(diagram.string(relation.textColor), property: "color"),
                                              isCased: painting.isCased))
        }
        squeezedCount = router.lanes.squeezedCount
    }

    /// The box of each relation's two ends: a shape's or else a boundary's of that alias, among those drawn, found by the
    /// aliases' interned names.
    private func relationEnds() throws(C4LayoutError) -> [(Int, Int)] {
        var boxByName = [Int](repeating: -1, count: diagram.nameCount)
        for (box, shapeIndex) in shapeOrder.enumerated() {
            let element = diagram.shapeRecords[shapes[shapeIndex].shapeIndex].element
            if element.aliasArgument < 0 { boxByName[Int(element.name)] = box }
        }
        var isTaken = [Bool](repeating: false, count: diagram.nameCount)
        for shape in diagram.shapeRecords where shape.element.aliasArgument < 0 { isTaken[Int(shape.element.name)] = true }
        for (groupIndex, group) in groups.enumerated() {
            let element = diagram.boundaryRecords[group.boundaryIndex].element
            guard let box = groupBoxIndices[groupIndex], element.aliasArgument < 0, !isTaken[Int(element.name)] else { continue }
            boxByName[Int(element.name)] = box
            isTaken[Int(element.name)] = true
        }
        return try diagram.relationRecords.map { relation throws(C4LayoutError) in
            guard relation.fromArgument < 0, relation.toArgument < 0, case let source = boxByName[Int(relation.fromName)], source >= 0,
                  case let target = boxByName[Int(relation.toName)], target >= 0 else {
                throw .relationToUnknownElement(from: diagram.text(relation.from), to: diagram.text(relation.to))
            }
            return (source, target)
        }
    }

    /// The boundaries whose style fills them, by their group.
    private func boundaryFills() -> [C4BoundaryFill] {
        groups.indices.compactMap { groupIndex in
            guard let box = groupBoxIndices[groupIndex] else { return nil }
            let element = diagram.boundaryRecords[groups[groupIndex].boundaryIndex].element
            guard !element.backgroundColor.isNoneOrEmpty else { return nil }
            let look = C4ElementLook(backgroundColor: diagram.string(element.backgroundColor), borderColor: nil, fontColor: nil)
            return look.paintsFill ? C4BoundaryFill(frame: boxes[box].frame, look: look) : nil
        }
    }
}
