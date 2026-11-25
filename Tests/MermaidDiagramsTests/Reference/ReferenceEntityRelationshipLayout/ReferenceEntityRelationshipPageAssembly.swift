/**
 * File: ReferenceEntityRelationshipPageAssembly.swift
 * ---------------------------------------------------
 * Layer: Tests
 * Description: The 0.7.0 EntityRelationshipPageAssembly kept as the reference the 0.8.0 layout is checked against:
 *              puts a placed entity relationship diagram on the page.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// Puts a placed entity relationship diagram on the page: boxes at their centers, relationships from one box's side
/// to the other's through their passing points, running straight out of each box for a mark's length before they
/// curve, loops beside their boxes, then everything moved inside the padding below the title.
struct ReferenceEntityRelationshipPageAssembly {
    let diagram: EntityRelationshipDiagram
    let measured: ReferenceEntityRelationshipMeasurement
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

    init(diagram: EntityRelationshipDiagram, measured: ReferenceEntityRelationshipMeasurement, axes: FlowchartFlowAxes) {
        self.diagram = diagram
        self.measured = measured
        self.axes = axes
        relationships = Array(repeating: nil, count: diagram.relationships.count)
    }

    mutating func placeBoxes(flowCenters: [CGPoint]) {
        boxCenters = flowCenters.map(axes.pagePoint)
    }

    /// The relationships between two different entities, along their routes. `layeredIndices[i]` is the
    /// relationship of the placement's `i`-th route.
    mutating func placeRelationships(layeredIndices: [Int], placement: LayeredPlacement) {
        var ends: [ReferenceEntityRelationshipEdgePorts.End] = []
        for (layeredIndex, index) in layeredIndices.enumerated() {
            let route = placement.edgeRoutes[layeredIndex]
            let relationship = diagram.relationships[index]
            ends.append(ReferenceEntityRelationshipEdgePorts.End(relationshipIndex: index, isFirstEntityEnd: true, entity: relationship.firstEntityIndex,
                                                        side: route[1].y > route[0].y ? axes.downstreamSide : axes.upstreamSide,
                                                        neighborAcross: route[1].x))
            ends.append(ReferenceEntityRelationshipEdgePorts.End(relationshipIndex: index, isFirstEntityEnd: false, entity: relationship.secondEntityIndex,
                                                        side: route[route.count - 2].y < route[route.count - 1].y ? axes.upstreamSide : axes.downstreamSide,
                                                        neighborAcross: route[route.count - 2].x))
        }
        let ports = ReferenceEntityRelationshipEdgePorts(ends: ends, relationshipCount: diagram.relationships.count, boxCenters: boxCenters,
                                                boxSizes: measured.boxes.map(\.size))
        for (layeredIndex, index) in layeredIndices.enumerated() {
            guard let start = ports.firstEntityPoints[index], let end = ports.secondEntityPoints[index] else { continue }
            let route = placement.edgeRoutes[layeredIndex]
            let points = [start] + route.dropFirst().dropLast().map(axes.pagePoint) + [end]
            let labelCenter = placement.edgeLabelCenters[layeredIndex].map(axes.pagePoint) ?? CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
            let startSide = ends[2 * layeredIndex].side
            let endSide = ends[2 * layeredIndex + 1].side
            relationships[index] = relationship(at: index, along: points, leaving: ReferenceEntityRelationshipEdgePorts.outward(from: startSide),
                                                arriving: ReferenceEntityRelationshipEdgePorts.outward(from: endSide), labelCenter: labelCenter)
        }
    }

    /// A relationship along `points`, from the first box's side to the second's. `leaving` and `arriving` point out
    /// of the two boxes; the line runs along them for a mark's length before it curves, so that each mark sits on a
    /// straight run.
    private func relationship(at index: Int, along points: [CGPoint], leaving: CGVector, arriving: CGVector,
                              labelCenter: CGPoint) -> EntityRelationshipLayoutRelationship {
        var routed = Self.straightened(points)
        let first = points[0]
        let last = points[points.count - 1]
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
                let reach = ReferenceEntityRelationshipSelfLoops.room(labelSizes: labelSizes, leavesBelow: false)
                loopReaches.append(CGRect(x: boxCenters[entity].x + boxSize.width / 2, y: boxCenters[entity].y, width: reach, height: 0))
                groupLoopIndices.formUnion(indices)
            }
            let loops = ReferenceEntityRelationshipSelfLoops.loops(center: boxCenters[entity], boxSize: boxSize, bands: measured.loopBands[entity],
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
    /// that a relationship whose route runs straight is one straight line.
    private static func straightened(_ points: [CGPoint]) -> [CGPoint] {
        var kept = [points[0]]
        for index in 1..<points.count {
            let point = points[index]
            if index + 1 < points.count, let previous = kept.last {
                let next = points[index + 1]
                let isOnVerticalRun = abs(previous.x - point.x) < 0.01 && abs(point.x - next.x) < 0.01
                let isOnHorizontalRun = abs(previous.y - point.y) < 0.01 && abs(point.y - next.y) < 0.01
                if isOnVerticalRun || isOnHorizontalRun { continue }
            }
            kept.append(point)
        }
        return kept
    }

    /// Two points are in line when they share a coordinate, to a hundredth of a point.
    private static func isInLine(_ first: CGPoint, _ second: CGPoint) -> Bool {
        abs(first.x - second.x) < 0.01 || abs(first.y - second.y) < 0.01
    }

    /// The finished layout: everything moved so that the drawing starts `padding` from the top left, below the
    /// title, and centered under the title when the title is wider.
    func finished(font: DiagramFont, title: DiagramTextBlock?, padding: CGFloat, titleGap: CGFloat) -> EntityRelationshipLayout {
        // An entity that stands for a group is its box, not an entity.
        let drawnEntities = measured.boxes.enumerated().filter { entity, _ in representedSubgraphs.isEmpty || representedSubgraphs[entity] == nil }
        let entities = drawnEntities.map { entity, box in
            let origin = CGVector(dx: boxCenters[entity].x - box.size.width / 2, dy: boxCenters[entity].y - box.size.height / 2)
            return EntityRelationshipLayoutEntity(frame: CGRect(origin: .zero, size: box.size), name: box.name, rows: box.rows).translated(by: origin)
        }
        let placedRelationships = relationships.compactMap { relationship in relationship }
        // A group's loops widen the drawing by their reach, Pele's, which holds their labels without the room others take.
        let groupLoops = groupLoopIndices.compactMap { index in relationships[index] }
        let otherRelationships = relationships.indices.compactMap { index in groupLoopIndices.contains(index) ? nil : relationships[index] }
        var bounds = ReferenceEntityRelationshipLayoutBounds.union(entities: entities, relationships: otherRelationships)
        if !groupLoops.isEmpty {
            bounds = bounds.union(ReferenceEntityRelationshipLayoutBounds.union(entities: [], relationships: groupLoops.map { loop in
                EntityRelationshipLayoutRelationship(identification: loop.identification, path: loop.path, firstEntityMark: loop.firstEntityMark,
                                                     secondEntityMark: loop.secondEntityMark, label: nil)
            }))
        }
        for loop in groupLoops { if let label = loop.label { bounds = bounds.union(label.frame) } }
        for box in subgraphBoxes { bounds = bounds.union(box.frame) }
        for reach in loopReaches { bounds = bounds.union(reach) }
        let titleSize = title?.size ?? .zero
        let innerWidth = max(bounds.width, titleSize.width)
        let titleHeight = title == nil ? 0 : titleSize.height + titleGap
        let offset = CGVector(dx: padding + (innerWidth - bounds.width) / 2 - bounds.minX, dy: padding + titleHeight - bounds.minY)
        let size = CGSize(width: (innerWidth + 2 * padding).rounded(.up), height: (bounds.height + titleHeight + 2 * padding).rounded(.up))
        var placedTitle = title
        placedTitle?.center = CGPoint(x: size.width / 2, y: padding + titleSize.height / 2)
        return EntityRelationshipLayout(size: size, font: font, entities: entities.map { entity in entity.translated(by: offset) },
                                        relationships: placedRelationships.map { relationship in relationship.translated(by: offset) }, title: placedTitle,
                                        subgraphs: subgraphBoxes.map { box in box.translated(by: offset) })
    }
}
