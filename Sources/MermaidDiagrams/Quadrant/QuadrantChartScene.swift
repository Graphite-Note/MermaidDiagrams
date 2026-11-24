/**
 * File: QuadrantChartScene.swift
 * ------------------------------
 * Layer: Core
 * Description: A laid-out quadrant chart's scene: its drawing parts back to front in the colors' roles, as Pele paints
 *              them.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

import CoreGraphics

extension DiagramScene {
    /// The quadrant chart's painting: the quadrants in the surface and border colors with their texts, the axes' texts
    /// in the muted color (the y axis's turned a quarter anticlockwise), the points in the first series color or the
    /// colors the chart writes, their texts, the title.
    public init(layout: QuadrantChartLayout) {
        var builder = DiagramSceneBuilder()
        QuadrantChartDrawingParts(layout: layout).addScene(to: &builder)
        self = builder.scene(size: layout.size, font: layout.font)
    }
}

extension QuadrantChartDrawingParts {
    /// A quarter turn anticlockwise on a page whose y runs down.
    static let turnedTextRotation: CGFloat = -.pi / 2

    func addScene(to builder: inout DiagramSceneBuilder) {
        builder.fillAndStroke(quadrantsScenePath, fill: .surface, stroke: .border, DiagramStroke(lineWidth: Self.lineWidth), part: .cluster)
        builder.texts(quadrantTexts, .foreground, part: .clusterLabel)
        builder.texts(axisTexts, .muted, part: .axisLabel)
        for turnedText in turnedAxisTexts { builder.text(turnedText, .muted, rotation: Self.turnedTextRotation, part: .axisLabel) }
        for group in pointGroups {
            builder.fill(group.circlesScenePath, Self.paint(group.fill), part: .node)
            if let stroke = group.stroke { builder.stroke(group.circlesScenePath, Self.paint(stroke.paint), DiagramStroke(lineWidth: stroke.width), part: .node) }
        }
        builder.texts(pointTexts, .foreground, part: .label)
        builder.title(title)
    }

    /// The paint a point's paint stands for: the first series color, or the color the chart writes.
    static func paint(_ paint: QuadrantChartPaint) -> DiagramPaint {
        switch paint {
        case .firstSeries: .series(0)
        case .written(let color): .color(DiagramColor(red: Double(color.red) / 255, green: Double(color.green) / 255, blue: Double(color.blue) / 255))
        }
    }
}
