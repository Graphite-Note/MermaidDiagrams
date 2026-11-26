/**
 * File: EntityRelationshipPageAssembly.swift
 * ------------------------------------------
 * Layer: Core
 * Description: Puts a placed entity relationship diagram on the page: each relationship's line written once into the
 *              layout's list of segments, its marks and label kept in a span of the thread's arena, the loops beside
 *              their boxes, everything moved inside the padding below the title when the drawing's bounds are known.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.8
 * Date: 26/11/2026
 */

import CoreGraphics

/// Puts a placed entity relationship diagram on the page: boxes at their centers, relationships from one box's side
/// to the other's through their passing points, running straight out of each box for a mark's length before they
/// curve, loops beside their boxes, then everything moved inside the padding below the title. Each relationship's line
/// is written once into `segments`, around the layout's origin, and moved where it stands once the drawing's bounds give
/// the offset, as 0.7.0 moved each path; the centers, the placed relationships and the loops' reaches live in the
/// calling thread's arena.
struct EntityRelationshipPageAssembly {
    /// The diagram's relationships, and how many entities it has.
    let relationshipRecords: [EntityRelationshipRelationshipRecord]
    let entityCount: Int
    let measured: EntityRelationshipMeasurement
    let axes: FlowchartFlowAxes
    let arena: DiagramScratchArena
    /// By entity: its box's center.
    var boxCenters: ScratchSpan<CGPoint> = .empty
    /// By relationship: the relationship placed, where `isPlaced` says.
    let relationships: ScratchSpan<EntityRelationshipPlacedRelationship>
    let isPlaced: ScratchSpan<Bool>
    var segments: [DiagramPathSegment] = []
    /// For a diagram laid out in its groups' boxes: by entity, the group it stands for (an entity not drawn), -1 for none,
    /// and the size of that group's box, which its loops hang off; empty spans for a diagram without groups.
    var representedSubgraphs: ScratchSpan<Int32> = .empty
    var representedBoxSizes: ScratchSpan<CGSize> = .empty
    /// The points every relationship placed through boxes passes, one after the other: where they cross groups' tops.
    var relationshipPoints: ScratchList<CGPoint>
    /// The groups' boxes.
    var subgraphBoxes: [FlowchartLayoutCluster] = []
    /// How far beyond its box each group's loops reach, which the drawing makes room for as Pele widens it.
    var loopReaches: ScratchList<CGRect>
    /// By relationship: whether it loops off a group's box, whose label takes no room beyond its reach.
    let isGroupLoop: ScratchSpan<Bool>

    /// A route whose two ends are this close, and not in line, curves from box to box without straight runs.
    static let shortestRouteWithStraightRuns = 3 * EntityRelationshipCardinalityMark.length

    init(model: EntityRelationshipModel, measured: EntityRelationshipMeasurement, axes: FlowchartFlowAxes, arena: DiagramScratchArena) {
        relationshipRecords = model.relationships
        entityCount = model.entities.count
        self.measured = measured
        self.axes = axes
        self.arena = arena
        relationships = arena.uninitializedSpan(count: model.relationships.count)
        isPlaced = arena.span(count: model.relationships.count, repeating: false)
        isGroupLoop = arena.span(count: model.relationships.count, repeating: false)
        relationshipPoints = arena.list(capacity: 0, of: CGPoint.self)
        loopReaches = arena.list(capacity: 0, of: CGRect.self)
        segments.reserveCapacity(5 * model.relationships.count)
    }

    /// Whether entity `index` stands for a group: it is not drawn, its group's box is.
    func standsForGroup(_ index: Int) -> Bool {
        index < representedSubgraphs.count && representedSubgraphs[index] >= 0
    }

    /// The boxes of a diagram laid out in ranks, at their flat nodes' centers.
    mutating func placeBoxes(flowNodes: ScratchSpan<LayeredFlatNode>) {
        boxCenters = arena.uninitializedSpan(count: flowNodes.count)
        for node in 0..<flowNodes.count { boxCenters[node] = axes.pagePoint(CGPoint(x: flowNodes[node].x, y: flowNodes[node].y)) }
    }

    /// Relationship `index` through `points`: its line written into the segments (each segment along the flow, or along
    /// `segmentAxes[i]` when given), its marks where it meets its boxes, its label at `labelCenter`.
    mutating func setRelationship(at index: Int, along points: ScratchSpan<CGPoint>, segmentAxes: ScratchSpan<Bool>?, labelCenter: CGPoint) {
        let relationship = relationshipRecords[index]
        let first = points[0]
        let last = points[points.count - 1]
        let firstSegment = segments.count
        let drawn = EntityRelationshipRouteSegments.append(through: points, flowIsVertical: axes.flowIsVertical, axes: segmentAxes, into: &segments)
        relationships[index] = EntityRelationshipPlacedRelationship(
            identification: relationship.identification, start: drawn.start, firstSegment: Int32(firstSegment),
            segmentCount: Int32(segments.count - firstSegment),
            firstEntityMark: EntityRelationshipCardinalityMark(cardinality: relationship.firstEntityCardinality, tip: first,
                                                               direction: CGVector(dx: -drawn.startDirection.dx, dy: -drawn.startDirection.dy)),
            secondEntityMark: EntityRelationshipCardinalityMark(cardinality: relationship.secondEntityCardinality, tip: last, direction: drawn.endDirection),
            hasLabel: measured.labels[index].lineCount > 0, label: measured.labels[index].centered(at: labelCenter))
        isPlaced[index] = true
    }

    /// The loops of every entity that has relationships with itself; a group's off the right side of its box, the
    /// drawing widened by their reach, as Pele hangs them (`er/render.ts`).
    mutating func placeSelfRelationships() {
        for entity in 0..<entityCount {
            let loops = measured.loopIndices(of: entity)
            guard !loops.isEmpty else { continue }
            let isGroup = standsForGroup(entity)
            let boxSize = isGroup ? representedBoxSizes[entity] : measured.boxes[entity].size
            let leavesBelow = measured.loopsLeaveBelow[entity]
            if isGroup {
                let measured = measured
                let reach = EntityRelationshipSelfLoops.room(labelSizes: loops.lazy.map { position in
                    measured.labelSize(of: Int(measured.loopRelationships[position]))
                }, leavesBelow: false)
                loopReaches.append(CGRect(x: boxCenters[entity].x + boxSize.width / 2, y: boxCenters[entity].y, width: reach, height: 0))
                for position in loops { isGroupLoop[Int(measured.loopRelationships[position])] = true }
            }
            // The bands laid along the side as 0.7.0 laid them: added up in order, scaled to fit, each loop in its band.
            var total: CGFloat = 0
            for position in loops { total += measured.loopBands[Int(measured.loopRelationships[position])] }
            let scale = EntityRelationshipSelfLoops.scale(total: total, boxSize: boxSize, leavesBelow: leavesBelow)
            var along = -total * scale / 2
            for position in loops {
                let index = Int(measured.loopRelationships[position])
                let scaledBand = measured.loopBands[index] * scale
                let loop = EntityRelationshipSelfLoops.loop(center: boxCenters[entity], boxSize: boxSize, offsetAlongSide: along + scaledBand / 2,
                                                            band: scaledBand, labelSize: measured.labelSize(of: index), leavesBelow: leavesBelow)
                placeLoop(loop, at: index)
                along += scaledBand
            }
        }
    }

    /// Relationship `index`, a loop: its three segments, its marks where it leaves and comes back, its label.
    private mutating func placeLoop(_ loop: EntityRelationshipSelfLoops.Loop, at index: Int) {
        let relationship = relationshipRecords[index]
        let firstSegment = segments.count
        segments.append(loop.out)
        segments.append(loop.around)
        segments.append(loop.back)
        relationships[index] = EntityRelationshipPlacedRelationship(
            identification: relationship.identification, start: loop.start, firstSegment: Int32(firstSegment), segmentCount: 3,
            firstEntityMark: EntityRelationshipCardinalityMark(cardinality: relationship.firstEntityCardinality, tip: loop.leavePoint, direction: loop.intoBox),
            secondEntityMark: EntityRelationshipCardinalityMark(cardinality: relationship.secondEntityCardinality, tip: loop.backPoint, direction: loop.intoBox),
            hasLabel: loop.labelCenter != nil && measured.labels[index].lineCount > 0,
            label: measured.labels[index].centered(at: loop.labelCenter ?? .zero))
        isPlaced[index] = true
    }
}
