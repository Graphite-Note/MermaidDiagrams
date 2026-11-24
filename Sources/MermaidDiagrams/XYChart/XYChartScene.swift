/**
 * File: XYChartScene.swift
 * ------------------------
 * Layer: Core
 * Description: A laid-out XY chart's scene: its drawing parts back to front in the colors' roles, as Pele paints them.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 23/11/2026
 */

import CoreGraphics

extension DiagramScene {
    /// The XY chart's painting: the grid, the bars in their series colors, the lines with their dots, the axes, then the
    /// marks' labels in the muted color, the other text (the left axis' title turned a quarter anticlockwise) and the
    /// title.
    public init(layout: XYChartLayout) {
        var builder = DiagramSceneBuilder()
        XYChartDrawingParts(layout: layout).addScene(to: &builder)
        self = builder.scene(size: layout.size, font: layout.font, seriesColors: layout.seriesColors)
    }
}

extension XYChartDrawingParts {
    /// A quarter turn anticlockwise on a page whose y runs down.
    static let turnedTextRotation: CGFloat = -.pi / 2

    func addScene(to builder: inout DiagramSceneBuilder) {
        builder.stroke(gridLinesScenePath, .alternateSurface, DiagramStroke(lineWidth: Self.lineWidth), part: .axis)
        for (index, barFill) in barFillsScenePaths.enumerated() { builder.fill(barFill, .series(index), part: .node) }
        for line in lines {
            let paint = DiagramPaint.series(line.seriesIndex)
            builder.stroke(line.strokeScenePath, paint, .rounded(lineWidth: Self.seriesLineWidth), part: .edge)
            builder.fill(line.dotsScenePath, paint, part: .marker)
        }
        builder.stroke(axisLinesScenePath, .border, DiagramStroke(lineWidth: Self.lineWidth, lineJoin: .round), part: .axis)
        builder.texts(axisLabels, .muted, part: .axisLabel)
        builder.texts(texts, .foreground, part: .label)
        builder.text(turnedText, .foreground, rotation: Self.turnedTextRotation, part: .axisLabel)
        builder.title(title)
    }
}
