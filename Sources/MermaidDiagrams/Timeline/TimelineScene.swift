/**
 * File: TimelineScene.swift
 * -------------------------
 * Layer: Core
 * Description: A laid-out timeline's scene: its drawing parts back to front in the colors' roles, as Pele paints them.
 *
 * Authors: Bahey Shalash
 * Version: 0.5
 * Date: 26/11/2026
 */

import CoreGraphics

extension DiagramScene {
    /// The timeline's painting: the axis and its arrow in the line color, the lines to the events in the border color,
    /// per color the section and period boxes, the event boxes and the dots, the text on the boxes in the background
    /// color, the events' text and the title. The paths are recorded into lanes of the thread's scene workspace.
    public init(layout: TimelineLayout) {
        self.init(layout: layout, limits: .standard)
    }

    /// The scene with each of its lanes bounded as `limits` bound them (`DiagramSceneWorkspace.elementLimit(for:)`): a
    /// lane past its limit is emptied and the scene says so (`exceededPathElementLimit`), which the preparation refuses.
    public init(layout: TimelineLayout, limits: MermaidDiagramLimits) {
        self = DiagramSceneWorkspace.withRecording(limits: limits) { workspace in
            var builder = DiagramSceneBuilder(workspace: workspace)
            TimelineSceneRecording.add(layout, to: &builder, workspace: workspace)
            return builder.scene(size: layout.size, font: layout.font, seriesColors: layout.seriesColors)
        }
    }
}

/// Adds a timeline's painting to a scene, its paths recorded into lanes of `workspace`, grouped as
/// `TimelineDrawingParts` groups them.
enum TimelineSceneRecording {
    static func add(_ layout: TimelineLayout, to builder: inout DiagramSceneBuilder, workspace: DiagramSceneWorkspace) {
        let paths = TimelineDrawingPaths(layout: layout, making: workspace)
        let line = DiagramStroke(lineWidth: TimelineDrawingParts.lineWidth)
        builder.stroke(paths.axis, .line, line, part: .axis)
        builder.fill(paths.axisArrow, .line, part: .axis)
        builder.stroke(paths.connectors, .border, line, part: .edge)
        for group in paths.colorGroups {
            let paint = TimelineDrawingParts.paint(group.color)
            builder.fill(group.boxes, paint, part: .node)
            builder.fill(group.eventBoxes, paint.atOpacity(TimelineDrawingParts.eventFillOpacity), part: .node)
            builder.fillAndStroke(group.dots, fill: paint, stroke: .background, DiagramStroke(lineWidth: TimelineDrawingParts.dotOutlineWidth),
                                  part: .marker)
        }
        // The texts are read from the layout's records and lines, measured from the timeline's bytes; the events are
        // in the order of their periods.
        let body = layout.body
        layout.text.withBytes { source in
            for section in body.sections {
                builder.text(section.text, of: layout.lines, source: source, TimelineDrawingParts.ink(.series(section.sectionIndex), of: layout), isBold: true,
                             part: .clusterLabel)
            }
            for period in body.periods {
                builder.text(period.text, of: layout.lines, source: source, TimelineDrawingParts.ink(period.color, of: layout), part: .label)
            }
            for event in body.events { builder.text(event.text, of: layout.lines, source: source, .foreground, part: .label) }
        }
        builder.title(layout.title)
    }
}

extension TimelineDrawingParts {
    static func paint(_ color: TimelineColor) -> DiagramPaint {
        switch color {
        case .series(let index): .series(index)
        case .muted: .muted
        }
    }
}
