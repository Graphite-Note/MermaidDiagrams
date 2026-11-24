/**
 * File: TimelineScene.swift
 * -------------------------
 * Layer: Core
 * Description: A laid-out timeline's scene: its drawing parts back to front in the colors' roles, as Pele paints them.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 23/11/2026
 */

import CoreGraphics

extension DiagramScene {
    /// The timeline's painting: the axis and its arrow in the line color, the lines to the events in the border color,
    /// per color the section and period boxes, the event boxes and the dots, the text on the boxes in the background
    /// color, the events' text and the title.
    public init(layout: TimelineLayout) {
        var builder = DiagramSceneBuilder()
        TimelineDrawingParts(layout: layout).addScene(to: &builder)
        self = builder.scene(size: layout.size, font: layout.font, seriesColors: layout.seriesColors)
    }
}

extension TimelineDrawingParts {
    func addScene(to builder: inout DiagramSceneBuilder) {
        let line = DiagramStroke(lineWidth: Self.lineWidth)
        builder.stroke(axisScenePath, .line, line, part: .axis)
        builder.fill(axisArrowScenePath, .line, part: .axis)
        builder.stroke(connectorsScenePath, .border, line, part: .edge)
        for group in colorGroups {
            let paint = Self.paint(group.color)
            builder.fill(group.boxesScenePath, paint, part: .node)
            builder.fill(group.eventBoxesScenePath, paint.atOpacity(Self.eventFillOpacity), part: .node)
            builder.fillAndStroke(group.dotsScenePath, fill: paint, stroke: .background, DiagramStroke(lineWidth: Self.dotOutlineWidth), part: .marker)
        }
        for (text, paint) in zip(sectionTexts, sectionTextPaints) { builder.text(text, paint, isBold: true, part: .clusterLabel) }
        for (text, paint) in zip(periodTexts, periodTextPaints) { builder.text(text, paint, part: .label) }
        builder.texts(eventTexts, .foreground, part: .label)
        builder.title(title)
    }

    static func paint(_ color: TimelineColor) -> DiagramPaint {
        switch color {
        case .series(let index): .series(index)
        case .muted: .muted
        }
    }
}
