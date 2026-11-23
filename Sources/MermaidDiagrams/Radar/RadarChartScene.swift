/**
 * File: RadarChartScene.swift
 * ---------------------------
 * Layer: Core
 * Description: A laid-out radar chart's scene: its drawing parts back to front in the colors' roles, as Pele paints them.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

import CoreGraphics

extension DiagramScene {
    /// The radar chart's painting: the title, the graticule in the second surface color, the spokes in the border color, the
    /// curves each in its series color (filled at a fifth, outlined), the axes' labels, the legend.
    public init(layout: RadarChartLayout) {
        var builder = DiagramSceneBuilder()
        RadarChartDrawingParts(layout: layout).addScene(to: &builder)
        self = builder.scene(size: layout.size, font: layout.font, seriesColors: layout.seriesColors)
    }
}

extension RadarChartDrawingParts {
    func addScene(to builder: inout DiagramSceneBuilder) {
        builder.title(title)
        builder.stroke(graticule, .alternateSurface, DiagramStroke(lineWidth: Self.lineWidth), part: .graticule)
        builder.stroke(spokes, .border, DiagramStroke(lineWidth: Self.lineWidth), part: .axis)
        for curve in curves {
            builder.fillAndStroke(curve.path, fill: DiagramPaint.series(curve.seriesIndex).atOpacity(Self.curveFillOpacity), stroke: .series(curve.seriesIndex),
                                  DiagramStroke(lineWidth: Self.curveLineWidth, lineJoin: .round), part: .curve)
        }
        builder.texts(axisLabels, .foreground, part: .axisLabel)
        for swatch in legendSwatches {
            builder.fillAndStroke(swatch.path, fill: DiagramPaint.series(swatch.seriesIndex).atOpacity(Self.swatchFillOpacity), stroke: .series(swatch.seriesIndex),
                                  DiagramStroke(lineWidth: Self.lineWidth), part: .legend)
        }
        builder.texts(legendTexts, .foreground, part: .legend)
    }
}
