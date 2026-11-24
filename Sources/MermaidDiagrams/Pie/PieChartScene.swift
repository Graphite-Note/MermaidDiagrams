/**
 * File: PieChartScene.swift
 * -------------------------
 * Layer: Core
 * Description: A laid-out pie chart's scene: its drawing parts back to front in the colors' roles, as Pele paints them.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 23/11/2026
 */

import CoreGraphics

extension DiagramScene {
    /// The pie chart's painting: the slices and the legend's swatches in their series colors, the slices' edges, the
    /// percentages, the legend, the title.
    public init(layout: PieChartLayout) {
        var builder = DiagramSceneBuilder()
        PieChartDrawingParts(layout: layout).addScene(to: &builder)
        self = builder.scene(size: layout.size, font: layout.font, seriesColors: layout.seriesColors)
    }
}

extension PieChartDrawingParts {
    /// Lines have butt caps and round joins.
    func addScene(to builder: inout DiagramSceneBuilder) {
        let line = DiagramStroke(lineWidth: Self.lineWidth, lineJoin: .round)
        for (index, seriesFill) in seriesFillsScenePaths.enumerated() { builder.fill(seriesFill, .series(index), part: .node) }
        builder.stroke(sliceEdgesScenePath, .background, line, part: .node)
        builder.stroke(emptyPieOutlineScenePath, .border, line, part: .node)
        for (percentage, paint) in zip(insidePercentages, insidePercentagePaints) { builder.text(percentage, paint, part: .label) }
        builder.texts(outsidePercentages, .foreground, part: .label)
        builder.texts(legendTexts, .foreground, part: .legend)
        builder.title(title)
    }
}
