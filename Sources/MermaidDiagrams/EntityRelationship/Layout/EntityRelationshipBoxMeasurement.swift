/**
 * File: EntityRelationshipBoxMeasurement.swift
 * --------------------------------------------
 * Layer: Core
 * Description: An entity's box sized around its name and attribute table, Pele's, its cells measured into the layout's
 *              lines and its rows' heights and columns' widths kept for when the box is placed.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.6
 * Date: 26/11/2026
 */

import CoreGraphics
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// The widths of an attribute table's four columns: type, name, keys, comment.
struct EntityRelationshipColumnWidths {
    var type: CGFloat = 0
    var name: CGFloat = 0
    var keys: CGFloat = 0
    var comment: CGFloat = 0

    subscript(column: Int) -> CGFloat {
        get {
            switch column {
            case 0: type
            case 1: name
            case 2: keys
            default: comment
            }
        }
        set {
            switch column {
            case 0: type = newValue
            case 1: name = newValue
            case 2: keys = newValue
            default: comment = newValue
            }
        }
    }
}

/// An entity's box measured: its size, its name placed from the box's top left corner, and its attribute table: its
/// rows (`rowCount` of the measurement's `rowHeights` from `firstRow`, their cells four to a row in its `cells`), its
/// columns' widths, the height of a line of its text, and where the rows start, below the header.
struct EntityRelationshipMeasuredBox {
    let size: CGSize
    let name: DiagramMeasuredText
    let firstRow: Int32
    let rowCount: Int32
    let columnWidths: EntityRelationshipColumnWidths
    let rowLineHeight: CGFloat
    let headerHeight: CGFloat
    let rowFontSize: CGFloat

    var rowIndices: Range<Int> { Int(firstRow)..<Int(firstRow + rowCount) }

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

    /// The box of entity `index`, its cells measured into `measured`'s lines and lists.
    /// - Parameter minimumSize: The least size the entity's loops need; its height counts for a box without
    ///   attributes only, which loops out of its right side.
    static func box<Measurer>(ofEntity index: Int, cells cellMeasuring: EntityRelationshipCellMeasuring<Measurer>,
                              measurers: EntityRelationshipFlatMeasurers<Measurer>, minimumSize: CGSize, into measured: inout EntityRelationshipMeasurement,
                              constantCells: inout EntityRelationshipConstantCells) -> EntityRelationshipMeasuredBox {
        let entity = cellMeasuring.model.pointee.entities[index]
        var name = cellMeasuring.label(entity.label, measurer: measurers.name, maximumWidth: nameWrappingWidth, into: &measured.lines)
        let nameHeight = max(name.size.height, measurers.name.singleLineHeight)
        let narrowest = max(minimumWidth, minimumSize.width, name.size.width + 2 * nameHorizontalPadding)
        guard entity.attributeCount > 0 else {
            let size = CGSize(width: narrowest, height: max(nameHeight + 2 * nameVerticalPadding, minimumSize.height))
            name.center = CGPoint(x: size.width / 2, y: size.height / 2)
            return EntityRelationshipMeasuredBox(size: size, name: name, firstRow: Int32(measured.rowHeights.count), rowCount: 0,
                                                 columnWidths: EntityRelationshipColumnWidths(), rowLineHeight: measurers.row.singleLineHeight,
                                                 headerHeight: 0, rowFontSize: measurers.row.fontSize)
        }
        let firstRow = measured.rowHeights.count
        var table = EntityRelationshipAttributeTable(rowLineHeight: measurers.row.singleLineHeight)
        for attributeIndex in entity.attributeIndices {
            let attribute = cellMeasuring.model.pointee.attributes[attributeIndex]
            let type = cellMeasuring.typeOrName(attribute.type, of: attribute, isType: true, measurer: measurers.row, into: &measured.lines)
            let attributeName = cellMeasuring.typeOrName(attribute.name, of: attribute, isType: false, measurer: measurers.row, into: &measured.lines)
            let keys = constantCells.keys(of: attribute, model: cellMeasuring.model.pointee, measurer: measurers.key, into: &measured.lines)
            let comment = attribute.hasComment
                ? cellMeasuring.comment(of: attribute, measurer: measurers.row, maximumWidth: commentWrappingWidth, into: &measured.lines)
                : constantCells.noComment(measurer: measurers.row.measurer, into: &measured.lines)
            measured.rowHeights.append(table.addRow(type, attributeName, keys, comment))
            measured.cells.append(type)
            measured.cells.append(attributeName)
            measured.cells.append(keys)
            measured.cells.append(comment)
        }
        let width = max(narrowest, table.filledWidth + 2 * cellHorizontalPadding)
        let headerHeight = nameHeight + 2 * headerVerticalPadding
        name.center = CGPoint(x: width / 2, y: headerHeight / 2)
        return EntityRelationshipMeasuredBox(size: CGSize(width: width, height: headerHeight + table.height), name: name, firstRow: Int32(firstRow),
                                             rowCount: Int32(measured.rowHeights.count - firstRow), columnWidths: table.columnWidths,
                                             rowLineHeight: table.rowLineHeight, headerHeight: headerHeight, rowFontSize: measurers.row.fontSize)
    }

    /// A type or a name in backticks may hold line breaks; each starts a line. A text without a line break or a final
    /// carriage return is its one line, the label `DiagramLabel(lines:)` makes of it.
    static func lines(of text: String) -> DiagramLabel {
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
