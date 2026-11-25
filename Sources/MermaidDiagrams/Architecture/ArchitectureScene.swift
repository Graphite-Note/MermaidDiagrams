/**
 * File: ArchitectureScene.swift
 * -----------------------------
 * Layer: Core
 * Description: A laid-out architecture diagram's scene, back to front as Pele writes its SVG: the title, the groups
 *              with their heads, the edges and their arrows, the edges' texts, the services and junctions.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 25/11/2026
 */

import CoreGraphics

extension DiagramScene {
    /// The architecture diagram's painting, in Pele's order: the bold title; each group's box in the second surface at
    /// half opacity outlined in the border color, its icon stroked in the text color and its title in the muted color;
    /// each edge in the line color with round ends and corners, and its arrows; each edge's text on a patch of the page's
    /// color; each junction's dot in the line color, each service's square in the surface color outlined in the border
    /// color, its icon or its text, and its title. Every shape is recorded into a lane of the thread's scene workspace,
    /// given back once the builder has copied it.
    public init(layout: ArchitectureLayout) {
        self.init(layout: layout, limits: .standard)
    }

    /// The same painting recorded under `limits`: a scene one of whose lanes goes past their element limit says so
    /// (`exceededPathElementLimit`), and the preparation refuses it.
    public init(layout: ArchitectureLayout, limits: MermaidDiagramLimits) {
        self = DiagramSceneWorkspace.withRecording(limits: limits) { workspace in
            var builder = DiagramSceneBuilder(workspace: workspace)
            builder.title(layout.title)
            let madeCount = workspace.madePathCount
            for group in layout.groups {
                workspace.givePathsBack(downTo: madeCount)
                let box = workspace.roundedRectangle(group.frame, cornerWidth: ArchitectureScenePaths.cornerRadius, cornerHeight: ArchitectureScenePaths.cornerRadius)
                builder.fillAndStroke(box, fill: DiagramPaint.alternateSurface.atOpacity(0.5), stroke: .border, DiagramStroke(lineWidth: 1), part: .cluster)
                ArchitectureScenePaths.add(group.icon, to: &builder, workspace: workspace)
                builder.text(group.title, .muted, part: .clusterLabel)
            }
            for edge in layout.edges {
                workspace.givePathsBack(downTo: madeCount)
                ArchitectureScenePaths.add(edge, to: &builder, workspace: workspace)
            }
            for text in layout.edgeTexts {
                workspace.givePathsBack(downTo: madeCount)
                builder.fill(workspace.roundedRectangle(text.frame.insetBy(dx: -4, dy: 0), cornerWidth: 3, cornerHeight: 3), .background, part: .labelBackground)
                builder.text(text, .foreground, part: .edgeLabel)
            }
            for node in layout.nodes {
                workspace.givePathsBack(downTo: madeCount)
                ArchitectureScenePaths.add(node, to: &builder, workspace: workspace)
            }
            return builder.scene(size: layout.size, font: layout.font)
        }
    }
}

/// The shapes of an architecture diagram's scene, recorded into lanes of the scene's workspace.
enum ArchitectureScenePaths {
    /// Pele's `--pele-radius`.
    static let cornerRadius: CGFloat = 4

    /// An edge's line and its arrows.
    static func add(_ edge: ArchitectureLayoutEdge, to builder: inout DiagramSceneBuilder, workspace: DiagramSceneWorkspace) {
        let line = workspace.makeLane()
        DiagramEdgeDrawing.record(edge.path, into: line)
        builder.stroke(line, .line, .rounded(lineWidth: 1), part: .edge)
        let arrows = workspace.makeLane()
        let crosses = workspace.makeLane()
        if let arrow = edge.sourceArrow { DiagramEdgeDrawing.addMark(arrow, filled: arrows, stroked: crosses) }
        if let arrow = edge.targetArrow { DiagramEdgeDrawing.addMark(arrow, filled: arrows, stroked: crosses) }
        builder.fill(arrows, .line, part: .marker)
    }

    static func add(_ node: ArchitectureLayoutNode, to builder: inout DiagramSceneBuilder, workspace: DiagramSceneWorkspace) {
        switch node.form {
        case .junction(let center, let radius):
            builder.fill(workspace.ellipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius)), .line, part: .node)
        case .service(let square, let icon, let iconText, let title):
            builder.fillAndStroke(workspace.roundedRectangle(square, cornerWidth: cornerRadius, cornerHeight: cornerRadius), fill: .surface, stroke: .border,
                                  DiagramStroke(lineWidth: 1), part: .node)
            add(icon, to: &builder, workspace: workspace)
            builder.text(iconText, .foreground, part: .iconText)
            builder.text(title, .foreground, part: .label)
        }
    }

    /// An icon Pele has an outline for, stroked in the text color 1.5 units of its 24-unit grid wide; nothing for another.
    static func add(_ icon: ArchitectureLayoutIcon?, to builder: inout DiagramSceneBuilder, workspace: DiagramSceneWorkspace) {
        guard let icon, let glyph = ArchitectureIcons.glyph(named: icon.name) else { return }
        let outline = workspace.makeLane()
        glyph.record(in: icon.frame, into: outline)
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
