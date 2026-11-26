/**
 * File: EntityRelationshipPageFinishing.swift
 * -------------------------------------------
 * Layer: Core
 * Description: A placed entity relationship diagram finished on its page: the rectangle its drawing covers, the offset
 *              that puts it inside the padding below the title, and the layout's lists written with everything moved
 *              once where it stands.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics

extension EntityRelationshipPageAssembly {
    /// The finished layout: everything moved so that the drawing starts `padding` from the top left, below the title,
    /// and centered under the title when the title is wider. Each part is placed once where it is moved to; the
    /// relationships' segments are moved where they stand rather than copied.
    mutating func finished(font: DiagramFont, title: DiagramMeasuredText?, padding: CGFloat, titleGap: CGFloat, source: [UInt8]) -> EntityRelationshipLayout {
        let bounds = drawingBounds()
        let titleSize = title?.size ?? .zero
        let innerWidth = max(bounds.width, titleSize.width)
        let titleHeight = title == nil ? 0 : titleSize.height + titleGap
        let offset = CGVector(dx: padding + (innerWidth - bounds.width) / 2 - bounds.minX, dy: padding + titleHeight - bounds.minY)
        let size = CGSize(width: (innerWidth + 2 * padding).rounded(.up), height: (bounds.height + titleHeight + 2 * padding).rounded(.up))
        var placedTitle = title
        placedTitle?.center = CGPoint(x: size.width / 2, y: padding + titleSize.height / 2)
        let (entities, rows, cells) = placedEntities(offset: offset)
        var placedCount = 0
        for index in 0..<isPlaced.count where isPlaced[index] { placedCount += 1 }
        var placedRelationships: [EntityRelationshipPlacedRelationship] = []
        placedRelationships.reserveCapacity(placedCount)
        for index in 0..<isPlaced.count where isPlaced[index] {
            var placed = relationships[index]
            EntityRelationshipRouteSegments.translate(placed.segmentIndices, of: &segments, by: offset)
            placed.start = placed.start.translated(by: offset)
            placed.firstEntityMark = placed.firstEntityMark.translated(by: offset)
            placed.secondEntityMark = placed.secondEntityMark.translated(by: offset)
            placed.label = placed.label.translated(by: offset)
            placedRelationships.append(placed)
        }
        var placedSubgraphs = subgraphBoxes
        for index in placedSubgraphs.indices { placedSubgraphs[index] = placedSubgraphs[index].translated(by: offset) }
        return EntityRelationshipLayout(size: size, font: font, lines: measured.lines, source: source, placedEntities: entities, placedRows: rows,
                                        placedCells: cells, placedRelationships: placedRelationships, segments: segments, placedTitle: placedTitle,
                                        subgraphs: placedSubgraphs)
    }

    /// The drawn entities' boxes, rows and cells' lines, moved by `offset`.
    private func placedEntities(offset: CGVector) -> ([EntityRelationshipPlacedEntity], [EntityRelationshipPlacedRow], [EntityRelationshipPlacedCell]) {
        var entities: [EntityRelationshipPlacedEntity] = []
        entities.reserveCapacity(measured.boxes.count)
        var rows: [EntityRelationshipPlacedRow] = []
        rows.reserveCapacity(measured.rowHeights.count)
        var cells: [EntityRelationshipPlacedCell] = []
        cells.reserveCapacity(measured.cells.count)
        for entity in 0..<measured.boxes.count where !standsForGroup(entity) {
            let box = measured.boxes[entity]
            let origin = Self.origin(of: box, at: boxCenters[entity])
            let firstRow = rows.count
            EntityRelationshipAttributeTable.placeRows(of: box, inset: EntityRelationshipBoxMeasurement.cellHorizontalPadding, measured: measured,
                                                       movedBy: origin, then: offset, rows: &rows, cellTexts: &cells)
            entities.append(EntityRelationshipPlacedEntity(frame: box.frame(origin: origin).offsetBy(dx: offset.dx, dy: offset.dy),
                                                           name: box.name.translated(by: origin).translated(by: offset), firstRow: Int32(firstRow),
                                                           rowCount: Int32(rows.count - firstRow)))
        }
        return (entities, rows, cells)
    }

    /// The top left corner of `box` centered on `center`.
    private static func origin(of box: EntityRelationshipMeasuredBox, at center: CGPoint) -> CGVector {
        CGVector(dx: center.x - box.size.width / 2, dy: center.y - box.size.height / 2)
    }

    /// The rectangle the drawing covers: the drawn entities' boxes, then the relationships but a group's loops, then those
    /// loops without their labels, their labels, the groups' boxes and the loops' reach, each taken in that order.
    private func drawingBounds() -> CGRect {
        var bounds = CGRect.null
        for entity in 0..<measured.boxes.count where !standsForGroup(entity) {
            bounds = bounds.union(measured.boxes[entity].frame(origin: Self.origin(of: measured.boxes[entity], at: boxCenters[entity])))
        }
        // A group's loops widen the drawing by their reach, Pele's, which holds their labels without the room others take.
        var hasGroupLoops = false
        for index in 0..<isPlaced.count where isPlaced[index] {
            guard !isGroupLoop[index] else {
                hasGroupLoops = true
                continue
            }
            bounds = EntityRelationshipLayoutBounds.union(bounds, relationship: relationships[index], segments: segments)
        }
        bounds = bounds.isNull ? .zero : bounds
        if hasGroupLoops {
            var loopBounds = CGRect.null
            for index in 0..<isPlaced.count where isPlaced[index] && isGroupLoop[index] {
                loopBounds = EntityRelationshipLayoutBounds.union(loopBounds, relationship: relationships[index], segments: segments, includesLabel: false)
            }
            bounds = bounds.union(loopBounds.isNull ? .zero : loopBounds)
            for index in 0..<isPlaced.count where isPlaced[index] && isGroupLoop[index] && relationships[index].hasLabel {
                bounds = bounds.union(relationships[index].label.frame)
            }
        }
        for box in subgraphBoxes { bounds = bounds.union(box.frame) }
        for reach in loopReaches { bounds = bounds.union(reach) }
        return bounds
    }
}
