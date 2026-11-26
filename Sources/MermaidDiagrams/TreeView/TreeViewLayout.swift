/**
 * File: TreeViewLayout.swift
 * --------------------------
 * Layer: Core
 * Description: A tree view laid out: a row per entry with its band, icon, name and description, the guide lines from
 *              each folder to its entries, and the title, on a page whose y runs down.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 26/11/2026
 */

import CoreGraphics

/// A tree view laid out on a page whose origin is the top left corner and whose y runs down, in points. It keeps its
/// rows and guide lines as flat records whose texts are measured lines of the diagram's text (`TreeViewPlacedRow`,
/// `TreeViewGuideStroke`); `guides` and `rows` are made from them when read.
public struct TreeViewLayout: Sendable {
    public let size: CGSize
    /// The font the text was measured in.
    public let font: DiagramFont
    /// The title, centered above the tree, or nil.
    public let title: DiagramTextBlock?
    /// The guide lines' width (`lineThickness`).
    public let guideLineWidth: CGFloat
    /// The rows, one per entry, top to bottom, and the guide lines, in the order they are stroked.
    let placedRows: [TreeViewPlacedRow]
    let guideStrokes: [TreeViewGuideStroke]
    /// The rows' texts, and the diagram's text their lines are ranges of.
    let lines: DiagramMeasuredLines
    let text: [UInt8]

    /// The guide lines: from under each folder down to its last entry and across to each entry, one path a stroke.
    public var guides: [DiagramPath] {
        guideStrokes.map(\.path)
    }

    /// The rows, one per entry, top to bottom, their texts as blocks of their placed lines.
    public var rows: [TreeViewLayoutRow] {
        text.withUnsafeBufferPointer { source in
            placedRows.map { row in
                TreeViewLayoutRow(entryIndex: Int(row.entryIndex), isFolder: row.isFolder, highlight: row.isHighlighted ? row.highlight : nil,
                                  glyph: row.glyph, glyphFrame: row.glyphFrame,
                                  nameLines: row.placedNameLines(lines).map { line in DiagramTextBlock(line, of: lines, source: source) },
                                  descriptionLines: row.placedDescriptionLines(lines).map { line in DiagramTextBlock(line, of: lines, source: source) })
            }
        }
    }
}

extension TreeViewLayout: Equatable {
    /// Equal when they draw the same: the same size, font, title, guides and rows.
    public static func == (left: TreeViewLayout, right: TreeViewLayout) -> Bool {
        left.size == right.size && left.font == right.font && left.title == right.title && left.guideLineWidth == right.guideLineWidth
            && left.guides == right.guides && left.rows == right.rows
    }
}

public struct TreeViewLayoutRow: Equatable, Sendable {
    /// The entry's index in `TreeViewDiagram.entries`.
    public let entryIndex: Int
    public let isFolder: Bool
    /// The band behind a highlighted entry (`:::highlight`), to the tree's right edge, or nil.
    public let highlight: CGRect?
    /// The built-in icon the entry shows, or nil, and the square it is drawn in.
    public let glyph: TreeViewGlyph?
    public let glyphFrame: CGRect
    /// The name's lines, from their left end; a folder's are bold.
    public let nameLines: [DiagramTextBlock]
    /// The description's lines, italic and muted: beside the names, or under the name in a tight layout.
    public let descriptionLines: [DiagramTextBlock]
}
