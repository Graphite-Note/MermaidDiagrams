/**
 * File: ReferenceOutlineScenes.swift
 * ----------------------------------
 * Layer: Tests
 * Description: 0.7.0's Ishikawa and tree view scenes, frozen as main 2a0cc65 made them from Core Graphics paths, which
 *              the scenes recorded into lanes are compared with.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

enum ReferenceIshikawaScene {
    /// The diagram's painting, in Pele's order. Across: the title, the spine and its arrow in the line color, then each
    /// category's bones and arrow, its box in the surface color outlined in the border color, its name and its causes,
    /// a cause's causes muted, and last the head with its bold name. Down: the title, the connectors in the border color,
    /// then each entry's box (the effect's and the categories') and its name.
    static func scene(layout: IshikawaLayout) -> DiagramScene {
        var builder = DiagramSceneBuilder()
        builder.title(layout.title)
        let line = DiagramStroke(lineWidth: ReferenceIshikawaScenePaths.lineWidth)
        if let spine = layout.spine { builder.stroke(DiagramEdgeDrawing.path(spine), .line, line, part: .ishikawaSpine) }
        if let arrow = layout.spineArrow { builder.fill(ReferenceIshikawaScenePaths.arrowPath(arrow), .line, part: .marker) }
        for category in layout.categories {
            let bones = CGMutablePath()
            for bone in category.bones { bones.addPath(DiagramEdgeDrawing.path(bone)) }
            builder.stroke(bones, .line, line, part: .ishikawaBones)
            builder.fill(ReferenceIshikawaScenePaths.arrowPath(category.arrow), .line, part: .marker)
            builder.fillAndStroke(ReferenceKanbanScene.roundedBox(category.box), fill: .surface, stroke: .border, line, part: .node)
            builder.text(category.label, .foreground, part: .label)
            for cause in category.causes { builder.text(cause.text, cause.isMuted ? .muted : .foreground, part: .label) }
        }
        if let head = layout.head {
            builder.fillAndStroke(ReferenceIshikawaScenePaths.headOutline(head.frame), fill: .surface, stroke: .border,
                                  DiagramStroke(lineWidth: ReferenceIshikawaScenePaths.lineWidth, lineJoin: .round), part: .node)
            builder.text(head.label, .foreground, isBold: true, part: .label)
        }
        let connectors = CGMutablePath()
        for connector in layout.outlineConnectors { connectors.addPath(DiagramEdgeDrawing.path(connector)) }
        builder.stroke(connectors, .border, line, part: .edge)
        for entry in layout.outlineEntries {
            if entry.isFramed {
                let corner = min(entry.cornerRadius, entry.frame.width / 2, entry.frame.height / 2)
                builder.fillAndStroke(CGPath(roundedRect: entry.frame, cornerWidth: corner, cornerHeight: corner, transform: nil), fill: .surface,
                                      stroke: .border, line, part: .node)
            }
            builder.text(entry.text, .foreground, isBold: entry.isFramed, part: .label)
        }
        return builder.scene(size: layout.size, font: layout.font)
    }
}

enum ReferenceIshikawaScenePaths {
    static let lineWidth: CGFloat = 1

    static func arrowPath(_ mark: DiagramEdgeMark) -> CGPath {
        let filled = CGMutablePath()
        DiagramEdgeDrawing.addMark(mark, filled: filled, stroked: CGMutablePath())
        return filled
    }

    /// The head: flat on the spine's side, a half circle on the other.
    static func headOutline(_ frame: CGRect) -> CGPath {
        let radius = frame.height / 2
        let path = CGMutablePath()
        path.move(to: CGPoint(x: frame.minX, y: frame.minY))
        path.addLine(to: CGPoint(x: frame.maxX - radius, y: frame.minY))
        path.addArc(center: CGPoint(x: frame.maxX - radius, y: frame.midY), radius: radius, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false)
        path.addLine(to: CGPoint(x: frame.minX, y: frame.maxY))
        path.closeSubpath()
        return path
    }
}



enum ReferenceTreeViewScene {
    /// The tree's painting, in Pele's order: the title, the guide lines in the border color, then each row's band in the
    /// accent color, its icon outlined in the muted color, its name (bold for a folder) and its description, italic and
    /// muted.
    static func scene(layout: TreeViewLayout) -> DiagramScene {
        var builder = DiagramSceneBuilder()
        let glyphs = ReferenceTreeViewGlyphs()
        builder.title(layout.title)
        let guides = CGMutablePath()
        for guide in layout.guides { guides.addPath(DiagramEdgeDrawing.path(guide)) }
        builder.stroke(guides, .border, DiagramStroke(lineWidth: layout.guideLineWidth), part: .treeGuides)
        for row in layout.rows {
            if let highlight = row.highlight {
                builder.fill(ReferenceKanbanScene.roundedBox(highlight), DiagramPaint.accent.atOpacity(ReferenceTreeViewGlyphs.highlightOpacity), part: .treeHighlight)
            }
            if let glyph = row.glyph, let path = glyphs.path(of: glyph, in: row.glyphFrame) {
                builder.stroke(path, .muted, DiagramStroke.rounded(lineWidth: ReferenceTreeViewGlyphs.lineWidth(side: row.glyphFrame.width)), part: .icon)
            }
            for line in row.nameLines { builder.text(line, .foreground, isBold: row.isFolder, part: .label) }
            for line in row.descriptionLines { builder.text(line, .muted, isItalic: true, part: .treeDescription) }
        }
        return builder.scene(size: layout.size, font: layout.font)
    }
}

/// Pele's built-in tree view icons: outlines on a 24 by 24 grid, stroked 1.5 grid units wide, read once per scene.
struct ReferenceTreeViewGlyphs {
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

/// Kanban's rounded box, which the Ishikawa and tree view scenes drew their boxes with.
enum ReferenceKanbanScene {
    static let cornerRadius: CGFloat = 4

    static func roundedBox(_ frame: CGRect) -> CGPath {
        CGPath(roundedRect: frame, cornerWidth: min(cornerRadius, frame.width / 2), cornerHeight: min(cornerRadius, frame.height / 2), transform: nil)
    }
}
