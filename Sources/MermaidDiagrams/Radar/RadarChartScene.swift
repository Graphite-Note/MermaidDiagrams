/**
 * File: RadarChartScene.swift
 * ---------------------------
 * Layer: Core
 * Description: A laid-out radar chart's scene: its graticule, spokes, curves and swatches recorded into lanes of the
 *              thread's scene workspace and added back to front in the colors' roles, as Pele paints them, without a Core
 *              Graphics path.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 24/11/2026
 */

import CoreGraphics

extension DiagramScene {
    /// The radar chart's painting: the title, the graticule in the second surface color, the spokes in the border color, the
    /// curves each in its series color (filled at a fifth, outlined), the axes' labels, the legend.
    public init(layout: RadarChartLayout) {
        self = DiagramSceneWorkspace.withRecording { workspace in
            var builder = DiagramSceneBuilder(workspace: workspace)
            RadarChartSceneRecording.add(layout, to: &builder, workspace: workspace)
            return builder.scene(size: layout.size, font: layout.font, seriesColors: layout.seriesColors)
        }
    }
}

/// Adds a radar chart's painting to a scene, its paths recorded into lanes of `workspace` element for element as
/// `RadarChartDrawingParts` records them into Core Graphics paths; a curve's or a swatch's lane is given back once added.
enum RadarChartSceneRecording {
    static func add(_ layout: RadarChartLayout, to builder: inout DiagramSceneBuilder, workspace: DiagramSceneWorkspace) {
        typealias Parts = RadarChartDrawingParts
        builder.title(layout.title)
        builder.stroke(graticule(of: layout, workspace: workspace), .alternateSurface, DiagramStroke(lineWidth: Parts.lineWidth), part: .graticule)
        let spokes = workspace.makeLane()
        for direction in layout.axisDirections {
            spokes.move(to: layout.center)
            spokes.addLine(to: CGPoint(x: layout.center.x + direction.x * layout.spokeLength, y: layout.center.y + direction.y * layout.spokeLength))
        }
        builder.stroke(spokes, .border, DiagramStroke(lineWidth: Parts.lineWidth), part: .axis)
        for curve in layout.curves {
            let madeCount = workspace.madePathCount
            let path = workspace.makeLane()
            if curve.isRounded {
                RadarCurveSpline.addClosedCurve(through: curve.points, tension: curve.tension, to: path)
            } else {
                RadarCurveSpline.addClosedPolygon(through: curve.points, to: path)
            }
            builder.fillAndStroke(path, fill: DiagramPaint.series(curve.seriesIndex).atOpacity(Parts.curveFillOpacity), stroke: .series(curve.seriesIndex),
                                  DiagramStroke(lineWidth: Parts.curveLineWidth, lineJoin: .round), part: .curve)
            workspace.givePathsBack(downTo: madeCount)
        }
        builder.texts(layout.axisLabels, .foreground, part: .axisLabel)
        for entry in layout.legend {
            let madeCount = workspace.madePathCount
            let swatch = workspace.makeLane()
            swatch.addRoundedRect(in: entry.swatch, cornerWidth: Parts.swatchCornerRadius, cornerHeight: Parts.swatchCornerRadius)
            builder.fillAndStroke(swatch, fill: DiagramPaint.series(entry.seriesIndex).atOpacity(Parts.swatchFillOpacity), stroke: .series(entry.seriesIndex),
                                  DiagramStroke(lineWidth: Parts.lineWidth), part: .legend)
            workspace.givePathsBack(downTo: madeCount)
        }
        for entry in layout.legend { builder.text(entry.text, .foreground, part: .legend) }
    }

    /// The rings: circles, or polygons through the axes' directions, each added to the graticule as a path of its own.
    private static func graticule(of layout: RadarChartLayout, workspace: DiagramSceneWorkspace) -> DiagramPathLane {
        let graticule = workspace.makeLane()
        for ringRadius in layout.ringRadii {
            switch layout.graticule {
            case .circle:
                graticule.addEllipse(in: CGRect(x: layout.center.x - ringRadius, y: layout.center.y - ringRadius, width: 2 * ringRadius,
                                                height: 2 * ringRadius))
            case .polygon:
                let madeCount = workspace.madePathCount
                let ring = workspace.makeLane()
                RadarCurveSpline.addClosedPolygon(through: layout.axisDirections.map { direction in
                    CGPoint(x: layout.center.x + direction.x * ringRadius, y: layout.center.y + direction.y * ringRadius)
                }, to: ring)
                graticule.addPath(ring)
                workspace.givePathsBack(downTo: madeCount)
            }
        }
        return graticule
    }
}
