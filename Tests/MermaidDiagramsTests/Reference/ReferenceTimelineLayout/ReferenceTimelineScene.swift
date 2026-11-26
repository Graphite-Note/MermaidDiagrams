/**
 * File: ReferenceTimelineScene.swift
 * ----------------------------------
 * Layer: Tests
 * Description: 0.7.0's timeline scene, frozen as main ba176e5 recorded it from a layout of text blocks and paths, which
 *              the scene of the flat timeline layout is compared with.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// Adds a timeline's painting to a scene, its paths recorded into lanes of `workspace`, grouped as
/// `TimelineDrawingParts` groups them.
enum ReferenceTimelineSceneRecording {
    /// The scene of `layout`, made as 0.7.0's `DiagramScene(layout:limits:)` made it.
    static func scene(_ layout: ReferenceTimelineLayout, limits: MermaidDiagramLimits = .standard) -> DiagramScene {
        DiagramSceneWorkspace.withRecording(limits: limits) { workspace in
            var builder = DiagramSceneBuilder(workspace: workspace)
            add(layout, to: &builder, workspace: workspace)
            return builder.scene(size: layout.size, font: layout.font, seriesColors: layout.seriesColors)
        }
    }


    /// The paint of text on a box of `color`, as `TimelineDrawingParts.ink(_:of:)` finds it.
    static func ink(_ color: TimelineColor, of layout: ReferenceTimelineLayout) -> DiagramPaint {
        guard case .series(let index) = color, let ink = layout.seriesColors.ink(ofSeries: index) else { return .background }
        return .color(ink)
    }

    static func add(_ layout: ReferenceTimelineLayout, to builder: inout DiagramSceneBuilder, workspace: DiagramSceneWorkspace) {
        let paths = ReferenceTimelineDrawingPaths(layout: layout, making: workspace)
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
        for section in layout.sections {
            builder.text(section.text, Self.ink(.series(section.sectionIndex), of: layout), isBold: true, part: .clusterLabel)
        }
        for period in layout.periods { builder.text(period.text, Self.ink(period.color, of: layout), part: .label) }
        for period in layout.periods {
            for event in period.events { builder.text(event.text, .foreground, part: .label) }
        }
        builder.title(layout.title)
    }
}


/// A timeline's paths, grouped as `TimelineDrawingParts` groups them, recorded into the paths a maker makes: Core
/// Graphics paths for the drawing parts, lanes of the thread's scene workspace for the scene. Both record the same
/// elements, bit for bit.
struct ReferenceTimelineDrawingPaths<Path: DiagramPathRecording> {
    struct ColorGroup {
        let color: TimelineColor
        let boxes: Path
        let eventBoxes: Path
        let dots: Path
    }

    /// The groups with a box or a dot: the series colors in order, then the muted color.
    let colorGroups: [ColorGroup]
    let axis: Path
    let axisArrow: Path
    let connectors: Path

    init<Maker: DiagramPathMaking>(layout: ReferenceTimelineLayout, making maker: Maker) where Maker.Path == Path {
        let seriesCount = DiagramPalette.peleSeries.count
        var groups: [ColorGroup] = []
        groups.reserveCapacity(seriesCount + 1)
        for index in 0..<seriesCount {
            groups.append(ColorGroup(color: .series(index), boxes: maker.makePath(), eventBoxes: maker.makePath(), dots: maker.makePath()))
        }
        groups.append(ColorGroup(color: .muted, boxes: maker.makePath(), eventBoxes: maker.makePath(), dots: maker.makePath()))
        func group(for color: TimelineColor) -> ColorGroup {
            switch color {
            case .series(let index): groups[index % seriesCount]
            case .muted: groups[seriesCount]
            }
        }
        let radius = TimelineDrawingParts.boxCornerRadius
        for section in layout.sections {
            Self.addBox(section.frame, to: group(for: .series(section.sectionIndex)).boxes, radius: radius, making: maker)
        }
        connectors = maker.makePath()
        let dotRadius = TimelineDrawingParts.dotRadius
        for period in layout.periods {
            let paths = group(for: period.color)
            Self.addBox(period.frame, to: paths.boxes, radius: radius, making: maker)
            for event in period.events { Self.addBox(event.frame, to: paths.eventBoxes, radius: radius, making: maker) }
            paths.dots.addEllipse(in: CGRect(x: period.dot.x - dotRadius, y: period.dot.y - dotRadius, width: 2 * dotRadius, height: 2 * dotRadius))
            for connector in period.connectors { maker.addEdgeLineInPlace(connector, to: connectors) }
        }
        colorGroups = groups.filter { group in !(group.boxes.isEmpty && group.dots.isEmpty) }
        axis = maker.makePath()
        if let line = layout.axis { DiagramEdgeDrawing.record(line, into: axis) }
        axisArrow = maker.makePath()
        if let mark = layout.axisArrow { DiagramEdgeDrawing.addMark(mark, filled: axisArrow, stroked: maker.makePath()) }
    }

    /// Adds `CGPath(roundedRect:)` of `frame` to `paths`, as a box is added.
    private static func addBox<Maker: DiagramPathMaking>(_ frame: CGRect, to paths: Path, radius: CGFloat, making maker: Maker) where Maker.Path == Path {
        let madeCount = maker.madePathCount
        paths.addPath(maker.roundedRectangle(frame, cornerWidth: radius, cornerHeight: radius))
        maker.givePathsBack(downTo: madeCount)
    }
}
