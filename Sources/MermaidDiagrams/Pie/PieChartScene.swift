/**
 * File: PieChartScene.swift
 * -------------------------
 * Layer: Core
 * Description: A laid-out pie chart's scene: its slices, swatches and edges recorded into lanes of the thread's scene
 *              workspace and added back to front in the colors' roles, as Pele paints them, without a Core Graphics path.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 25/11/2026
 */

import CoreGraphics

extension DiagramScene {
    /// The pie chart's painting: the slices and the legend's swatches in their series colors, the slices' edges, the
    /// percentages, the legend, the title.
    public init(layout: PieChartLayout) {
        self.init(layout: layout, limits: .standard)
    }

    /// The same painting recorded under `limits`: a scene one of whose lanes goes past their element limit says so
    /// (`exceededPathElementLimit`), and the preparation refuses it.
    public init(layout: PieChartLayout, limits: MermaidDiagramLimits) {
        self = DiagramSceneWorkspace.withRecording(limits: limits) { workspace in
            var builder = DiagramSceneBuilder(workspace: workspace)
            PieChartSceneRecording.add(layout, to: &builder, workspace: workspace)
            return builder.scene(size: layout.size, font: layout.font, seriesColors: layout.seriesColors)
        }
    }
}

/// Adds a pie chart's painting to a scene, its paths recorded into lanes of `workspace` element for element as
/// `PieChartDrawingParts` records them into Core Graphics paths.
enum PieChartSceneRecording {
    /// Lines have butt caps and round joins.
    static func add(_ layout: PieChartLayout, to builder: inout DiagramSceneBuilder, workspace: DiagramSceneWorkspace) {
        let seriesColorCount = PieChartDrawingParts.seriesColorCount
        var seriesCount = 0
        for slice in layout.slices { seriesCount = max(seriesCount, slice.seriesIndex + 1) }
        for entry in layout.legend { seriesCount = max(seriesCount, entry.seriesIndex + 1) }
        let fillCount = min(seriesCount, seriesColorCount)
        withUnsafeTemporaryAllocation(of: DiagramPathLane.self, capacity: fillCount) { fills in
            for index in 0..<fillCount { fills.initializeElement(at: index, to: workspace.makeLane()) }
            let edges = workspace.makeLane()
            for slice in layout.slices {
                let madeCount = workspace.madePathCount
                let wedge = wedge(slice, center: layout.center, radius: layout.radius, innerRadius: layout.innerRadius, making: workspace)
                fills[slice.seriesIndex % seriesColorCount].addPath(wedge, alsoTo: edges)
                workspace.givePathsBack(downTo: madeCount)
            }
            for entry in layout.legend {
                fills[entry.seriesIndex % seriesColorCount].addRoundedRect(in: entry.swatch, cornerWidth: PieChartDrawingParts.swatchCornerRadius,
                                                                           cornerHeight: PieChartDrawingParts.swatchCornerRadius)
            }
            let line = DiagramStroke(lineWidth: PieChartDrawingParts.lineWidth, lineJoin: .round)
            for index in 0..<fillCount { builder.fill(fills[index], .series(index), part: .node) }
            builder.stroke(edges, .background, line, part: .node)
            if layout.slices.isEmpty {
                let pieFrame = CGRect(x: layout.center.x - layout.radius, y: layout.center.y - layout.radius, width: 2 * layout.radius,
                                      height: 2 * layout.radius)
                builder.stroke(workspace.ellipse(in: pieFrame), .border, line, part: .node)
            }
            _ = fills.deinitialize()
        }
        for slice in layout.slices where slice.percentagePlacement == .insideSlice {
            builder.text(slice.percentage, layout.seriesColors.ink(ofSeries: slice.seriesIndex).map(DiagramPaint.color) ?? .background, part: .label)
        }
        for slice in layout.slices where slice.percentagePlacement == .outsideRim { builder.text(slice.percentage, .foreground, part: .label) }
        for entry in layout.legend { builder.text(entry.text, .foreground, part: .legend) }
        builder.title(layout.title)
    }

    /// `PieChartDrawingParts.wedge` in a lane made for it, given back by the caller.
    private static func wedge(_ slice: PieChartLayoutSlice, center: CGPoint, radius: CGFloat, innerRadius: CGFloat,
                              making workspace: DiagramSceneWorkspace) -> DiagramPathLane {
        let start = slice.startAngle - .pi / 2
        let end = slice.isWholePie ? start + 2 * .pi : slice.endAngle - .pi / 2
        guard innerRadius > 0 else {
            guard !slice.isWholePie else {
                return workspace.ellipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius))
            }
            let wedge = workspace.makeLane()
            wedge.move(to: center)
            wedge.addLine(to: PieChartSlicePlacement.point(at: slice.startAngle, distance: radius, from: center))
            wedge.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
            wedge.closeSubpath()
            return wedge
        }
        let wedge = workspace.makeLane()
        wedge.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
        if slice.isWholePie {
            wedge.closeSubpath()
            wedge.move(to: CGPoint(x: center.x + innerRadius * cos(end), y: center.y + innerRadius * sin(end)))
        }
        wedge.addArc(center: center, radius: innerRadius, startAngle: end, endAngle: start, clockwise: true)
        wedge.closeSubpath()
        return wedge
    }
}
