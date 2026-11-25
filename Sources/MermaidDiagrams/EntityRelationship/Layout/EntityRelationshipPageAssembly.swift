/**
 * File: EntityRelationshipPageAssembly.swift
 * ------------------------------------------
 * Layer: Core
 * Description: Puts a placed entity relationship diagram on the page.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.5
 * Date: 25/11/2026
 */

import CoreGraphics

/// Puts a placed entity relationship diagram on the page: boxes at their centers, relationships from one box's side
/// to the other's through their passing points, running straight out of each box for a mark's length before they
/// curve, loops beside their boxes, then everything moved inside the padding below the title.
struct EntityRelationshipPageAssembly {
    let diagram: EntityRelationshipDiagram
    let measured: EntityRelationshipMeasurement
    let axes: FlowchartFlowAxes
    var boxCenters: [CGPoint] = []
    /// By relationship index; nil until the relationship is placed.
    private var relationships: [EntityRelationshipLayoutRelationship?]
    /// For a diagram laid out in its groups' boxes: the group each entity stands for (an entity not drawn), or nil.
    var representedSubgraphs: [Int?] = []
    /// For each relationship placed through boxes, the points it passes: where it crosses a group's top.
    var relationshipPoints: [[CGPoint]] = []
    /// The groups' boxes.
    var subgraphBoxes: [FlowchartLayoutCluster] = []
    /// For each entity that stands for a group, the size of the group's box, which its loops hang off.
    var representedBoxSizes: [Int: CGSize] = [:]
    /// How far beyond its box each group's loops reach, which the drawing makes room for as Pele widens it.
    private var loopReaches: [CGRect] = []
    /// The relationships that loop off a group's box, whose labels take no room beyond their reach.
    private var groupLoopIndices: Set<Int> = []

    /// A route whose two ends are this close, and not in line, curves from box to box without straight runs.
    static let shortestRouteWithStraightRuns = 3 * EntityRelationshipCardinalityMark.length

    init(diagram: EntityRelationshipDiagram, measured: EntityRelationshipMeasurement, axes: FlowchartFlowAxes) {
        self.diagram = diagram
        self.measured = measured
        self.axes = axes
        relationships = Array(repeating: nil, count: diagram.relationships.count)
    }

    /// The boxes of a diagram laid out in ranks, at their flat nodes' centers.
    mutating func placeBoxes(flowNodes: ScratchSpan<LayeredFlatNode>) {
        boxCenters.reserveCapacity(flowNodes.count)
        for node in flowNodes { boxCenters.append(axes.pagePoint(CGPoint(x: node.x, y: node.y))) }
    }

    /// The relationships between two different entities, along their routes. `layeredIndices[i]` is the relationship of
    /// the flat layout's `i`-th edge, whose route runs from its first entity's center to its second's through its
    /// path's inner points.
    mutating func placeRelationships(layeredIndices: ScratchSpan<Int>, nodes: ScratchSpan<LayeredFlatNode>, edges laidOut: ScratchSpan<LayeredSpanEdge>,
                                     points: ScratchSpan<CGPoint>) {
        let routes = RankedRoutes(nodes: nodes, edges: laidOut, points: points)
        let ends = rankedEnds(layeredIndices: layeredIndices, routes: routes)
        var boxSizes: [CGSize] = []
        boxSizes.reserveCapacity(measured.boxes.count)
        for box in measured.boxes { boxSizes.append(box.size) }
        let ports = EntityRelationshipEdgePorts(ends: ends, relationshipCount: diagram.relationships.count, boxCenters: boxCenters, boxSizes: boxSizes)
        for layeredIndex in 0..<layeredIndices.count {
            let index = layeredIndices[layeredIndex]
            guard let start = ports.firstEntityPoints[index], let end = ports.secondEntityPoints[index] else { continue }
            let count = routes.count(of: layeredIndex)
            // Room for the two straight runs' points `relationship(at:along:)` adds.
            var routePoints: [CGPoint] = []
            routePoints.reserveCapacity(count + 2)
            routePoints.append(start)
            for pointIndex in 1..<(count - 1) { routePoints.append(axes.pagePoint(routes.point(pointIndex, count: count, of: layeredIndex))) }
            routePoints.append(end)
            let edge = laidOut[layeredIndex]
            let labelCenter = edge.labelWidth > 0 ? axes.pagePoint(edge.labelCenter) : CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
            let startSide = ends[2 * layeredIndex].side
            let endSide = ends[2 * layeredIndex + 1].side
            relationships[index] = relationship(at: index, along: &routePoints, leaving: EntityRelationshipEdgePorts.outward(from: startSide),
                                                arriving: EntityRelationshipEdgePorts.outward(from: endSide), labelCenter: labelCenter)
        }
    }

    /// The flat layout's routes in flow space, each from its first entity's center to its second's through its path's
    /// inner points.
    private struct RankedRoutes {
        let nodes: ScratchSpan<LayeredFlatNode>
        let edges: ScratchSpan<LayeredSpanEdge>
        let points: ScratchSpan<CGPoint>

        func count(of layeredIndex: Int) -> Int {
            let edge = edges[layeredIndex]
            return edge.pointStart >= 0 && edge.pointCount > 2 ? edge.pointCount : 2
        }

        /// The route's point `index`, of `count`: the centers at its ends, the path's inner points between.
        func point(_ index: Int, count: Int, of layeredIndex: Int) -> CGPoint {
            let edge = edges[layeredIndex]
            if index == 0 { return CGPoint(x: nodes[edge.tail].x, y: nodes[edge.tail].y) }
            if index == count - 1 { return CGPoint(x: nodes[edge.head].x, y: nodes[edge.head].y) }
            return points[edge.pointStart + index]
        }
    }

    /// The two ends of each route on the sides of their boxes facing it, the first entity's then the second's.
    private func rankedEnds(layeredIndices: ScratchSpan<Int>, routes: RankedRoutes) -> [EntityRelationshipEdgePorts.End] {
        var ends: [EntityRelationshipEdgePorts.End] = []
        ends.reserveCapacity(2 * layeredIndices.count)
        for layeredIndex in 0..<layeredIndices.count {
            let index = layeredIndices[layeredIndex]
            let count = routes.count(of: layeredIndex)
            let first = routes.point(0, count: count, of: layeredIndex)
            let second = routes.point(1, count: count, of: layeredIndex)
            let beforeLast = routes.point(count - 2, count: count, of: layeredIndex)
            let last = routes.point(count - 1, count: count, of: layeredIndex)
            let relationship = diagram.relationships[index]
            ends.append(EntityRelationshipEdgePorts.End(relationshipIndex: index, isFirstEntityEnd: true, entity: relationship.firstEntityIndex,
                                                        side: second.y > first.y ? axes.downstreamSide : axes.upstreamSide, neighborAcross: second.x))
            ends.append(EntityRelationshipEdgePorts.End(relationshipIndex: index, isFirstEntityEnd: false, entity: relationship.secondEntityIndex,
                                                        side: beforeLast.y < last.y ? axes.upstreamSide : axes.downstreamSide, neighborAcross: beforeLast.x))
        }
        return ends
    }

    /// A relationship along `routed`, from the first box's side to the second's. `leaving` and `arriving` point out
    /// of the two boxes; the line runs along them for a mark's length before it curves, so that each mark sits on a
    /// straight run. The route is straightened and given its straight runs where it stands.
    private func relationship(at index: Int, along routed: inout [CGPoint], leaving: CGVector, arriving: CGVector,
                              labelCenter: CGPoint) -> EntityRelationshipLayoutRelationship {
        let first = routed[0]
        let last = routed[routed.count - 1]
        Self.straighten(&routed)
        let isDirect = routed.count == 2 && (Self.isInLine(first, last) || hypot(last.x - first.x, last.y - first.y) <= Self.shortestRouteWithStraightRuns)
        if !isDirect {
            let straight = EntityRelationshipCardinalityMark.length
            routed.insert(CGPoint(x: first.x + leaving.dx * straight, y: first.y + leaving.dy * straight), at: 1)
            routed.insert(CGPoint(x: last.x + arriving.dx * straight, y: last.y + arriving.dy * straight), at: routed.count - 1)
        }
        let drawn = DiagramRouteDrawing.path(through: routed, flowIsVertical: axes.flowIsVertical, startTrim: 0, endTrim: 0)
        let relationship = diagram.relationships[index]
        return EntityRelationshipLayoutRelationship(
            identification: relationship.identification, path: drawn.path,
            firstEntityMark: EntityRelationshipCardinalityMark(cardinality: relationship.firstEntityCardinality, tip: first,
                                                               direction: CGVector(dx: -drawn.startDirection.dx, dy: -drawn.startDirection.dy)),
            secondEntityMark: EntityRelationshipCardinalityMark(cardinality: relationship.secondEntityCardinality, tip: last, direction: drawn.endDirection),
            label: centered(measured.labels[index], at: labelCenter))
    }

    /// A relationship through `points`, each segment an S along the flow `segmentsRunVertically` gives it.
    mutating func setRelationship(at index: Int, along points: [CGPoint], segmentsRunVertically: [Bool], labelCenter: CGPoint) {
        let drawn = DiagramRouteDrawing.path(through: points, segmentsRunVertically: segmentsRunVertically, startTrim: 0, endTrim: 0)
        let relationship = diagram.relationships[index]
        let first = points[0]
        let last = points[points.count - 1]
        relationships[index] = EntityRelationshipLayoutRelationship(
            identification: relationship.identification, path: drawn.path,
            firstEntityMark: EntityRelationshipCardinalityMark(cardinality: relationship.firstEntityCardinality, tip: first,
                                                               direction: CGVector(dx: -drawn.startDirection.dx, dy: -drawn.startDirection.dy)),
            secondEntityMark: EntityRelationshipCardinalityMark(cardinality: relationship.secondEntityCardinality, tip: last, direction: drawn.endDirection),
            label: centered(measured.labels[index], at: labelCenter))
    }

    /// The loops of every entity that has relationships with itself; a group's off the right side of its box, the
    /// drawing widened by their reach, as Pele hangs them (`er/render.ts`).
    mutating func placeSelfRelationships() {
        for (entity, indices) in measured.selfRelationshipIndices.enumerated() where !indices.isEmpty {
            let labelSizes = indices.map { index in measured.labels[index]?.size }
            let boxSize = representedBoxSizes[entity] ?? measured.boxes[entity].size
            if representedBoxSizes[entity] != nil {
                let reach = EntityRelationshipSelfLoops.room(labelSizes: labelSizes, leavesBelow: false)
                loopReaches.append(CGRect(x: boxCenters[entity].x + boxSize.width / 2, y: boxCenters[entity].y, width: reach, height: 0))
                groupLoopIndices.formUnion(indices)
            }
            let loops = EntityRelationshipSelfLoops.loops(center: boxCenters[entity], boxSize: boxSize, bands: measured.loopBands[entity],
                                                          labelSizes: labelSizes, leavesBelow: measured.loopsLeaveBelow[entity])
            for (loop, index) in zip(loops, indices) {
                let relationship = diagram.relationships[index]
                relationships[index] = EntityRelationshipLayoutRelationship(
                    identification: relationship.identification, path: loop.path,
                    firstEntityMark: EntityRelationshipCardinalityMark(cardinality: relationship.firstEntityCardinality, tip: loop.leave,
                                                                       direction: loop.intoBox),
                    secondEntityMark: EntityRelationshipCardinalityMark(cardinality: relationship.secondEntityCardinality, tip: loop.back,
                                                                        direction: loop.intoBox),
                    label: loop.labelCenter.flatMap { center in centered(measured.labels[index], at: center) })
            }
        }
    }

    private func centered(_ text: DiagramTextBlock?, at center: CGPoint) -> DiagramTextBlock? {
        guard var text else { return nil }
        text.center = center
        return text
    }

    /// The route without each point that lies between its neighbours on one straight vertical or horizontal run, so
    /// that a relationship whose route runs straight is one straight line; the points kept move to the front of the
    /// list, which keeps its room. A point is compared with the last one kept and with the next one, as yet unmoved.
    private static func straighten(_ points: inout [CGPoint]) {
        var keptCount = 1
        for index in 1..<points.count {
            let point = points[index]
            if index + 1 < points.count {
                let previous = points[keptCount - 1]
                let next = points[index + 1]
                let isOnVerticalRun = abs(previous.x - point.x) < 0.01 && abs(point.x - next.x) < 0.01
                let isOnHorizontalRun = abs(previous.y - point.y) < 0.01 && abs(point.y - next.y) < 0.01
                if isOnVerticalRun || isOnHorizontalRun { continue }
            }
            points[keptCount] = point
            keptCount += 1
        }
        points.removeLast(points.count - keptCount)
    }

    /// Two points are in line when they share a coordinate, to a hundredth of a point.
    private static func isInLine(_ first: CGPoint, _ second: CGPoint) -> Bool {
        abs(first.x - second.x) < 0.01 || abs(first.y - second.y) < 0.01
    }

    /// The finished layout: everything moved so that the drawing starts `padding` from the top left, below the
    /// title, and centered under the title when the title is wider. Each part is placed once where it is moved to; the
    /// relationships are taken out of the assembly, so that each path is moved where it stands rather than copied.
    mutating func finished(font: DiagramFont, title: DiagramTextBlock?, padding: CGFloat, titleGap: CGFloat) -> EntityRelationshipLayout {
        // An entity that stands for a group is its box, not an entity: each drawn entity's top left corner.
        var drawnEntities: [(entity: Int, origin: CGVector)] = []
        drawnEntities.reserveCapacity(measured.boxes.count)
        for (entity, box) in measured.boxes.enumerated() where representedSubgraphs.isEmpty || representedSubgraphs[entity] == nil {
            drawnEntities.append((entity, CGVector(dx: boxCenters[entity].x - box.size.width / 2, dy: boxCenters[entity].y - box.size.height / 2)))
        }
        let bounds = drawingBounds(drawnEntities: drawnEntities)
        let titleSize = title?.size ?? .zero
        let innerWidth = max(bounds.width, titleSize.width)
        let titleHeight = title == nil ? 0 : titleSize.height + titleGap
        let offset = CGVector(dx: padding + (innerWidth - bounds.width) / 2 - bounds.minX, dy: padding + titleHeight - bounds.minY)
        let size = CGSize(width: (innerWidth + 2 * padding).rounded(.up), height: (bounds.height + titleHeight + 2 * padding).rounded(.up))
        var placedTitle = title
        placedTitle?.center = CGPoint(x: size.width / 2, y: padding + titleSize.height / 2)
        var entities: [EntityRelationshipLayoutEntity] = []
        entities.reserveCapacity(drawnEntities.count)
        for drawn in drawnEntities { entities.append(measured.boxes[drawn.entity].placed(origin: drawn.origin, offset: offset)) }
        var placedRelationships: [EntityRelationshipLayoutRelationship] = []
        placedRelationships.reserveCapacity(relationships.count)
        for index in relationships.indices {
            guard var placed = relationships[index].take() else { continue }
            placed.translate(by: offset)
            placedRelationships.append(placed)
        }
        var placedSubgraphs = subgraphBoxes
        for index in placedSubgraphs.indices { placedSubgraphs[index] = placedSubgraphs[index].translated(by: offset) }
        return EntityRelationshipLayout(size: size, font: font, entities: entities, relationships: placedRelationships, title: placedTitle,
                                        subgraphs: placedSubgraphs)
    }

    /// The rectangle the drawing covers: the drawn entities' boxes, then the relationships but a group's loops, then those
    /// loops without their labels, their labels, the groups' boxes and the loops' reach, each taken in that order.
    private func drawingBounds(drawnEntities: [(entity: Int, origin: CGVector)]) -> CGRect {
        var bounds = CGRect.null
        for drawn in drawnEntities { bounds = bounds.union(measured.boxes[drawn.entity].frame(origin: drawn.origin)) }
        // A group's loops widen the drawing by their reach, Pele's, which holds their labels without the room others take.
        for index in relationships.indices where !groupLoopIndices.contains(index) {
            if let relationship = relationships[index] { bounds = EntityRelationshipLayoutBounds.union(bounds, relationship: relationship) }
        }
        bounds = bounds.isNull ? .zero : bounds
        let groupLoops = groupLoopIndices.compactMap { index in relationships[index] }
        if !groupLoops.isEmpty {
            var loopBounds = CGRect.null
            for loop in groupLoops { loopBounds = EntityRelationshipLayoutBounds.union(loopBounds, relationship: loop, includesLabel: false) }
            bounds = bounds.union(loopBounds.isNull ? .zero : loopBounds)
        }
        for loop in groupLoops { if let label = loop.label { bounds = bounds.union(label.frame) } }
        for box in subgraphBoxes { bounds = bounds.union(box.frame) }
        for reach in loopReaches { bounds = bounds.union(reach) }
        return bounds
    }
}
