/**
 * File: TreeViewScene.swift
 * -------------------------
 * Layer: Core
 * Description: A laid-out tree view's scene, back to front in Pele's colors, with its built-in file and folder glyphs,
 *              and its renderer, which paints it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

extension DiagramScene {
    /// The tree's painting, in Pele's order: the title, the guide lines in the border color, then each row's band in the
    /// accent color, its icon outlined in the muted color, its name (bold for a folder) and its description, italic and
    /// muted.
    public init(layout: TreeViewLayout) {
        var builder = DiagramSceneBuilder()
        let glyphs = TreeViewGlyphs()
        builder.title(layout.title)
        let guides = CGMutablePath()
        for guide in layout.guides { guides.addPath(DiagramEdgeDrawing.path(guide)) }
        builder.stroke(guides, .border, DiagramStroke(lineWidth: layout.guideLineWidth), part: .treeGuides)
        for row in layout.rows {
            if let highlight = row.highlight {
                builder.fill(KanbanScene.roundedBox(highlight), DiagramPaint.accent.atOpacity(TreeViewGlyphs.highlightOpacity), part: .treeHighlight)
            }
            if let glyph = row.glyph, let path = glyphs.path(of: glyph, in: row.glyphFrame) {
                builder.stroke(path, .muted, DiagramStroke.rounded(lineWidth: TreeViewGlyphs.lineWidth(side: row.glyphFrame.width)), part: .icon)
            }
            for line in row.nameLines { builder.text(line, .foreground, isBold: row.isFolder, part: .label) }
            for line in row.descriptionLines { builder.text(line, .muted, isItalic: true, part: .treeDescription) }
        }
        self = builder.scene(size: layout.size, font: layout.font)
    }
}

/// Pele's built-in tree view icons: outlines on a 24 by 24 grid, stroked 1.5 grid units wide, read once per scene.
struct TreeViewGlyphs {
    static let folderPathData = "M3 6.5A1.5 1.5 0 0 1 4.5 5h4.6l2.4 2.5h8A1.5 1.5 0 0 1 21 9v9a1.5 1.5 0 0 1-1.5 1.5h-15A1.5 1.5 0 0 1 3 18z"
    static let filePathData = "M6.5 3h7L19 8.5v11a1.5 1.5 0 0 1-1.5 1.5h-11A1.5 1.5 0 0 1 5 19.5v-15A1.5 1.5 0 0 1 6.5 3zM13.5 3v5.5H19"
    /// The glyphs' stroke, in grid units.
    static let gridLineWidth: CGFloat = 1.5
    /// How much of the accent color a highlighted row's band takes.
    static let highlightOpacity: CGFloat = 0.14

    private let folder = DiagramGlyphPath(pathData: folderPathData)
    private let file = DiagramGlyphPath(pathData: filePathData)

    func path(of glyph: TreeViewGlyph, in frame: CGRect) -> CGPath? {
        (glyph == .folder ? folder : file)?.path(in: frame)
    }

    /// The stroke's width in points for a glyph drawn `side` points wide.
    static func lineWidth(side: CGFloat) -> CGFloat {
        gridLineWidth * side / DiagramGlyphPath.standardGridSide
    }
}

/// Draws a laid-out tree view into a Core Graphics context whose origin is the layout's top left and whose y runs down,
/// by painting its scene with `DiagramSceneRenderer`.
public enum TreeViewRenderer {
    public static func draw(_ layout: TreeViewLayout, in context: CGContext, palette: DiagramPalette) {
        DiagramSceneRenderer.draw(DiagramScene(layout: layout), in: context, palette: palette)
    }
}
