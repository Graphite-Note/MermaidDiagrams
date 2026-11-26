/**
 * File: EntityRelationshipBoxMeasurement.swift
 * --------------------------------------------
 * Layer: Core
 * Description: An entity's box sized around its name and attribute table, Pele's, its rows placed when the box is.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.4
 * Date: 26/11/2026
 */

import CoreGraphics
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// An entity's box measured: its size, its name placed from the box's top left corner, and its attribute table, whose
/// rows are placed when the box is.
struct EntityRelationshipMeasuredBox {
    let size: CGSize
    let name: DiagramTextBlock
    /// The attribute table, nil for an entity without attributes.
    let table: EntityRelationshipAttributeTable?
    /// Where the rows start, below the header.
    let headerHeight: CGFloat
    let rowFontSize: CGFloat

    /// The box with its top left corner at `origin`, then moved by `offset`: every place found from the box's corner
    /// and moved as `translated(by:)` moves it, first by `origin` and then by `offset`.
    func placed(origin: CGVector, offset: CGVector) -> EntityRelationshipLayoutEntity {
        let rows = table?.rows(top: headerHeight, width: size.width, inset: EntityRelationshipBoxMeasurement.cellHorizontalPadding, rowFontSize: rowFontSize,
                               movedBy: origin, then: offset) ?? []
        return EntityRelationshipLayoutEntity(frame: frame(origin: origin).offsetBy(dx: offset.dx, dy: offset.dy),
                                              name: name.translated(by: origin).translated(by: offset), rows: rows)
    }

    /// The box's frame with its top left corner at `origin`, as the box placed there has it.
    func frame(origin: CGVector) -> CGRect {
        CGRect(origin: .zero, size: size).offsetBy(dx: origin.dx, dy: origin.dy)
    }
}

/// Sizes an entity's box around its text as Pele does: the name 18 points from each side and 12 above and below it,
/// the box at least 96 points wide; with attributes, the name in a header 9 points above and below it, then a row
/// for each attribute (`EntityRelationshipAttributeTable`), 12 points in from the box's sides.
enum EntityRelationshipBoxMeasurement {
    static let minimumWidth: CGFloat = 96
    static let nameHorizontalPadding: CGFloat = 18
    static let nameVerticalPadding: CGFloat = 12
    static let headerVerticalPadding: CGFloat = 9
    static let cellHorizontalPadding: CGFloat = 12
    /// The widest a name's line is before it wraps.
    static let nameWrappingWidth: CGFloat = 240
    /// The widest a comment's line is before it wraps; types, names and keys never wrap.
    static let commentWrappingWidth: CGFloat = 260

    /// - Parameter minimumSize: The least size the entity's loops need; its height counts for a box without
    ///   attributes only, which loops out of its right side.
    static func box<Measurer>(for entity: EntityRelationshipEntity, measurers: EntityRelationshipTextMeasurers<Measurer>,
                              minimumSize: CGSize, cells constantCells: inout EntityRelationshipConstantCells) -> EntityRelationshipMeasuredBox {
        var name = DiagramTextBlock(label: entity.label, measurer: measurers.name, maximumWidth: nameWrappingWidth)
        let nameHeight = max(name.size.height, measurers.name.lineHeight)
        let narrowest = max(minimumWidth, minimumSize.width, name.size.width + 2 * nameHorizontalPadding)
        guard !entity.attributes.isEmpty else {
            let size = CGSize(width: narrowest, height: max(nameHeight + 2 * nameVerticalPadding, minimumSize.height))
            name.center = CGPoint(x: size.width / 2, y: size.height / 2)
            return EntityRelationshipMeasuredBox(size: size, name: name, table: nil, headerHeight: 0, rowFontSize: measurers.row.fontSize)
        }
        var cells: [DiagramTextBlock] = []
        cells.reserveCapacity(entity.attributes.count * EntityRelationshipAttributeTable.cellsPerRow)
        for attribute in entity.attributes { appendCells(of: attribute, measurers: measurers, constantCells: &constantCells, to: &cells) }
        let table = EntityRelationshipAttributeTable(cells: cells, rowLineHeight: measurers.row.lineHeight)
        let width = max(narrowest, table.filledWidth + 2 * cellHorizontalPadding)
        let headerHeight = nameHeight + 2 * headerVerticalPadding
        name.center = CGPoint(x: width / 2, y: headerHeight / 2)
        return EntityRelationshipMeasuredBox(size: CGSize(width: width, height: headerHeight + table.height), name: name, table: table,
                                             headerHeight: headerHeight, rowFontSize: measurers.row.fontSize)
    }

    /// An attribute's type, name, keys and comment, measured in that order; a cell with nothing to show has no lines. The
    /// keys and a comment that is not written are blocks of a closed set, measured once a diagram (`constantCells`).
    private static func appendCells<Measurer>(of attribute: EntityRelationshipAttribute, measurers: EntityRelationshipTextMeasurers<Measurer>,
                                              constantCells: inout EntityRelationshipConstantCells, to cells: inout [DiagramTextBlock]) {
        let unwrapped = CGFloat.greatestFiniteMagnitude
        cells.append(DiagramTextBlock(label: lines(of: attribute.type), measurer: measurers.row, maximumWidth: unwrapped))
        cells.append(DiagramTextBlock(label: lines(of: attribute.name), measurer: measurers.row, maximumWidth: unwrapped))
        cells.append(constantCells.keys(attribute.keys, measurer: measurers.key))
        if let comment = attribute.comment {
            cells.append(DiagramTextBlock(label: comment, measurer: measurers.row, maximumWidth: commentWrappingWidth))
        } else {
            cells.append(constantCells.noComment(measurer: measurers.row))
        }
    }

    /// A type or a name in backticks may hold line breaks; each starts a line. A text without a line break or a final
    /// carriage return is its one line, the label `DiagramLabel(lines:)` makes of it.
    private static func lines(of text: String) -> DiagramLabel {
        // A line feed, alone or after a carriage return, is byte 10; a final carriage return is byte 13.
        if !hasLineBreak(text) { return DiagramLabel(lines: [text]) }
        return DiagramLabel(lines: text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            String(line.hasSuffix("\r") ? line.dropLast() : line)
        })
    }

    /// Whether a text holds a line feed or ends with a carriage return, found on its bytes at once when they are
    /// contiguous (a native String's are).
    private static func hasLineBreak(_ text: String) -> Bool {
        let found = text.utf8.withContiguousStorageIfAvailable { bytes -> Bool in
            guard let base = bytes.baseAddress, !bytes.isEmpty else { return false }
            return bytes[bytes.count - 1] == 13 || memchr(base, 10, bytes.count) != nil
        }
        return found ?? (text.utf8.contains(10) || text.utf8.last == 13)
    }
}
