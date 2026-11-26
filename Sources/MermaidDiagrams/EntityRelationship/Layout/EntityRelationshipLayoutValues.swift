/**
 * File: EntityRelationshipLayoutValues.swift
 * ------------------------------------------
 * Layer: Core
 * Description: An entity relationship layout made of the values a host reads of one (entities, relationships, title,
 *              groups): their blocks' lines copied into the layout's lines and their paths' segments into its list, so
 *              that the layout reads back as those values and is drawn as they are.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics

extension EntityRelationshipLayout {
    /// The layout of these values, as a layout made in code or by an older engine gives them.
    init(size: CGSize, font: DiagramFont, entities: [EntityRelationshipLayoutEntity], relationships: [EntityRelationshipLayoutRelationship],
         title: DiagramTextBlock?, subgraphs: [FlowchartLayoutCluster] = []) {
        var lines = DiagramMeasuredLines()
        func measured(_ block: DiagramTextBlock) -> DiagramMeasuredText {
            var text = DiagramFlatTextMeasuring.copied(block, into: &lines)
            text.center = block.center
            return text
        }
        var placedEntities: [EntityRelationshipPlacedEntity] = []
        var rows: [EntityRelationshipPlacedRow] = []
        var cells: [EntityRelationshipPlacedCell] = []
        for entity in entities {
            let firstRow = rows.count
            for row in entity.rows {
                let firstCell = cells.count
                for cell in row.texts { cells.append(EntityRelationshipPlacedCell(column: Self.number(of: cell.column), text: measured(cell.text))) }
                rows.append(EntityRelationshipPlacedRow(frame: row.frame, firstCellText: Int32(firstCell), cellTextCount: Int32(cells.count - firstCell)))
            }
            placedEntities.append(EntityRelationshipPlacedEntity(frame: entity.frame, name: measured(entity.name), firstRow: Int32(firstRow),
                                                                 rowCount: Int32(rows.count - firstRow)))
        }
        var segments: [DiagramPathSegment] = []
        var placedRelationships: [EntityRelationshipPlacedRelationship] = []
        for relationship in relationships {
            let firstSegment = segments.count
            segments.append(contentsOf: relationship.path.segments)
            let label = relationship.label.map(measured)
            placedRelationships.append(EntityRelationshipPlacedRelationship(
                identification: relationship.identification, start: relationship.path.start, firstSegment: Int32(firstSegment),
                segmentCount: Int32(relationship.path.segments.count), firstEntityMark: relationship.firstEntityMark,
                secondEntityMark: relationship.secondEntityMark, hasLabel: label != nil,
                label: label ?? DiagramMeasuredText(firstLine: 0, lineCount: 0, width: 0, height: 0, lineHeight: 0, fontSize: 0)))
        }
        let placedTitle = title.map(measured)
        self.init(size: size, font: font, lines: lines, source: [], placedEntities: placedEntities, placedRows: rows, placedCells: cells,
                  placedRelationships: placedRelationships, segments: segments, placedTitle: placedTitle, subgraphs: subgraphs)
    }

    /// A column's number, its place in `EntityRelationshipColumn`'s order.
    private static func number(of column: EntityRelationshipColumn) -> Int8 {
        switch column {
        case .type: 0
        case .name: 1
        case .keys: 2
        case .comment: 3
        }
    }
}

extension EntityRelationshipLayoutEntity {
    func translated(by offset: CGVector) -> EntityRelationshipLayoutEntity {
        EntityRelationshipLayoutEntity(frame: frame.offsetBy(dx: offset.dx, dy: offset.dy), name: name.translated(by: offset),
                                       rows: rows.map { row in row.translated(by: offset) })
    }
}

extension EntityRelationshipLayoutRow {
    func translated(by offset: CGVector) -> EntityRelationshipLayoutRow {
        EntityRelationshipLayoutRow(frame: frame.offsetBy(dx: offset.dx, dy: offset.dy), texts: texts.map { cell in
            EntityRelationshipLayoutCellText(column: cell.column, text: cell.text.translated(by: offset))
        })
    }
}
