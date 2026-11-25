/**
 * File: QuadrantChartScene.swift
 * ------------------------------
 * Layer: Core
 * Description: A laid-out quadrant chart's scene: the quadrants and the points recorded into lanes of the thread's scene
 *              workspace and added back to front in the colors' roles, as Pele paints them, without a Core Graphics path.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

import CoreGraphics

extension DiagramScene {
    /// The quadrant chart's painting: the quadrants in the surface and border colors with their texts, the axes' texts
    /// in the muted color (the y axis's turned a quarter anticlockwise), the points in the first series color or the
    /// colors the chart writes, their texts, the title.
    public init(layout: QuadrantChartLayout) {
        self = DiagramSceneWorkspace.withRecording { workspace in
            var builder = DiagramSceneBuilder(workspace: workspace)
            QuadrantChartSceneRecording.add(layout, to: &builder, workspace: workspace)
            return builder.scene(size: layout.size, font: layout.font)
        }
    }
}

/// Adds a quadrant chart's painting to a scene, its paths recorded into lanes of `workspace` element for element as
/// `QuadrantChartDrawingParts` records them into Core Graphics paths.
enum QuadrantChartSceneRecording {
    static func add(_ layout: QuadrantChartLayout, to builder: inout DiagramSceneBuilder, workspace: DiagramSceneWorkspace) {
        let radius = QuadrantChartDrawingParts.cornerRadius
        let quadrants = workspace.makeLane()
        for quadrant in layout.quadrants { quadrants.addPathOfRoundedRect(quadrant.frame, cornerWidth: radius, cornerHeight: radius) }
        builder.fillAndStroke(quadrants, fill: .surface, stroke: .border, DiagramStroke(lineWidth: QuadrantChartDrawingParts.lineWidth), part: .cluster)
        for quadrant in layout.quadrants { builder.text(quadrant.text, .foreground, part: .clusterLabel) }
        for label in layout.axisLabels where !label.isTurned { builder.text(label.text, .muted, part: .axisLabel) }
        for label in layout.axisLabels where label.isTurned {
            builder.text(label.text, .muted, rotation: QuadrantChartDrawingParts.turnedTextRotation, part: .axisLabel)
        }
        addPoints(of: layout, to: &builder, workspace: workspace)
        for point in layout.points { builder.text(point.text, .foreground, part: .label) }
        builder.title(layout.title)
    }

    /// The points' circles back to front, grouped as `QuadrantChartDrawingParts.pointGroups` groups them: a group is
    /// added when the paint changes or a point has an outline, and its lane is given back.
    private static func addPoints(of layout: QuadrantChartLayout, to builder: inout DiagramSceneBuilder, workspace: DiagramSceneWorkspace) {
        let madeCount = workspace.madePathCount
        var circles = workspace.makeLane()
        var current: (fill: QuadrantChartPaint, stroke: QuadrantChartStroke?)?
        for point in layout.points.reversed() {
            if let paint = current, paint.fill != point.fill || paint.stroke != nil || point.stroke != nil {
                addGroup(circles, fill: paint.fill, stroke: paint.stroke, to: &builder)
                workspace.givePathsBack(downTo: madeCount)
                circles = workspace.makeLane()
            }
            circles.addEllipse(in: CGRect(x: point.center.x - point.radius, y: point.center.y - point.radius, width: 2 * point.radius,
                                          height: 2 * point.radius))
            current = (point.fill, point.stroke)
        }
        if let paint = current { addGroup(circles, fill: paint.fill, stroke: paint.stroke, to: &builder) }
        workspace.givePathsBack(downTo: madeCount)
    }

    private static func addGroup(_ circles: DiagramPathLane, fill: QuadrantChartPaint, stroke: QuadrantChartStroke?,
                                 to builder: inout DiagramSceneBuilder) {
        builder.fill(circles, QuadrantChartDrawingParts.paint(fill), part: .node)
        if let stroke { builder.stroke(circles, QuadrantChartDrawingParts.paint(stroke.paint), DiagramStroke(lineWidth: stroke.width), part: .node) }
    }
}

extension QuadrantChartDrawingParts {
    /// A quarter turn anticlockwise on a page whose y runs down.
    static let turnedTextRotation: CGFloat = -.pi / 2

    /// The paint a point's paint stands for: the first series color, or the color the chart writes.
    static func paint(_ paint: QuadrantChartPaint) -> DiagramPaint {
        switch paint {
        case .firstSeries: .series(0)
        case .written(let color): .color(DiagramColor(red: Double(color.red) / 255, green: Double(color.green) / 255, blue: Double(color.blue) / 255))
        }
    }
}
