/**
 * File: XYChartScene.swift
 * ------------------------
 * Layer: Core
 * Description: A laid-out XY chart's scene: its grid, bars, lines, dots and axes recorded into lanes of the thread's
 *              scene workspace and added back to front in the colors' roles, as Pele paints them, without a Core Graphics
 *              path.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 24/11/2026
 */

import CoreGraphics

extension DiagramScene {
    /// The XY chart's painting: the grid, the bars in their series colors, the lines with their dots, the axes, then the
    /// marks' labels in the muted color, the other text (the left axis' title turned a quarter anticlockwise) and the
    /// title.
    public init(layout: XYChartLayout) {
        self = DiagramSceneWorkspace.withRecording { workspace in
            var builder = DiagramSceneBuilder(workspace: workspace)
            XYChartSceneRecording.add(layout, to: &builder, workspace: workspace)
            return builder.scene(size: layout.size, font: layout.font, seriesColors: layout.seriesColors)
        }
    }
}

/// Adds an XY chart's painting to a scene, its paths recorded into lanes of `workspace` element for element as
/// `XYChartDrawingParts` records them into Core Graphics paths; each series color's bars and each line are recorded in a
/// lane given back once added.
enum XYChartSceneRecording {
    static func add(_ layout: XYChartLayout, to builder: inout DiagramSceneBuilder, workspace: DiagramSceneWorkspace) {
        typealias Parts = XYChartDrawingParts
        builder.stroke(segments(layout.gridLines, workspace: workspace), .alternateSurface, DiagramStroke(lineWidth: Parts.lineWidth), part: .axis)
        addBars(of: layout, to: &builder, workspace: workspace)
        for line in layout.lines {
            let madeCount = workspace.madePathCount
            let stroke = workspace.makeLane()
            for run in line.runs where !run.isEmpty { stroke.addLines(between: run) }
            for entry in layout.legend where entry.kind == .line && entry.seriesIndex == line.seriesIndex {
                stroke.move(to: CGPoint(x: entry.swatch.minX, y: entry.swatch.midY))
                stroke.addLine(to: CGPoint(x: entry.swatch.maxX, y: entry.swatch.midY))
            }
            let dots = workspace.makeLane()
            let radius = Parts.dotRadius
            for dot in line.dots { dots.addEllipse(in: CGRect(x: dot.x - radius, y: dot.y - radius, width: 2 * radius, height: 2 * radius)) }
            let paint = DiagramPaint.series(line.seriesIndex)
            builder.stroke(stroke, paint, .rounded(lineWidth: Parts.seriesLineWidth), part: .edge)
            builder.fill(dots, paint, part: .marker)
            workspace.givePathsBack(downTo: madeCount)
        }
        builder.stroke(segments(layout.axisLines, workspace: workspace), .border, DiagramStroke(lineWidth: Parts.lineWidth, lineJoin: .round), part: .axis)
        builder.texts(layout.axisLabels, .muted, part: .axisLabel)
        builder.text(layout.bottomAxisTitle, .foreground, part: .label)
        builder.texts(layout.barValues, .foreground, part: .label)
        builder.texts(layout.pointLabels, .foreground, part: .label)
        for entry in layout.legend { builder.text(entry.text, .foreground, part: .label) }
        builder.text(layout.leftAxisTitle, .foreground, rotation: Parts.turnedTextRotation, part: .axisLabel)
        builder.title(layout.title)
    }

    /// Each series color's bars and bar swatches, one fill a color, as many as the bars and swatches use.
    private static func addBars(of layout: XYChartLayout, to builder: inout DiagramSceneBuilder, workspace: DiagramSceneWorkspace) {
        let seriesColorCount = XYChartDrawingParts.seriesColorCount
        var largestSeriesIndex = -1
        for bar in layout.bars { largestSeriesIndex = max(largestSeriesIndex, bar.seriesIndex) }
        for entry in layout.legend where entry.kind == .bar { largestSeriesIndex = max(largestSeriesIndex, entry.seriesIndex) }
        let colorCount = min(seriesColorCount, largestSeriesIndex + 1)
        guard colorCount > 0 else { return }
        let radius = XYChartDrawingParts.swatchCornerRadius
        for colorIndex in 0..<colorCount {
            let madeCount = workspace.madePathCount
            let fill = workspace.makeLane()
            for bar in layout.bars where bar.seriesIndex % seriesColorCount == colorIndex { fill.addRect(bar.frame) }
            for entry in layout.legend where entry.kind == .bar && entry.seriesIndex % seriesColorCount == colorIndex {
                fill.addRoundedRect(in: entry.swatch, cornerWidth: radius, cornerHeight: radius)
            }
            builder.fill(fill, .series(colorIndex), part: .node)
            workspace.givePathsBack(downTo: madeCount)
        }
    }

    /// A move and a line for each segment.
    private static func segments(_ segments: [XYChartSegment], workspace: DiagramSceneWorkspace) -> DiagramPathLane {
        let path = workspace.makeLane()
        for segment in segments {
            path.move(to: segment.start)
            path.addLine(to: segment.end)
        }
        return path
    }
}

extension XYChartDrawingParts {
    /// A quarter turn anticlockwise on a page whose y runs down.
    static let turnedTextRotation: CGFloat = -.pi / 2
}
