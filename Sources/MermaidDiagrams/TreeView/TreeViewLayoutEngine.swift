/**
 * File: TreeViewLayoutEngine.swift
 * --------------------------------
 * Layer: Core
 * Description: Lays a tree view out with Pele's measurements: a row per entry, set in a step per level, siblings lined
 *              up around their icons, descriptions beside the names, guide lines from each folder to its entries.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// Lays a tree view out as Pele's tree view renderer does: entries top to bottom in the order written, each level set in
/// `rowIndent` plus `paddingAcross` (20 points), each row one and a half lines high plus `paddingDown` above and below;
/// when one entry of a folder shows an icon, its siblings leave room for one; folders' names bold; descriptions in a
/// column 16 points right of the longest name; guide lines from under each folder down to its last entry, with a rounded
/// elbow, and across to each entry; a band behind each highlighted entry. A tree wider than `maximumWidth` is laid out
/// tight when that is narrower: steps that fit the width, names broken over lines and descriptions under them.
public enum TreeViewLayoutEngine {
    static let iconGap: CGFloat = 6
    static let descriptionGap: CGFloat = 16
    static let guideInset: CGFloat = 7
    static let elbowRadius: CGFloat = 4
    static let highlightOverhang: CGFloat = 4
    static let padding: CGFloat = 8
    static let titleGap: CGFloat = 12

    public static func layout(_ diagram: TreeViewDiagram, typography: DiagramTypography, maximumWidth: CGFloat? = nil) -> TreeViewLayout {
        layout(diagram, measurers: DiagramTextMeasurerSet(typography: typography), font: typography.font, maximumWidth: maximumWidth)
    }

    static func layout<Measurer: DiagramTextMeasuring>(_ diagram: TreeViewDiagram, measurers: DiagramTextMeasurerSet<Measurer>, font: DiagramFont,
                                                       maximumWidth: CGFloat?) -> TreeViewLayout {
        let limit = maximumWidth.flatMap { width in width > 0 && width.isFinite ? width : nil }
        let loose = laidOut(diagram, measurers: measurers, font: font, tightWidth: nil)
        guard let limit, loose.size.width > limit else { return loose }
        let tight = laidOut(diagram, measurers: measurers, font: font, tightWidth: limit)
        return tight.size.width < loose.size.width ? tight : loose
    }

    /// The tree laid out loose, or tight for `tightWidth`.
    private static func laidOut<Measurer: DiagramTextMeasuring>(_ diagram: TreeViewDiagram, measurers: DiagramTextMeasurerSet<Measurer>,
                                                                font: DiagramFont, tightWidth: CGFloat?) -> TreeViewLayout {
        let title = diagram.title.map { title in
            DiagramTextBlock(label: DiagramLabel(title), measurer: measurers.bold, maximumWidth: tightWidth.map { width in max(80, width - 2 * padding) } ?? 4_000)
        }
        let titleHeight = title.map { title in title.lines.isEmpty ? 0 : title.size.height + titleGap } ?? 0
        let rows = TreeViewRowPlacement(diagram, measurers: measurers, tightWidth: tightWidth)
        let width = max(rows.width, title?.size.width ?? 0)
        let inset = padding + (rows.hasHighlight ? highlightOverhang : 0)
        let origin = CGPoint(x: inset, y: padding + titleHeight)
        let size = CGSize(width: (width + 2 * inset).rounded(.up), height: (origin.y + rows.height + padding).rounded(.up))
        var placedTitle = title
        placedTitle?.center = CGPoint(x: size.width / 2, y: padding + (title?.size.height ?? 0) / 2)
        return TreeViewLayout(size: size, font: font, title: placedTitle, guides: rows.guides(diagram, origin: origin),
                              guideLineWidth: CGFloat(diagram.options.lineThickness),
                              rows: rows.placedRows(origin: origin, pageWidth: size.width))
    }
}
