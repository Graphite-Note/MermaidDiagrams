/**
 * File: ArchitectureScene.swift
 * -----------------------------
 * Layer: Core
 * Description: A laid-out architecture diagram's scene, back to front as Pele writes its SVG: the title, the groups
 *              with their heads, the edges and their arrows, the edges' texts, the services and junctions.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

import CoreGraphics

extension DiagramScene {
    /// The architecture diagram's painting, in Pele's order: the bold title; each group's box in the second surface at
    /// half opacity outlined in the border color, its icon stroked in the text color and its title in the muted color;
    /// each edge in the line color with round ends and corners, and its arrows; each edge's text on a patch of the page's
    /// color; each junction's dot in the line color, each service's square in the surface color outlined in the border
    /// color, its icon or its text, and its title.
    public init(layout: ArchitectureLayout) {
        var builder = DiagramSceneBuilder()
        builder.title(layout.title)
        for group in layout.groups {
            let box = DiagramScenePath(roundedRect: group.frame, cornerWidth: ArchitectureScenePaths.cornerRadius, cornerHeight: ArchitectureScenePaths.cornerRadius)
            builder.fillAndStroke(box, fill: DiagramPaint.alternateSurface.atOpacity(0.5), stroke: .border, DiagramStroke(lineWidth: 1), part: .cluster)
            ArchitectureScenePaths.add(group.icon, to: &builder)
            builder.text(group.title, .muted, part: .clusterLabel)
        }
        for edge in layout.edges {
            builder.stroke(DiagramEdgeDrawing.path(edge.path), .line, .rounded(lineWidth: 1), part: .edge)
            var arrows = DiagramScenePath()
            for arrow in [edge.sourceArrow, edge.targetArrow].compactMap({ arrow in arrow }) {
                DiagramEdgeDrawing.addMark(arrow, filled: &arrows)
            }
            builder.fill(arrows, .line, part: .marker)
        }
        for text in layout.edgeTexts {
            let patch = text.frame.insetBy(dx: -4, dy: 0)
            builder.fill(DiagramScenePath(roundedRect: patch, cornerWidth: 3, cornerHeight: 3), .background, part: .labelBackground)
            builder.text(text, .foreground, part: .edgeLabel)
        }
        for node in layout.nodes { ArchitectureScenePaths.add(node, to: &builder) }
        self = builder.scene(size: layout.size, font: layout.font)
    }
}

/// The shapes of an architecture diagram's scene.
enum ArchitectureScenePaths {
    /// Pele's `--pele-radius`.
    static let cornerRadius: CGFloat = 4

    static func add(_ node: ArchitectureLayoutNode, to builder: inout DiagramSceneBuilder) {
        switch node.form {
        case .junction(let center, let radius):
            builder.fill(DiagramScenePath(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius)), .line,
                         part: .node)
        case .service(let square, let icon, let iconText, let title):
            builder.fillAndStroke(DiagramScenePath(roundedRect: square, cornerWidth: cornerRadius, cornerHeight: cornerRadius), fill: .surface, stroke: .border,
                                  DiagramStroke(lineWidth: 1), part: .node)
            add(icon, to: &builder)
            builder.text(iconText, .foreground, part: .iconText)
            builder.text(title, .foreground, part: .label)
        }
    }

    /// An icon Pele has an outline for, stroked in the text color 1.5 units of its 24-unit grid wide; nothing for another.
    static func add(_ icon: ArchitectureLayoutIcon?, to builder: inout DiagramSceneBuilder) {
        guard let icon, let outline = ArchitectureIcons.outline(named: icon.name, in: icon.frame) else { return }
        let lineWidth = ArchitectureIcons.gridLineWidth * min(icon.frame.width, icon.frame.height) / DiagramGlyphPath.standardGridSide
        builder.stroke(outline, .foreground, .rounded(lineWidth: lineWidth), part: .icon)
    }
}

/// Draws a laid-out architecture diagram into a Core Graphics context whose origin is the layout's top left and whose y
/// runs down, back to front, by painting its scene (`DiagramScene(layout:)`) with `DiagramSceneRenderer`.
public enum ArchitectureRenderer {
    public static func draw(_ layout: ArchitectureLayout, in context: CGContext, palette: DiagramPalette) {
        DiagramSceneRenderer.draw(DiagramScene(layout: layout), in: context, palette: palette)
    }
}
