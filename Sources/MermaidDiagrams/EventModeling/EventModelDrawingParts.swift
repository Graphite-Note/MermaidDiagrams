/**
 * File: EventModelDrawingParts.swift
 * ----------------------------------
 * Layer: Core
 * Description: A laid-out event model's geometry grouped by how it is painted, its scene in Pele's colors and order, and
 *              its renderer.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

import CoreGraphics

/// A laid-out event model's geometry grouped by how it is painted, back to front as Pele draws it: the lanes' bands in
/// the surface color and their names (down a column, the names after the relations), the relations' lines and arrows,
/// the frames' boxes (on the background, each
/// kind's series color over it at `seriesFillOpacity` and outlined in it, a user interface outlined in the border
/// color), their names, numbers and data, then the notes' and specifications' cards, and the title.
public struct EventModelDrawingParts {
    public var laneBands: CGPath { laneBandsScenePath.coreGraphicsPath }
    let laneBandsScenePath: DiagramScenePath
    public let laneNames: [DiagramTextBlock]
    public var relationLines: CGPath { relationLinesScenePath.coreGraphicsPath }
    let relationLinesScenePath: DiagramScenePath
    public var arrows: CGPath { arrowsScenePath.coreGraphicsPath }
    let arrowsScenePath: DiagramScenePath
    /// The boxes filled in the background color and outlined in the border color: a user interface's across, every
    /// box down a column.
    public var outlinedBoxes: CGPath { outlinedBoxesScenePath.coreGraphicsPath }
    let outlinedBoxesScenePath: DiagramScenePath
    /// The boxes of the other kinds filled in the background color, under their series color, across.
    public var plainBoxes: CGPath { plainBoxesScenePath.coreGraphicsPath }
    let plainBoxesScenePath: DiagramScenePath
    /// For each series index used, the boxes filled in it at `seriesFillOpacity` and outlined in it.
    public var seriesBoxes: [(seriesIndex: Int, boxes: CGPath)] {
        seriesBoxesScenePaths.map { series in (series.seriesIndex, series.boxes.coreGraphicsPath) }
    }
    let seriesBoxesScenePaths: [(seriesIndex: Int, boxes: DiagramScenePath)]
    public let names: [DiagramTextBlock]
    /// The frames' numbers down a column, in the muted color.
    public let numbers: [DiagramTextBlock]
    /// Drawn in the system's monospaced font.
    public let dataLines: [DiagramTextBlock]
    public var cards: CGPath { cardsScenePath.coreGraphicsPath }
    let cardsScenePath: DiagramScenePath
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
        laneBandsScenePath = Self.roundedRectangles(layout.laneBands)
        laneNames = layout.laneNames
        var lines = DiagramScenePath()
        var arrows = DiagramScenePath()
        var unused = DiagramScenePath()
        for relation in layout.relations {
            lines.addEdgePath(relation.path)
            DiagramEdgeDrawing.addMark(relation.arrow, filled: &arrows, stroked: &unused)
        }
        relationLinesScenePath = lines
        self.arrowsScenePath = arrows
        outlinedBoxesScenePath = Self.roundedRectangles(layout.frames.filter { frame in frame.isOutlinedInBorder || frame.seriesIndex == nil }.map(\.frame))
        plainBoxesScenePath = Self.roundedRectangles(layout.frames.filter { frame in !frame.isOutlinedInBorder && frame.seriesIndex != nil }.map(\.frame))
        let seriesIndices = Set(layout.frames.compactMap(\.seriesIndex)).sorted()
        seriesBoxesScenePaths = seriesIndices.map { index in (index, Self.roundedRectangles(layout.frames.filter { frame in frame.seriesIndex == index }.map(\.frame))) }
        names = layout.frames.map(\.name)
        numbers = layout.frames.compactMap(\.number)
        dataLines = layout.frames.flatMap(\.dataLines)
        cardsScenePath = Self.roundedRectangles(layout.cards.map(\.frame))
        cardHeadings = layout.cards.map(\.heading)
        cardLines = layout.cards.flatMap(\.lines)
        title = layout.title
        runsDown = layout.runsDown
    }

    private static func roundedRectangles(_ frames: [CGRect]) -> DiagramScenePath {
        var path = DiagramScenePath()
        for frame in frames { path.addRoundedRect(in: frame, cornerWidth: cornerRadius, cornerHeight: cornerRadius) }
        return path
    }
}

extension DiagramScene {
    /// The event model's painting, in Pele's order and colors.
    public init(layout: EventModelLayout) {
        var builder = DiagramSceneBuilder()
        EventModelDrawingParts(layout: layout).addScene(to: &builder)
        self = builder.scene(size: layout.size, font: layout.font)
    }
}

extension EventModelDrawingParts {
    func addScene(to builder: inout DiagramSceneBuilder) {
        let line = DiagramStroke(lineWidth: 1)
        builder.title(title)
        builder.fill(laneBandsScenePath, .surface, part: .cluster)
        if !runsDown { builder.texts(laneNames, .muted, isBold: true, part: .clusterLabel) }
        builder.stroke(relationLinesScenePath, .line, line, part: .edge)
        builder.fill(arrowsScenePath, .line, part: .marker)
        if runsDown { builder.texts(laneNames, .muted, isBold: true, part: .clusterLabel) }
        builder.fillAndStroke(outlinedBoxesScenePath, fill: .background, stroke: .border, line, part: .node)
        builder.fill(plainBoxesScenePath, .background, part: .node)
        for (seriesIndex, boxes) in seriesBoxesScenePaths {
            builder.fillAndStroke(boxes, fill: DiagramPaint.series(seriesIndex).atOpacity(Self.seriesFillOpacity), stroke: .series(seriesIndex), line, part: .node)
        }
        builder.texts(names, .foreground, isBold: true, part: .label)
        builder.texts(numbers, .muted, part: .label)
        builder.texts(dataLines, .foreground, isMonospaced: true, part: .label)
        builder.fillAndStroke(cardsScenePath, fill: .background, stroke: .border, line, part: .note)
        builder.texts(cardHeadings, .foreground, isBold: true, part: .note)
        builder.texts(cardLines, .foreground, part: .note)
    }
}

/// Draws a laid-out event model into a Core Graphics context whose origin is the layout's top left and whose y runs
/// down, by painting its scene with `DiagramSceneRenderer`.
public enum EventModelRenderer {
    public static func draw(_ layout: EventModelLayout, in context: CGContext, palette: DiagramPalette) {
        DiagramSceneRenderer.draw(DiagramScene(layout: layout), in: context, palette: palette)
    }
}
