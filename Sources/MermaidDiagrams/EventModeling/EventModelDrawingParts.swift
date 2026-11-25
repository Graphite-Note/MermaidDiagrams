/**
 * File: EventModelDrawingParts.swift
 * ----------------------------------
 * Layer: Core
 * Description: A laid-out event model's geometry grouped by how it is painted, its scene in Pele's colors and order, and
 *              its renderer.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 25/11/2026
 */

import CoreGraphics

/// A laid-out event model's geometry grouped by how it is painted, back to front as Pele draws it: the lanes' bands in
/// the surface color and their names (down a column, the names after the relations), the relations' lines and arrows,
/// the frames' boxes (on the background, each
/// kind's series color over it at `seriesFillOpacity` and outlined in it, a user interface outlined in the border
/// color), their names, numbers and data, then the notes' and specifications' cards, and the title.
public struct EventModelDrawingParts {
    public let laneBands: CGPath
    public let laneNames: [DiagramTextBlock]
    public let relationLines: CGPath
    public let arrows: CGPath
    /// The boxes filled in the background color and outlined in the border color: a user interface's across, every
    /// box down a column.
    public let outlinedBoxes: CGPath
    /// The boxes of the other kinds filled in the background color, under their series color, across.
    public let plainBoxes: CGPath
    /// For each series index used, the boxes filled in it at `seriesFillOpacity` and outlined in it.
    public let seriesBoxes: [(seriesIndex: Int, boxes: CGPath)]
    public let names: [DiagramTextBlock]
    /// The frames' numbers down a column, in the muted color.
    public let numbers: [DiagramTextBlock]
    /// Drawn in the system's monospaced font.
    public let dataLines: [DiagramTextBlock]
    public let cards: CGPath
    public let cardHeadings: [DiagramTextBlock]
    public let cardLines: [DiagramTextBlock]
    public let title: DiagramTextBlock?
    /// Whether the model runs down a column, where Pele draws the relations before the lanes' names, which belong to
    /// the cards' groups; across, the lanes and their names come first.
    public let runsDown: Bool

    /// Pele's `fill-opacity` for a kind's color over its box.
    public static let seriesFillOpacity: CGFloat = 0.22
    static let cornerRadius: CGFloat = 4

    public init(layout: EventModelLayout) {
        let paths = EventModelDrawingPaths(layout: layout, making: DiagramCoreGraphicsPaths())
        laneBands = paths.laneBands.path
        laneNames = layout.laneNames
        relationLines = paths.relationLines.path
        arrows = paths.arrows.path
        outlinedBoxes = paths.outlinedBoxes.path
        plainBoxes = paths.plainBoxes.path
        seriesBoxes = paths.seriesBoxes.map { group in (group.seriesIndex, group.boxes.path) }
        names = layout.frames.map(\.name)
        numbers = layout.frames.compactMap(\.number)
        dataLines = layout.frames.flatMap(\.dataLines)
        cards = paths.cards.path
        cardHeadings = layout.cards.map(\.heading)
        cardLines = layout.cards.flatMap(\.lines)
        title = layout.title
        runsDown = layout.runsDown
    }
}

/// An event model's paths, grouped as `EventModelDrawingParts` groups them, recorded into the paths a maker makes:
/// Core Graphics paths for the drawing parts, lanes of the thread's scene workspace for the scene, the same elements.
struct EventModelDrawingPaths<Path: DiagramCurvedPathRecording> {
    let laneBands: Path
    let relationLines: Path
    let arrows: Path
    let outlinedBoxes: Path
    let plainBoxes: Path
    /// For each series index used, from the smallest, the boxes in it.
    let seriesBoxes: [(seriesIndex: Int, boxes: Path)]
    let cards: Path

    init<Maker: DiagramPathMaking>(layout: EventModelLayout, making maker: Maker) where Maker.Path == Path {
        let radius = EventModelDrawingParts.cornerRadius
        laneBands = maker.makePath()
        for band in layout.laneBands { laneBands.addRoundedRect(in: band, cornerWidth: radius, cornerHeight: radius) }
        relationLines = maker.makePath()
        arrows = maker.makePath()
        let unused = maker.makePath()
        for relation in layout.relations {
            maker.addEdgeLineInPlace(relation.path, to: relationLines)
            DiagramEdgeDrawing.addMark(relation.arrow, filled: arrows, stroked: unused)
        }
        outlinedBoxes = maker.makePath()
        plainBoxes = maker.makePath()
        var seriesIndices: [Int] = []
        for frame in layout.frames {
            let boxes = frame.isOutlinedInBorder || frame.seriesIndex == nil ? outlinedBoxes : plainBoxes
            boxes.addRoundedRect(in: frame.frame, cornerWidth: radius, cornerHeight: radius)
            if let index = frame.seriesIndex, !seriesIndices.contains(index) { seriesIndices.append(index) }
        }
        seriesIndices.sort()
        seriesBoxes = seriesIndices.map { index in
            let boxes = maker.makePath()
            for frame in layout.frames where frame.seriesIndex == index {
                boxes.addRoundedRect(in: frame.frame, cornerWidth: radius, cornerHeight: radius)
            }
            return (index, boxes)
        }
        cards = maker.makePath()
        for card in layout.cards { cards.addRoundedRect(in: card.frame, cornerWidth: radius, cornerHeight: radius) }
    }
}

extension DiagramScene {
    /// The event model's painting, in Pele's order and colors, its paths recorded into lanes of the thread's scene
    /// workspace.
    public init(layout: EventModelLayout) {
        self.init(layout: layout, limits: .standard)
    }

    /// The scene with each of its lanes bounded as `limits` bound them (`DiagramSceneWorkspace.elementLimit(for:)`): a
    /// lane past its limit is emptied and the scene says so (`exceededPathElementLimit`), which the preparation refuses.
    public init(layout: EventModelLayout, limits: MermaidDiagramLimits) {
        self = DiagramSceneWorkspace.withRecording(limits: limits) { workspace in
            var builder = DiagramSceneBuilder(workspace: workspace)
            EventModelSceneRecording.add(layout, to: &builder, paths: EventModelDrawingPaths(layout: layout, making: workspace))
            return builder.scene(size: layout.size, font: layout.font)
        }
    }
}

/// Adds an event model's painting to a scene from its paths.
enum EventModelSceneRecording {
    static func add(_ layout: EventModelLayout, to builder: inout DiagramSceneBuilder, paths: EventModelDrawingPaths<DiagramPathLane>) {
        let line = DiagramStroke(lineWidth: 1)
        builder.title(layout.title)
        builder.fill(paths.laneBands, .surface, part: .cluster)
        if !layout.runsDown { builder.texts(layout.laneNames, .muted, isBold: true, part: .clusterLabel) }
        builder.stroke(paths.relationLines, .line, line, part: .edge)
        builder.fill(paths.arrows, .line, part: .marker)
        if layout.runsDown { builder.texts(layout.laneNames, .muted, isBold: true, part: .clusterLabel) }
        builder.fillAndStroke(paths.outlinedBoxes, fill: .background, stroke: .border, line, part: .node)
        builder.fill(paths.plainBoxes, .background, part: .node)
        for (seriesIndex, boxes) in paths.seriesBoxes {
            builder.fillAndStroke(boxes, fill: DiagramPaint.series(seriesIndex).atOpacity(EventModelDrawingParts.seriesFillOpacity),
                                  stroke: .series(seriesIndex), line, part: .node)
        }
        for frame in layout.frames { builder.text(frame.name, .foreground, isBold: true, part: .label) }
        for frame in layout.frames { builder.text(frame.number, .muted, part: .label) }
        for frame in layout.frames { builder.texts(frame.dataLines, .foreground, isMonospaced: true, part: .label) }
        builder.fillAndStroke(paths.cards, fill: .background, stroke: .border, line, part: .note)
        for card in layout.cards { builder.text(card.heading, .foreground, isBold: true, part: .note) }
        for card in layout.cards { builder.texts(card.lines, .foreground, part: .note) }
    }
}

/// Draws a laid-out event model into a Core Graphics context whose origin is the layout's top left and whose y runs
/// down, by painting its scene with `DiagramSceneRenderer`.
public enum EventModelRenderer {
    public static func draw(_ layout: EventModelLayout, in context: CGContext, palette: DiagramPalette) {
        DiagramSceneRenderer.draw(DiagramScene(layout: layout), in: context, palette: palette)
    }
}
