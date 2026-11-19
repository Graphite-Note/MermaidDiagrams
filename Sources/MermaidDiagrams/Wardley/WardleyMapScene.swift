/**
 * File: WardleyMapScene.swift
 * ---------------------------
 * Layer: Core
 * Description: A laid-out Wardley map's scene, as Pele paints it: the title, the frame, the stages' and axes' texts, the
 *              pipelines, the links, the evolutions, the nodes with their labels, the annotations, notes and forces.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics
import Foundation

extension DiagramScene {
    /// The Wardley map's painting, back to front as Pele writes it: the title; the stages' lines dashed in the border
    /// color, the grid, the axes in the line color; the stages' names in the muted color and the axes' titles in bold;
    /// the pipelines' boxes on the surface color; the links in the line color, their labels muted; the evolutions in the
    /// accent color; each node's shape, inertia bar and label; the annotations; the notes in bold; the forces.
    public init(layout: WardleyMapLayout) {
        var builder = DiagramSceneBuilder()
        builder.title(layout.title)
        WardleyMapScenePaths.addFrame(of: layout, to: &builder)
        for pipeline in layout.pipelines {
            builder.fillAndStroke(WardleyMapScenePaths.rounded(pipeline.frame), fill: .surface, stroke: .border, DiagramStroke(lineWidth: 1), part: .wardleyPipeline)
            if let line = pipeline.line {
                builder.stroke(DiagramEdgeDrawing.path(line), .line, DiagramStroke(lineWidth: 1, dashLengths: [4, 4]), part: .wardleyPipeline)
            }
        }
        for link in layout.links {
            builder.stroke(DiagramEdgeDrawing.path(link.line), .line, DiagramStroke(lineWidth: 1, dashLengths: link.isDashed ? [6, 6] : []), part: .edge)
            builder.fill(WardleyMapScenePaths.arrows(link.arrows), .line, part: .marker)
            builder.text(link.label, .muted, part: .edgeLabel)
        }
        for trend in layout.trends {
            if let line = trend.line { builder.stroke(DiagramEdgeDrawing.path(line), .accent, DiagramStroke(lineWidth: 1, dashLengths: [4, 4]), part: .wardleyTrend) }
            builder.fill(WardleyMapScenePaths.arrows(trend.arrow.map { arrow in [arrow] } ?? []), .accent, part: .marker)
            builder.fillAndStroke(WardleyMapScenePaths.circle(trend.target, radius: 6), fill: .background, stroke: .accent, DiagramStroke(lineWidth: 1),
                                  part: .wardleyTrend)
        }
        for node in layout.nodes { WardleyMapScenePaths.add(node, to: &builder) }
        WardleyMapScenePaths.addAnnotations(of: layout, to: &builder)
        for note in layout.notes { builder.texts(note, .foreground, isBold: true, part: .wardleyNote) }
        for force in layout.forces {
            let outline = CGMutablePath()
            outline.addPath(DiagramEdgeDrawing.path(force.outline))
            outline.closeSubpath()
            let part: DiagramScenePart = force.isAccelerator ? .wardleyAccelerator : .wardleyDeaccelerator
            builder.fillAndStroke(outline, fill: .surface, stroke: .line, DiagramStroke(lineWidth: 1), part: part)
            builder.text(force.name, .foreground, isBold: true, part: part)
        }
        self = builder.scene(size: layout.size, font: layout.font)
    }
}

/// The shapes of a Wardley map's scene.
enum WardleyMapScenePaths {
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
