/**
 * File: TreeViewLayout.swift
 * --------------------------
 * Layer: Core
 * Description: A tree view laid out: a row per entry with its band, icon, name and description, the guide lines from
 *              each folder to its entries, and the title, on a page whose y runs down.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// A tree view laid out on a page whose origin is the top left corner and whose y runs down, in points.
public struct TreeViewLayout: Equatable, Sendable {
    public let size: CGSize
    /// The font the text was measured in.
    public let font: DiagramFont
    /// The title, centered above the tree, or nil.
    public let title: DiagramTextBlock?
    /// The guide lines: from under each folder down to its last entry and across to each entry, one path a stroke.
    public let guides: [DiagramPath]
    /// The guide lines' width (`lineThickness`).
    public let guideLineWidth: CGFloat
    /// The rows, one per entry, top to bottom.
    public let rows: [TreeViewLayoutRow]
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
