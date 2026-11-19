/**
 * File: PieChartScene.swift
 * -------------------------
 * Layer: Core
 * Description: A laid-out pie chart's scene: its drawing parts back to front in the colors' roles, as Pele paints them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

extension DiagramScene {
    /// The pie chart's painting: the slices and the legend's swatches in their series colors, the slices' edges, the
    /// percentages, the legend, the title.
    public init(layout: PieChartLayout) {
        var builder = DiagramSceneBuilder()
        PieChartDrawingParts(layout: layout).addScene(to: &builder)
        self = builder.scene(size: layout.size, font: layout.font)
    }
}

extension PieChartDrawingParts {
    /// Lines have butt caps and round joins.
    func addScene(to builder: inout DiagramSceneBuilder) {
        let line = DiagramStroke(lineWidth: Self.lineWidth, lineJoin: .round)
        for (index, seriesFill) in seriesFills.enumerated() { builder.fill(seriesFill, .series(index), part: .node) }
        builder.stroke(sliceEdges, .background, line, part: .node)
        builder.stroke(emptyPieOutline, .border, line, part: .node)
        builder.texts(insidePercentages, .background, part: .label)
        builder.texts(outsidePercentages, .foreground, part: .label)
        builder.texts(legendTexts, .foreground, part: .legend)
        builder.title(title)
    }
}
