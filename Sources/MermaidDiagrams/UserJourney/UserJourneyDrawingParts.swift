/**
 * File: UserJourneyDrawingParts.swift
 * -----------------------------------
 * Layer: Core
 * Description: A laid-out user journey's geometry grouped by how it is painted, and its paths recorded into Core
 *              Graphics paths or into lanes of the thread's scene workspace.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics

/// A laid-out user journey's geometry grouped by how it is painted, so that drawing it in any colors is a few fills
/// and strokes, by Core Graphics (`UserJourneyRenderer`) or by a view's own shapes. Back to front, as Pele draws: the
/// scale, the stems, the line from face to face, the faces, the bands, the cards with their text and dots, the
/// legend, the title.
public struct UserJourneyDrawingParts {
    /// The scale's lines, stroked `lineWidth` wide in the second surface.
    public let scaleLines: CGPath
    /// The dashed stems from the cards to the faces, stroked `lineWidth` wide in the border color, `stemDashLengths`.
    public let stems: CGPath
    /// The line from face to face, stroked `lineWidth` wide in the line color with round joins; empty for one task.
    public let scoreLine: CGPath
    /// The faces' circles, filled in the background color and stroked `lineWidth` wide in the line color.
    public let faces: CGPath
    /// The faces' eyes, filled in the line color.
    public let eyes: CGPath
    /// The faces' mouths, stroked `lineWidth` wide in the line color with round caps.
    public let mouths: CGPath
    /// The sections' bands, filled in the second surface.
    public let sectionBands: CGPath
    /// The cards, filled in the surface color and stroked `lineWidth` wide in the border color.
    public let cards: CGPath
    /// For each series color, the actors' dots on the cards in it: entry `k` is filled in
    /// `DiagramPalette.seriesColor(at: k)` and stroked `lineWidth` wide in the surface color, and holds the dots of the
    /// actors whose index leaves `k` when divided by the number of series colors.
    public let cardDotsBySeries: [CGPath]
    /// For each series color, the legend's dots in it, filled only.
    public let legendDotsBySeries: [CGPath]
    /// The scale's numbers, in the muted color.
    public let scaleTexts: [DiagramTextBlock]
    /// The bands' headings, drawn bold in the foreground color.
    public let sectionTexts: [DiagramTextBlock]
    /// The cards' text and the legend's names, in the foreground color.
    public let taskTexts: [DiagramTextBlock]
    public let legendTexts: [DiagramTextBlock]
    /// The title, drawn bold, or nil.
    public let title: DiagramTextBlock?

    public static let lineWidth: CGFloat = 1
    /// Pele's `2 3`: two points drawn, three left.
    public static let stemDashLengths: [CGFloat] = [2, 3]
    /// Pele's eight `--pele-series-*` colors, which the actors take in turn.
    public static let seriesColorCount = DiagramPalette.peleSeries.count
    /// The corner radius of the cards and bands: Pele's `--pele-radius`.
    static let cornerRadius: CGFloat = 4

    public init(layout: UserJourneyLayout) {
        let paths = UserJourneyDrawingPaths(layout: layout, making: DiagramCoreGraphicsPaths())
        scaleLines = paths.scaleLines.path
        stems = paths.stems.path
        scoreLine = paths.scoreLine.path
        faces = paths.faces.path
        eyes = paths.eyes.path
        mouths = paths.mouths.path
        sectionBands = paths.sectionBands.path
        cards = paths.cards.path
        cardDotsBySeries = paths.cardDotsBySeries.map(\.path)
        legendDotsBySeries = paths.legendDotsBySeries.map(\.path)
        scaleTexts = layout.scaleLevels.map(\.text)
        sectionTexts = layout.sections.map(\.text)
        taskTexts = layout.tasks.map(\.text)
        legendTexts = layout.legend.map(\.text)
        title = layout.title
    }
}

/// A user journey's paths, grouped as `UserJourneyDrawingParts` groups them, recorded into the paths a maker makes:
/// Core Graphics paths for the drawing parts, lanes of the thread's scene workspace for the scene, the same elements.
struct UserJourneyDrawingPaths<Path: DiagramCurvedPathRecording> {
    let scaleLines: Path
    let stems: Path
    let scoreLine: Path
    let faces: Path
    let eyes: Path
    let mouths: Path
    let sectionBands: Path
    let cards: Path
    let cardDotsBySeries: [Path]
    let legendDotsBySeries: [Path]

    init<Maker: DiagramPathMaking>(layout: UserJourneyLayout, making maker: Maker) where Maker.Path == Path {
        faces = maker.makePath()
        eyes = maker.makePath()
        mouths = maker.makePath()
        stems = maker.makePath()
        cards = maker.makePath()
        let seriesCount = UserJourneyDrawingParts.seriesColorCount
        let usedSeriesCount = min(layout.legend.count, seriesCount)
        cardDotsBySeries = (0..<usedSeriesCount).map { _ in maker.makePath() }
        legendDotsBySeries = (0..<usedSeriesCount).map { _ in maker.makePath() }
        let radius = UserJourneyDrawingParts.cornerRadius
        for task in layout.tasks {
            UserJourneyFaceShape.add(task.mood, at: task.faceCenter, circles: faces, eyes: eyes, mouths: mouths)
            maker.addEdgeLine(task.stem, to: stems)
            maker.addMadeRoundedRectangle(task.frame, cornerWidth: radius, cornerHeight: radius, to: cards)
            for dot in task.actorDots { Self.add(dot, to: cardDotsBySeries) }
        }
        for entry in layout.legend { Self.add(entry.dot, to: legendDotsBySeries) }
        scaleLines = maker.makePath()
        for level in layout.scaleLevels { maker.addEdgeLine(level.line, to: scaleLines) }
        sectionBands = maker.makePath()
        for section in layout.sections { maker.addMadeRoundedRectangle(section.frame, cornerWidth: radius, cornerHeight: radius, to: sectionBands) }
        scoreLine = maker.makePath()
        if let line = layout.scoreLine { DiagramEdgeDrawing.record(line, into: scoreLine) }
    }

    /// An actor's dot, in the paths of its series color.
    static func add(_ dot: UserJourneyActorDot, to dotsBySeries: [Path]) {
        let radius = UserJourneyGeometry.dotRadius
        dotsBySeries[dot.seriesIndex % UserJourneyDrawingParts.seriesColorCount].addEllipse(
            in: CGRect(x: dot.center.x - radius, y: dot.center.y - radius, width: 2 * radius, height: 2 * radius))
    }
}
