/**
 * File: ReferencePlaneMapScenes.swift
 * -----------------------------------
 * Layer: Tests
 * Description: 0.7.0's Wardley map, Cynefin framework and architecture scenes, frozen as main 2a0cc65 made them from Core
 *              Graphics paths, which the scenes recorded into lanes are compared with.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
import Foundation
@testable import MermaidDiagrams

enum ReferenceWardleyMapScene {
    /// The Wardley map's painting, back to front as Pele writes it: the title; the stages' lines dashed in the border
    /// color, the grid, the axes in the line color; the stages' names in the muted color and the axes' titles in bold;
    /// the pipelines' boxes on the surface color; the links in the line color, their labels muted; the evolutions in the
    /// accent color; each node's shape, inertia bar and label; the annotations; the notes in bold; the forces.
    static func scene(layout: WardleyMapLayout) -> DiagramScene {
        var builder = DiagramSceneBuilder()
        builder.title(layout.title)
        ReferenceWardleyMapScenePaths.addFrame(of: layout, to: &builder)
        for pipeline in layout.pipelines {
            builder.fillAndStroke(ReferenceWardleyMapScenePaths.rounded(pipeline.frame), fill: .surface, stroke: .border, DiagramStroke(lineWidth: 1), part: .wardleyPipeline)
            if let line = pipeline.line {
                builder.stroke(DiagramEdgeDrawing.path(line), .line, DiagramStroke(lineWidth: 1, dashLengths: [4, 4]), part: .wardleyPipeline)
            }
        }
        for link in layout.links {
            builder.stroke(DiagramEdgeDrawing.path(link.line), .line, DiagramStroke(lineWidth: 1, dashLengths: link.isDashed ? [6, 6] : []), part: .edge)
            builder.fill(ReferenceWardleyMapScenePaths.arrows(link.arrows), .line, part: .marker)
            builder.text(link.label, .muted, part: .edgeLabel)
        }
        for trend in layout.trends {
            if let line = trend.line { builder.stroke(DiagramEdgeDrawing.path(line), .accent, DiagramStroke(lineWidth: 1, dashLengths: [4, 4]), part: .wardleyTrend) }
            builder.fill(ReferenceWardleyMapScenePaths.arrows(trend.arrow.map { arrow in [arrow] } ?? []), .accent, part: .marker)
            builder.fillAndStroke(ReferenceWardleyMapScenePaths.circle(trend.target, radius: 6), fill: .background, stroke: .accent, DiagramStroke(lineWidth: 1),
                                  part: .wardleyTrend)
        }
        for node in layout.nodes { ReferenceWardleyMapScenePaths.add(node, to: &builder) }
        ReferenceWardleyMapScenePaths.addAnnotations(of: layout, to: &builder)
        for note in layout.notes { builder.texts(note, .foreground, isBold: true, part: .wardleyNote) }
        for force in layout.forces {
            let outline = CGMutablePath()
            outline.addPath(DiagramEdgeDrawing.path(force.outline))
            outline.closeSubpath()
            let part: DiagramScenePart = force.isAccelerator ? .wardleyAccelerator : .wardleyDeaccelerator
            builder.fillAndStroke(outline, fill: .surface, stroke: .line, DiagramStroke(lineWidth: 1), part: part)
            builder.text(force.name, .foreground, isBold: true, part: part)
        }
        return builder.scene(size: layout.size, font: layout.font)
    }
}

/// The shapes of a Wardley map's scene.
enum ReferenceWardleyMapScenePaths {
    static let radius: CGFloat = 6
    static let squareSide: CGFloat = 10
    /// Pele's `--pele-radius`.
    static let cornerRadius: CGFloat = 4

    static func rounded(_ frame: CGRect) -> CGPath {
        CGPath(roundedRect: frame, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    }

    static func circle(_ center: CGPoint, radius: CGFloat) -> CGPath {
        CGPath(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius), transform: nil)
    }

    static func arrows(_ marks: [DiagramEdgeMark]) -> CGPath {
        let filled = CGMutablePath()
        for mark in marks { DiagramEdgeDrawing.addMark(mark, filled: filled, stroked: CGMutablePath()) }
        return filled
    }

    /// The stages' lines, the grid, the axes, the stages' names and the axes' titles.
    static func addFrame(of layout: WardleyMapLayout, to builder: inout DiagramSceneBuilder) {
        let stages = CGMutablePath()
        for line in layout.stageLines { stages.addPath(DiagramEdgeDrawing.path(line)) }
        builder.stroke(stages, .border, DiagramStroke(lineWidth: 1, dashLengths: [4, 4]), part: .wardleyStage)
        let grid = CGMutablePath()
        for line in layout.gridLines { grid.addPath(DiagramEdgeDrawing.path(line)) }
        builder.stroke(grid, .border, DiagramStroke(lineWidth: 1, dashLengths: [2, 6]), part: .wardleyGrid)
        builder.stroke(DiagramEdgeDrawing.path(layout.axes), .line, DiagramStroke(lineWidth: 1), part: .wardleyAxis)
        builder.texts(layout.stageLabels, .muted, part: .wardleyStageLabel)
        builder.text(layout.evolutionTitle, .foreground, isBold: true, part: .wardleyAxisLabel)
        builder.text(layout.visibilityTitle, .foreground, isBold: true, rotation: -.pi / 2, part: .wardleyAxisLabel)
    }

    /// A node: its sourcing ring (muted, the second surface, the surface or the background), a market's triangle of dots,
    /// a parent's square or a component's circle, its inertia bar, and its label.
    static func add(_ node: WardleyMapLayoutNode, to builder: inout DiagramSceneBuilder) {
        let center = node.center
        if let sourcing = node.sourcing {
            let fill: DiagramPaint = switch sourcing {
            case .outsource: .muted
            case .buy: .alternateSurface
            case .build: .surface
            case .market: .background
            }
            builder.fillAndStroke(circle(center, radius: 2 * radius), fill: fill, stroke: .line, DiagramStroke(lineWidth: 1), part: .node)
        }
        if node.sourcing == .market { addMarket(at: center, to: &builder) }
        switch node.shape {
        case .square:
            let square = CGPath(rect: CGRect(x: center.x - squareSide / 2, y: center.y - squareSide / 2, width: squareSide, height: squareSide), transform: nil)
            builder.fillAndStroke(square, fill: .background, stroke: .line, DiagramStroke(lineWidth: 1), part: .node)
        case .circle: builder.fillAndStroke(circle(center, radius: radius), fill: .background, stroke: .line, DiagramStroke(lineWidth: 1), part: .node)
        case .none: break
        }
        if let inertia = node.inertia { builder.fill(CGPath(rect: inertia, transform: nil), .line, part: .wardleyInertia) }
        builder.texts(node.label, .foreground, isBold: node.isAnchor, part: .label)
    }

    /// A market's triangle 1.2 radii from its center, outlined, with a dot of 0.7 radii at each corner.
    private static func addMarket(at center: CGPoint, to builder: inout DiagramSceneBuilder) {
        let reach = 1.2 * radius
        let across = reach * cos(CGFloat.pi / 6)
        let bottom = center.y + reach * sin(CGFloat.pi / 6)
        let corners = [CGPoint(x: center.x, y: center.y - reach), CGPoint(x: center.x - across, y: bottom), CGPoint(x: center.x + across, y: bottom)]
        let triangle = CGMutablePath()
        triangle.addLines(between: corners)
        triangle.closeSubpath()
        builder.stroke(triangle, .line, DiagramStroke(lineWidth: 1), part: .node)
        for corner in corners {
            builder.fillAndStroke(circle(corner, radius: 0.7 * radius), fill: .background, stroke: .line, DiagramStroke(lineWidth: 1), part: .node)
        }
    }

    /// Each annotation's circles with their bold numbers, then the list's box and its rows.
    static func addAnnotations(of layout: WardleyMapLayout, to builder: inout DiagramSceneBuilder) {
        for annotation in layout.annotations {
            for (circle, number) in zip(annotation.circles, annotation.numbers) {
                builder.fillAndStroke(self.circle(circle.center, radius: circle.radius), fill: .background, stroke: .line, DiagramStroke(lineWidth: 1),
                                      part: .wardleyAnnotation)
                builder.text(number, .foreground, isBold: true, part: .wardleyAnnotation)
            }
        }
        guard let list = layout.annotationList else { return }
        builder.fillAndStroke(rounded(list.frame), fill: .background, stroke: .border, DiagramStroke(lineWidth: 1), part: .wardleyAnnotations)
        builder.texts(list.rows, .foreground, part: .wardleyAnnotations)
    }
}


enum ReferenceCynefinScene {
    /// The Cynefin framework's painting, back to front as Pele writes it: the title; each quadrant's region in its series
    /// color at 14 percent; the boundaries dashed in the border color and the cliff two points wide in the line color; the
    /// ellipse over them in the background, then in confusion's series color at 18 percent, dashed in the border color;
    /// each domain's name in bold, its subtitles in muted italic and its items in rounded boxes; each transition's curve,
    /// arrow and label in the line and text colors.
    static func scene(layout: CynefinLayout) -> DiagramScene {
        var builder = DiagramSceneBuilder()
        builder.title(layout.title)
        for region in layout.regions {
            builder.fill(ReferenceCynefinScenePaths.closed(region.outline), DiagramPaint.series(region.seriesIndex).atOpacity(ReferenceCynefinScenePaths.regionOpacity),
                         part: .cynefinRegion)
        }
        let boundaries = CGMutablePath()
        for boundary in layout.boundaries { boundaries.addPath(DiagramEdgeDrawing.path(boundary)) }
        builder.stroke(boundaries, .border, DiagramStroke(lineWidth: 1, dashLengths: [6, 3]), part: .cynefinBoundary)
        builder.stroke(DiagramEdgeDrawing.path(layout.cliff), .line, DiagramStroke(lineWidth: 2, lineCap: .round), part: .cynefinCliff)
        let ellipse = CGPath(ellipseIn: layout.confusion, transform: nil)
        builder.fill(ellipse, .background, part: .cynefinRegion)
        builder.fillAndStroke(ellipse, fill: DiagramPaint.series(CynefinLayoutEngine.confusionSeriesIndex).atOpacity(ReferenceCynefinScenePaths.confusionOpacity),
                              stroke: .border, DiagramStroke(lineWidth: 1, dashLengths: [4, 2]), part: .cynefinRegion)
        for block in layout.blocks { ReferenceCynefinScenePaths.add(block, to: &builder) }
        for transition in layout.transitions {
            builder.stroke(DiagramEdgeDrawing.path(transition.path), .line, DiagramStroke(lineWidth: 1), part: .edge)
            let arrow = CGMutablePath()
            DiagramEdgeDrawing.addMark(transition.arrow, filled: arrow, stroked: CGMutablePath())
            builder.fill(arrow, .line, part: .marker)
            builder.text(transition.label, .foreground, part: .edgeLabel)
        }
        return builder.scene(size: layout.size, font: layout.font)
    }
}

/// The shapes of a Cynefin framework's scene.
enum ReferenceCynefinScenePaths {
    static let regionOpacity: CGFloat = 0.14
    static let confusionOpacity: CGFloat = 0.18
    /// Pele's `--pele-radius`.
    static let cornerRadius: CGFloat = 4

    /// A region's outline, closed.
    static func closed(_ outline: DiagramPath) -> CGPath {
        let path = CGMutablePath()
        path.addPath(DiagramEdgeDrawing.path(outline))
        path.closeSubpath()
        return path
    }

    /// A block: its name, its subtitles, then each item's box and text in turn.
    static func add(_ block: CynefinLayoutBlock, to builder: inout DiagramSceneBuilder) {
        builder.text(block.name, .foreground, isBold: true, part: .label)
        for subtitle in block.subtitles { builder.text(subtitle, .muted, isItalic: true, part: .cynefinSubtitle) }
        for badge in block.badges {
            let box = CGPath(roundedRect: badge.frame, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
            builder.fillAndStroke(box, fill: .background, stroke: .border, DiagramStroke(lineWidth: 1, dashLengths: badge.isOverflow ? [3, 2] : []), part: .node)
            builder.text(badge.text, badge.isOverflow ? .muted : .foreground, part: .label)
        }
    }
}


enum ReferenceArchitectureScene {
    /// The architecture diagram's painting, in Pele's order: the bold title; each group's box in the second surface at
    /// half opacity outlined in the border color, its icon stroked in the text color and its title in the muted color;
    /// each edge in the line color with round ends and corners, and its arrows; each edge's text on a patch of the page's
    /// color; each junction's dot in the line color, each service's square in the surface color outlined in the border
    /// color, its icon or its text, and its title.
    static func scene(layout: ArchitectureLayout) -> DiagramScene {
        var builder = DiagramSceneBuilder()
        builder.title(layout.title)
        for group in layout.groups {
            let box = CGPath(roundedRect: group.frame, cornerWidth: ReferenceArchitectureScenePaths.cornerRadius, cornerHeight: ReferenceArchitectureScenePaths.cornerRadius, transform: nil)
            builder.fillAndStroke(box, fill: DiagramPaint.alternateSurface.atOpacity(0.5), stroke: .border, DiagramStroke(lineWidth: 1), part: .cluster)
            ReferenceArchitectureScenePaths.add(group.icon, to: &builder)
            builder.text(group.title, .muted, part: .clusterLabel)
        }
        for edge in layout.edges {
            builder.stroke(DiagramEdgeDrawing.path(edge.path), .line, .rounded(lineWidth: 1), part: .edge)
            let arrows = CGMutablePath()
            for arrow in [edge.sourceArrow, edge.targetArrow].compactMap({ arrow in arrow }) {
                DiagramEdgeDrawing.addMark(arrow, filled: arrows, stroked: CGMutablePath())
            }
            builder.fill(arrows, .line, part: .marker)
        }
        for text in layout.edgeTexts {
            let patch = text.frame.insetBy(dx: -4, dy: 0)
            builder.fill(CGPath(roundedRect: patch, cornerWidth: 3, cornerHeight: 3, transform: nil), .background, part: .labelBackground)
            builder.text(text, .foreground, part: .edgeLabel)
        }
        for node in layout.nodes { ReferenceArchitectureScenePaths.add(node, to: &builder) }
        return builder.scene(size: layout.size, font: layout.font)
    }
}

/// The shapes of an architecture diagram's scene.
enum ReferenceArchitectureScenePaths {
    /// Pele's `--pele-radius`.
    static let cornerRadius: CGFloat = 4

    /// The outline of the icon `name` in `frame`'s square, or nil for a name Pele has no outline for.
    static func outline(named name: String, in frame: CGRect) -> CGPath? {
        guard let data = ArchitectureIcons.pathDataByName[name], let glyph = DiagramGlyphPath(pathData: data) else { return nil }
        return glyph.path(in: frame)
    }

    static func add(_ node: ArchitectureLayoutNode, to builder: inout DiagramSceneBuilder) {
        switch node.form {
        case .junction(let center, let radius):
            builder.fill(CGPath(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius), transform: nil), .line,
                         part: .node)
        case .service(let square, let icon, let iconText, let title):
            builder.fillAndStroke(CGPath(roundedRect: square, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil), fill: .surface, stroke: .border,
                                  DiagramStroke(lineWidth: 1), part: .node)
            add(icon, to: &builder)
            builder.text(iconText, .foreground, part: .iconText)
            builder.text(title, .foreground, part: .label)
        }
    }

    /// An icon Pele has an outline for, stroked in the text color 1.5 units of its 24-unit grid wide; nothing for another.
    static func add(_ icon: ArchitectureLayoutIcon?, to builder: inout DiagramSceneBuilder) {
        guard let icon, let outline = ReferenceArchitectureScenePaths.outline(named: icon.name, in: icon.frame) else { return }
        let lineWidth = ArchitectureIcons.gridLineWidth * min(icon.frame.width, icon.frame.height) / DiagramGlyphPath.standardGridSide
        builder.stroke(outline, .foreground, .rounded(lineWidth: lineWidth), part: .icon)
    }
}
