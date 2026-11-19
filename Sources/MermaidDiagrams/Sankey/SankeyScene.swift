/**
 * File: SankeyScene.swift
 * -----------------------
 * Layer: Core
 * Description: A laid-out Sankey diagram's scene: its drawing parts back to front in the colors' roles, as Pele paints
 *              them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

extension DiagramScene {
    /// The Sankey diagram's painting: each band in a gradient across from its source's series color to its target's at
    /// `SankeyDrawingParts.bandOpacity`, the bars in their series colors, the names, the values in the muted color, the
    /// title.
    public init(layout: SankeyLayout) {
        var builder = DiagramSceneBuilder()
        SankeyDrawingParts(layout: layout).addScene(to: &builder)
        self = builder.scene(size: layout.size, font: layout.font)
    }
}

extension SankeyDrawingParts {
    func addScene(to builder: inout DiagramSceneBuilder) {
        for band in bands {
            let gradient = DiagramLinearGradient(startPaint: .series(band.sourceSeriesIndex), endPaint: .series(band.targetSeriesIndex),
                                                 startPoint: CGPoint(x: band.startX, y: 0), endPoint: CGPoint(x: band.endX, y: 0),
                                                 opacity: Self.bandOpacity)
            builder.fill(band.outline, gradient, part: .edge)
        }
        for (index, nodeFill) in nodeFills.enumerated() { builder.fill(nodeFill, .series(index), part: .node) }
        builder.texts(names, .foreground, part: .label)
        builder.texts(values, .muted, part: .label)
        builder.title(title)
    }
}
