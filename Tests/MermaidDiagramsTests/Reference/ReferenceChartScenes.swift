/**
 * File: ReferenceChartScenes.swift
 * --------------------------------
 * Layer: Tests
 * Description: 0.7.0's pie, radar, packet, Sankey, quadrant and XY chart scenes, frozen as main
 *              2a0cc65 made them from Core Graphics paths (the public drawing parts and the builder's Core Graphics
 *              paths), which the scenes recorded into lanes are compared with.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// 0.7.0's chart scenes, made from Core Graphics paths.
enum ReferenceChartScene {}

extension ReferenceChartScene {
    /// The pie chart's painting: the slices and the legend's swatches in their series colors, the slices' edges, the
    /// percentages, the legend, the title.
    static func scene(layout: PieChartLayout) -> DiagramScene {
        var builder = DiagramSceneBuilder()
        PieChartDrawingParts(layout: layout).referenceAddScene(to: &builder)
        return builder.scene(size: layout.size, font: layout.font, seriesColors: layout.seriesColors)
    }
}

extension PieChartDrawingParts {
    /// Lines have butt caps and round joins.
    func referenceAddScene(to builder: inout DiagramSceneBuilder) {
        let line = DiagramStroke(lineWidth: Self.lineWidth, lineJoin: .round)
        for (index, seriesFill) in seriesFills.enumerated() { builder.fill(seriesFill, .series(index), part: .node) }
        builder.stroke(sliceEdges, .background, line, part: .node)
        builder.stroke(emptyPieOutline, .border, line, part: .node)
        for (percentage, paint) in zip(insidePercentages, insidePercentagePaints) { builder.text(percentage, paint, part: .label) }
        builder.texts(outsidePercentages, .foreground, part: .label)
        builder.texts(legendTexts, .foreground, part: .legend)
        builder.title(title)
    }
}

extension ReferenceChartScene {
    /// The radar chart's painting: the title, the graticule in the second surface color, the spokes in the border color, the
    /// curves each in its series color (filled at a fifth, outlined), the axes' labels, the legend.
    static func scene(layout: RadarChartLayout) -> DiagramScene {
        var builder = DiagramSceneBuilder()
        RadarChartDrawingParts(layout: layout).referenceAddScene(to: &builder)
        return builder.scene(size: layout.size, font: layout.font, seriesColors: layout.seriesColors)
    }
}

extension RadarChartDrawingParts {
    func referenceAddScene(to builder: inout DiagramSceneBuilder) {
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

extension ReferenceChartScene {
    /// The packet diagram's painting: the fields' boxes in the surface and border colors, their labels, the bit numbers
    /// in the muted color, the title.
    static func scene(layout: PacketDiagramLayout) -> DiagramScene {
        var builder = DiagramSceneBuilder()
        PacketDiagramDrawingParts(layout: layout).referenceAddScene(to: &builder)
        return builder.scene(size: layout.size, font: layout.font)
    }
}

extension PacketDiagramDrawingParts {
    func referenceAddScene(to builder: inout DiagramSceneBuilder) {
        builder.fillAndStroke(fieldBoxes, fill: .surface, stroke: .border, DiagramStroke(lineWidth: Self.lineWidth), part: .node)
        builder.texts(fieldLabels, .foreground, part: .label)
        builder.texts(bitNumbers, .muted, part: .bitNumber)
        builder.title(title)
    }
}

extension ReferenceChartScene {
    /// The Sankey diagram's painting: each band in a gradient across from its source's color to its target's (or in the
    /// source's, the target's or one color, as the options say) at `SankeyDrawingParts.bandOpacity`, the bars in their
    /// series colors or their own, the names, the values in the muted color (both outlined in the background color when
    /// the options say so), the title.
    static func scene(layout: SankeyLayout) -> DiagramScene {
        var builder = DiagramSceneBuilder()
        SankeyDrawingParts(layout: layout).referenceAddScene(to: &builder)
        return builder.scene(size: layout.size, font: layout.font)
    }
}

extension SankeyDrawingParts {
    func referenceAddScene(to builder: inout DiagramSceneBuilder) {
        for band in bands {
            let sourcePaint = band.sourcePaint
            let targetPaint = band.targetPaint
            if let fixedLinkPaint {
                builder.fill(band.outline, fixedLinkPaint.atOpacity(Self.bandOpacity), part: .edge)
                continue
            }
            switch linkColor {
            case .gradient:
                let gradient = DiagramLinearGradient(startPaint: sourcePaint, endPaint: targetPaint, startPoint: CGPoint(x: band.startX, y: 0),
                                                     endPoint: CGPoint(x: band.endX, y: 0), opacity: Self.bandOpacity)
                builder.fill(band.outline, gradient, part: .edge)
            case .source: builder.fill(band.outline, sourcePaint.atOpacity(Self.bandOpacity), part: .edge)
            case .target: builder.fill(band.outline, targetPaint.atOpacity(Self.bandOpacity), part: .edge)
            case .fixed(let color): builder.fill(band.outline, DiagramPaint.color(color).atOpacity(Self.bandOpacity), part: .edge)
            }
        }
        for (index, nodeFill) in nodeFills.enumerated() { builder.fill(nodeFill, .series(index), part: .node) }
        for colored in coloredNodeFills { builder.fill(colored.path, .color(colored.color), part: .node) }
        for painted in paintedNodeFills { builder.fill(painted.path, painted.paint, part: .node) }
        let outline = hasOutlinedLabels ? DiagramTextOutline(paint: .background, lineWidth: Self.labelOutlineWidth) : nil
        builder.texts(names, .foreground, outline: outline, part: .label)
        builder.texts(values, .muted, outline: outline, part: .label)
        builder.title(title)
    }
}

extension ReferenceChartScene {
    /// The quadrant chart's painting: the quadrants in the surface and border colors with their texts, the axes' texts
    /// in the muted color (the y axis's turned a quarter anticlockwise), the points in the first series color or the
    /// colors the chart writes, their texts, the title.
    static func scene(layout: QuadrantChartLayout) -> DiagramScene {
        var builder = DiagramSceneBuilder()
        QuadrantChartDrawingParts(layout: layout).referenceAddScene(to: &builder)
        return builder.scene(size: layout.size, font: layout.font)
    }
}

extension QuadrantChartDrawingParts {
    /// A quarter turn anticlockwise on a page whose y runs down.
    static let referenceTurnedTextRotation: CGFloat = -.pi / 2

    func referenceAddScene(to builder: inout DiagramSceneBuilder) {
        builder.fillAndStroke(quadrants, fill: .surface, stroke: .border, DiagramStroke(lineWidth: Self.lineWidth), part: .cluster)
        builder.texts(quadrantTexts, .foreground, part: .clusterLabel)
        builder.texts(axisTexts, .muted, part: .axisLabel)
        for turnedText in turnedAxisTexts { builder.text(turnedText, .muted, rotation: Self.referenceTurnedTextRotation, part: .axisLabel) }
        for group in pointGroups {
            builder.fill(group.circles, Self.referencePaint(group.fill), part: .node)
            if let stroke = group.stroke { builder.stroke(group.circles, Self.referencePaint(stroke.paint), DiagramStroke(lineWidth: stroke.width), part: .node) }
        }
        builder.texts(pointTexts, .foreground, part: .label)
        builder.title(title)
    }

    /// The paint a point's paint stands for: the first series color, or the color the chart writes.
    static func referencePaint(_ paint: QuadrantChartPaint) -> DiagramPaint {
        switch paint {
        case .firstSeries: .series(0)
        case .written(let color): .color(DiagramColor(red: Double(color.red) / 255, green: Double(color.green) / 255, blue: Double(color.blue) / 255))
        }
    }
}

extension ReferenceChartScene {
    /// The XY chart's painting: the grid, the bars in their series colors, the lines with their dots, the axes, then the
    /// marks' labels in the muted color, the other text (the left axis' title turned a quarter anticlockwise) and the
    /// title.
    static func scene(layout: XYChartLayout) -> DiagramScene {
        var builder = DiagramSceneBuilder()
        XYChartDrawingParts(layout: layout).referenceAddScene(to: &builder)
        return builder.scene(size: layout.size, font: layout.font, seriesColors: layout.seriesColors)
    }
}

extension XYChartDrawingParts {
    /// A quarter turn anticlockwise on a page whose y runs down.
    static let referenceTurnedTextRotation: CGFloat = -.pi / 2

    func referenceAddScene(to builder: inout DiagramSceneBuilder) {
        builder.stroke(gridLines, .alternateSurface, DiagramStroke(lineWidth: Self.lineWidth), part: .axis)
        for (index, barFill) in barFills.enumerated() { builder.fill(barFill, .series(index), part: .node) }
        for line in lines {
            let paint = DiagramPaint.series(line.seriesIndex)
            builder.stroke(line.stroke, paint, .rounded(lineWidth: Self.seriesLineWidth), part: .edge)
            builder.fill(line.dots, paint, part: .marker)
        }
        builder.stroke(axisLines, .border, DiagramStroke(lineWidth: Self.lineWidth, lineJoin: .round), part: .axis)
        builder.texts(axisLabels, .muted, part: .axisLabel)
        builder.texts(texts, .foreground, part: .label)
        builder.text(turnedText, .foreground, rotation: Self.referenceTurnedTextRotation, part: .axisLabel)
        builder.title(title)
    }
}
