/**
 * File: EntityRelationshipLayout.swift
 * ------------------------------------
 * Layer: Core
 * Description: An entity relationship diagram laid out on a page, with its groups' boxes: its entities, rows, cells'
 *              lines and relationships kept as placed records of measured texts over one list of lines and of path
 *              segments over one list, which the scene reads directly, with the entities, relationships and title as
 *              values made when a host asks.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.4
 * Date: 26/11/2026
 */

import CoreGraphics

/// An entity relationship diagram laid out on a page whose origin is the top left corner and whose y runs down, in
/// points. Drawing it needs only colors: every position, path and text measurement is here.
///
/// Its texts are measured texts of one list of lines (`DiagramMeasuredText`), its relationships' lines runs of one list
/// of segments, which the scene draws from directly; `entities`, `relationships` and `title` make the same texts as
/// `DiagramTextBlock`s and the same paths each time they are read.
public struct EntityRelationshipLayout: Sendable {
    public let size: CGSize
    /// The font the entities' names were measured in; attribute rows and labels are in the same font at their own
    /// `fontSize`.
    public let font: DiagramFont
    /// The lines of every text below: ranges of the diagram's text (`source`), or derived bytes.
    let lines: DiagramMeasuredLines
    let source: [UInt8]
    /// The entities drawn, their rows runs of `placedRows`, each row's lines runs of `placedCells`.
    let placedEntities: [EntityRelationshipPlacedEntity]
    let placedRows: [EntityRelationshipPlacedRow]
    let placedCells: [EntityRelationshipPlacedCell]
    /// The relationships in the order they are written, those of an entity with itself included, their lines runs of
    /// `segments`.
    let placedRelationships: [EntityRelationshipPlacedRelationship]
    let segments: [DiagramPathSegment]
    let placedTitle: DiagramMeasuredText?
    /// The `subgraph` groups' boxes, painted as a flowchart's groups are; empty for a diagram without groups.
    public internal(set) var subgraphs: [FlowchartLayoutCluster] = []

    init(size: CGSize, font: DiagramFont, lines: DiagramMeasuredLines, source: [UInt8], placedEntities: [EntityRelationshipPlacedEntity],
         placedRows: [EntityRelationshipPlacedRow], placedCells: [EntityRelationshipPlacedCell], placedRelationships: [EntityRelationshipPlacedRelationship],
         segments: [DiagramPathSegment], placedTitle: DiagramMeasuredText?, subgraphs: [FlowchartLayoutCluster]) {
        self.size = size
        self.font = font
        self.lines = lines
        self.source = source
        self.placedEntities = placedEntities
        self.placedRows = placedRows
        self.placedCells = placedCells
        self.placedRelationships = placedRelationships
        self.segments = segments
        self.placedTitle = placedTitle
        self.subgraphs = subgraphs
    }

    /// The entities' boxes, each with its name and rows, made when read.
    public var entities: [EntityRelationshipLayoutEntity] {
        placedEntities.map { entity in
            EntityRelationshipLayoutEntity(frame: entity.frame, name: block(of: entity.name), rows: placedRows[entity.rowIndices].map { row in
                EntityRelationshipLayoutRow(frame: row.frame, texts: placedCells[row.cellIndices].map { cell in
                    EntityRelationshipLayoutCellText(column: cell.textColumn, text: block(of: cell.text))
                })
            })
        }
    }

    /// The relationships in the order they are written, those of an entity with itself included, made when read.
    public var relationships: [EntityRelationshipLayoutRelationship] {
        placedRelationships.map { relationship in
            EntityRelationshipLayoutRelationship(identification: relationship.identification, path: path(of: relationship),
                                                 firstEntityMark: relationship.firstEntityMark, secondEntityMark: relationship.secondEntityMark,
                                                 label: relationship.hasLabel ? block(of: relationship.label) : nil)
        }
    }

    /// The diagram's title above it, or nil.
    public var title: DiagramTextBlock? { placedTitle.map(block(of:)) }

    /// A relationship's line, made from its segments.
    func path(of relationship: EntityRelationshipPlacedRelationship) -> DiagramPath {
        DiagramPath(start: relationship.start, segments: Array(segments[relationship.segmentIndices]))
    }

    /// `text`, a text of this layout's lines, as a block.
    func block(of text: DiagramMeasuredText) -> DiagramTextBlock {
        source.withUnsafeBufferPointer { source in DiagramTextBlock(text, of: lines, source: source) }
    }
}

extension EntityRelationshipLayout: Equatable {
    /// The same size, font, entities, relationships, title and groups.
    public static func == (left: EntityRelationshipLayout, right: EntityRelationshipLayout) -> Bool {
        left.size == right.size && left.font == right.font && left.entities == right.entities && left.relationships == right.relationships
            && left.title == right.title && left.subgraphs == right.subgraphs
    }
}

/// An entity placed: its box, its name, and its rows, `rowCount` of the layout's rows from `firstRow`.
struct EntityRelationshipPlacedEntity: Sendable {
    let frame: CGRect
    let name: DiagramMeasuredText
    let firstRow: Int32
    let rowCount: Int32

    var rowIndices: Range<Int> { Int(firstRow)..<Int(firstRow + rowCount) }
}

/// A row placed: its band, and the lines of its cells, `cellTextCount` of the layout's cells from `firstCellText`.
struct EntityRelationshipPlacedRow: Sendable {
    let frame: CGRect
    let firstCellText: Int32
    let cellTextCount: Int32

    var cellIndices: Range<Int> { Int(firstCellText)..<Int(firstCellText + cellTextCount) }
}

/// One line of a cell placed, its column by number (`EntityRelationshipColumn`'s order).
struct EntityRelationshipPlacedCell: Sendable {
    let column: Int8
    let text: DiagramMeasuredText

    var textColumn: EntityRelationshipColumn {
        switch column {
        case 0: .type
        case 1: .name
        case 2: .keys
        default: .comment
        }
    }

    /// Whether the line is drawn in the muted color: a type's, keys' and comment's are; a name's is not.
    var isInMutedColor: Bool { column != 1 }
}

/// A relationship placed: its line from `start` through `segmentCount` of the layout's segments from `firstSegment`,
/// its marks, and its label when it has one.
struct EntityRelationshipPlacedRelationship: Sendable {
    let identification: EntityRelationshipIdentification
    var start: CGPoint
    let firstSegment: Int32
    let segmentCount: Int32
    var firstEntityMark: EntityRelationshipCardinalityMark
    var secondEntityMark: EntityRelationshipCardinalityMark
    let hasLabel: Bool
    var label: DiagramMeasuredText

    var segmentIndices: Range<Int> { Int(firstSegment)..<Int(firstSegment + segmentCount) }
}

/// An entity's box: its name in a header, and a row under it for each attribute.
public struct EntityRelationshipLayoutEntity: Equatable, Sendable {
    public let frame: CGRect
    /// The name or alias, centered in the header, or in the whole box when it has no attributes.
    public let name: DiagramTextBlock
    /// The attribute rows, top to bottom; the header ends where the first begins.
    public let rows: [EntityRelationshipLayoutRow]
}

/// One attribute's row across its entity's box.
public struct EntityRelationshipLayoutRow: Equatable, Sendable {
    /// The row's band, as wide as the box.
    public let frame: CGRect
    /// Each line of the row's cells, starting at its column's left edge.
    public let texts: [EntityRelationshipLayoutCellText]
}

/// One line of an attribute's cell, a block of its own placed so that it starts at its column's left edge.
public struct EntityRelationshipLayoutCellText: Equatable, Sendable {
    public let column: EntityRelationshipColumn
    public let text: DiagramTextBlock
}

/// The columns of an entity's attribute rows, left to right. A column no row fills takes no room.
public enum EntityRelationshipColumn: Equatable, Sendable, CaseIterable {
    case type
    case name
    case keys
    case comment
}

/// A relationship's line between two boxes, or looping out of one box and back, with a cardinality mark at each end.
public struct EntityRelationshipLayoutRelationship: Equatable, Sendable {
    public let identification: EntityRelationshipIdentification
    /// The line, from the first entity's box to the second's; the marks are drawn over its ends.
    public internal(set) var path: DiagramPath
    public internal(set) var firstEntityMark: EntityRelationshipCardinalityMark
    public internal(set) var secondEntityMark: EntityRelationshipCardinalityMark
    /// The label, drawn on a patch of the background, or nil.
    public internal(set) var label: DiagramTextBlock?
}

/// A cardinality drawn where a relationship's line meets a box.
public struct EntityRelationshipCardinalityMark: Equatable, Sendable, BitwiseCopyable {
    public let cardinality: EntityRelationshipCardinality
    /// Where the line meets the box.
    public let tip: CGPoint
    /// The unit direction from the line into the box.
    public let direction: CGVector

    /// How far a mark reaches back along its line from the box, in points: Pele's.
    public static let length: CGFloat = 18
}

extension EntityRelationshipLayoutRelationship {
    func translated(by offset: CGVector) -> EntityRelationshipLayoutRelationship {
        EntityRelationshipLayoutRelationship(identification: identification, path: path.translated(by: offset),
                                             firstEntityMark: firstEntityMark.translated(by: offset),
                                             secondEntityMark: secondEntityMark.translated(by: offset), label: label?.translated(by: offset))
    }
}

extension EntityRelationshipCardinalityMark {
    func translated(by offset: CGVector) -> EntityRelationshipCardinalityMark {
        EntityRelationshipCardinalityMark(cardinality: cardinality, tip: tip.translated(by: offset), direction: direction)
    }
}
