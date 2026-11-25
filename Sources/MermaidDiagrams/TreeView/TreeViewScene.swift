/**
 * File: TreeViewScene.swift
 * -------------------------
 * Layer: Core
 * Description: A laid-out tree view's scene, back to front in Pele's colors, with its built-in file and folder glyphs,
 *              and its renderer, which paints it.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

import CoreGraphics

extension DiagramScene {
    /// The tree's painting, in Pele's order: the title, the guide lines in the border color, then each row's band in the
    /// accent color, its icon outlined in the muted color, its name (bold for a folder) and its description, italic and
    /// muted. Every shape is recorded into a lane of the thread's scene workspace, given back once the builder has
    /// copied it.
    public init(layout: TreeViewLayout) {
        self = DiagramSceneWorkspace.withRecording { workspace in
            var builder = DiagramSceneBuilder(workspace: workspace)
            builder.title(layout.title)
            let madeCount = workspace.madePathCount
            let guides = workspace.makeLane()
            for guide in layout.guides {
                let line = workspace.makeLane()
                DiagramEdgeDrawing.record(guide, into: line)
                guides.addPath(line)
                workspace.givePathsBack(downTo: madeCount + 1)
            }
            builder.stroke(guides, .border, DiagramStroke(lineWidth: layout.guideLineWidth), part: .treeGuides)
            for row in layout.rows {
                workspace.givePathsBack(downTo: madeCount)
                TreeViewGlyphs.add(row, to: &builder, workspace: workspace)
            }
            return builder.scene(size: layout.size, font: layout.font)
        }
    }
}

/// Pele's built-in tree view icons: outlines on a 24 by 24 grid, stroked 1.5 grid units wide, read once for every scene.
enum TreeViewGlyphs {
    static let folderPathData = "M3 6.5A1.5 1.5 0 0 1 4.5 5h4.6l2.4 2.5h8A1.5 1.5 0 0 1 21 9v9a1.5 1.5 0 0 1-1.5 1.5h-15A1.5 1.5 0 0 1 3 18z"
    static let filePathData = "M6.5 3h7L19 8.5v11a1.5 1.5 0 0 1-1.5 1.5h-11A1.5 1.5 0 0 1 5 19.5v-15A1.5 1.5 0 0 1 6.5 3zM13.5 3v5.5H19"
    /// The glyphs' stroke, in grid units.
    static let gridLineWidth: CGFloat = 1.5
    /// How much of the accent color a highlighted row's band takes.
    static let highlightOpacity: CGFloat = 0.14
    /// Pele's corner radius (`--pele-radius`), which a highlighted row's band takes.
    static let highlightCornerRadius: CGFloat = 4

    private static let folder = DiagramGlyphPath(pathData: folderPathData)
    private static let file = DiagramGlyphPath(pathData: filePathData)

    /// A row's band, its icon, its name and its description.
    static func add(_ row: TreeViewLayoutRow, to builder: inout DiagramSceneBuilder, workspace: DiagramSceneWorkspace) {
        if let highlight = row.highlight {
            let corners = (width: min(highlightCornerRadius, highlight.width / 2), height: min(highlightCornerRadius, highlight.height / 2))
            builder.fill(workspace.roundedRectangle(highlight, cornerWidth: corners.width, cornerHeight: corners.height),
                         DiagramPaint.accent.atOpacity(highlightOpacity), part: .treeHighlight)
        }
        if let glyph = row.glyph, let outline = (glyph == .folder ? folder : file) {
            let lane = workspace.makeLane()
            outline.record(in: row.glyphFrame, into: lane)
            builder.stroke(lane, .muted, DiagramStroke.rounded(lineWidth: lineWidth(side: row.glyphFrame.width)), part: .icon)
        }
        for line in row.nameLines { builder.text(line, .foreground, isBold: row.isFolder, part: .label) }
        for line in row.descriptionLines { builder.text(line, .muted, isItalic: true, part: .treeDescription) }
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
