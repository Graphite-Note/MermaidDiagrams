/**
 * File: EventModelDrawingParts.swift
 * ----------------------------------
 * Layer: Core
 * Description: A laid-out event model's geometry grouped by how it is painted, its scene in Pele's colors and order, and
 *              its renderer.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// A laid-out event model's geometry grouped by how it is painted, back to front as Pele draws it: the lanes' bands in
/// the surface color and their names, the relations' lines and arrows, the frames' boxes (on the background, each
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
    /// Drawn in the system's monospaced font: the frames' numbers, in the muted color, and their data.
    public let numbers: [DiagramTextBlock]
    public let dataLines: [DiagramTextBlock]
    public let cards: CGPath
    public let cardHeadings: [DiagramTextBlock]
    public let cardLines: [DiagramTextBlock]
    public let title: DiagramTextBlock?

    /// Pele's `fill-opacity` for a kind's color over its box.
    public static let seriesFillOpacity: CGFloat = 0.22
    static let cornerRadius: CGFloat = 4

    public init(layout: EventModelLayout) {
        laneBands = Self.roundedRectangles(layout.laneBands)
        laneNames = layout.laneNames
        let lines = CGMutablePath()
        let arrows = CGMutablePath()
        let unused = CGMutablePath()
        for relation in layout.relations {
            lines.addPath(DiagramEdgeDrawing.path(relation.path))
            DiagramEdgeDrawing.addMark(relation.arrow, filled: arrows, stroked: unused)
        }
        relationLines = lines
        self.arrows = arrows
        outlinedBoxes = Self.roundedRectangles(layout.frames.filter { frame in frame.isOutlinedInBorder || frame.seriesIndex == nil }.map(\.frame))
        plainBoxes = Self.roundedRectangles(layout.frames.filter { frame in !frame.isOutlinedInBorder && frame.seriesIndex != nil }.map(\.frame))
        let seriesIndices = Set(layout.frames.compactMap(\.seriesIndex)).sorted()
        seriesBoxes = seriesIndices.map { index in (index, Self.roundedRectangles(layout.frames.filter { frame in frame.seriesIndex == index }.map(\.frame))) }
        names = layout.frames.map(\.name)
        numbers = layout.frames.compactMap(\.number)
        dataLines = layout.frames.flatMap(\.dataLines)
        cards = Self.roundedRectangles(layout.cards.map(\.frame))
        cardHeadings = layout.cards.map(\.heading)
        cardLines = layout.cards.flatMap(\.lines)
        title = layout.title
    }

    private static func roundedRectangles(_ frames: [CGRect]) -> CGPath {
        let path = CGMutablePath()
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
        builder.fill(laneBands, .surface, part: .cluster)
        builder.texts(laneNames, .muted, isBold: true, part: .clusterLabel)
        builder.stroke(relationLines, .line, line, part: .edge)
        builder.fill(arrows, .line, part: .marker)
        builder.fillAndStroke(outlinedBoxes, fill: .background, stroke: .border, line, part: .node)
        builder.fill(plainBoxes, .background, part: .node)
        for (seriesIndex, boxes) in seriesBoxes {
            builder.fillAndStroke(boxes, fill: DiagramPaint.series(seriesIndex).atOpacity(Self.seriesFillOpacity), stroke: .series(seriesIndex), line, part: .node)
        }
        builder.texts(names, .foreground, isBold: true, part: .label)
        builder.texts(numbers, .muted, isMonospaced: true, part: .label)
        builder.texts(dataLines, .foreground, isMonospaced: true, part: .label)
        builder.fillAndStroke(cards, fill: .background, stroke: .border, line, part: .note)
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
