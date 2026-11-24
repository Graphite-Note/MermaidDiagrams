/**
 * File: UserJourneyDrawingParts.swift
 * -----------------------------------
 * Layer: Core
 * Description: A laid-out user journey's geometry grouped by how it is painted: scale, stems, score line, faces,
 *              bands, cards and dots.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import CoreGraphics

/// A laid-out user journey's geometry grouped by how it is painted, so that drawing it in any colors is a few fills
/// and strokes, by Core Graphics (`UserJourneyRenderer`) or by a view's own shapes. Back to front, as Pele draws: the
/// scale, the stems, the line from face to face, the faces, the bands, the cards with their text and dots, the
/// legend, the title.
public struct UserJourneyDrawingParts {
    /// The scale's lines, stroked `lineWidth` wide in the second surface.
    public var scaleLines: CGPath { scaleLinesScenePath.coreGraphicsPath }
    let scaleLinesScenePath: DiagramScenePath
    /// The dashed stems from the cards to the faces, stroked `lineWidth` wide in the border color, `stemDashLengths`.
    public var stems: CGPath { stemsScenePath.coreGraphicsPath }
    let stemsScenePath: DiagramScenePath
    /// The line from face to face, stroked `lineWidth` wide in the line color with round joins; empty for one task.
    public var scoreLine: CGPath { scoreLineScenePath.coreGraphicsPath }
    let scoreLineScenePath: DiagramScenePath
    /// The faces' circles, filled in the background color and stroked `lineWidth` wide in the line color.
    public var faces: CGPath { facesScenePath.coreGraphicsPath }
    let facesScenePath: DiagramScenePath
    /// The faces' eyes, filled in the line color.
    public var eyes: CGPath { eyesScenePath.coreGraphicsPath }
    let eyesScenePath: DiagramScenePath
    /// The faces' mouths, stroked `lineWidth` wide in the line color with round caps.
    public var mouths: CGPath { mouthsScenePath.coreGraphicsPath }
    let mouthsScenePath: DiagramScenePath
    /// The sections' bands, filled in the second surface.
    public var sectionBands: CGPath { sectionBandsScenePath.coreGraphicsPath }
    let sectionBandsScenePath: DiagramScenePath
    /// The cards, filled in the surface color and stroked `lineWidth` wide in the border color.
    public var cards: CGPath { cardsScenePath.coreGraphicsPath }
    let cardsScenePath: DiagramScenePath
    /// For each series color, the actors' dots on the cards in it: entry `k` is filled in
    /// `DiagramPalette.seriesColor(at: k)` and stroked `lineWidth` wide in the surface color, and holds the dots of the
    /// actors whose index leaves `k` when divided by the number of series colors.
    public var cardDotsBySeries: [CGPath] { cardDotsBySeriesScenePaths.map(\.coreGraphicsPath) }
    let cardDotsBySeriesScenePaths: [DiagramScenePath]
    /// For each series color, the legend's dots in it, filled only.
    public var legendDotsBySeries: [CGPath] { legendDotsBySeriesScenePaths.map(\.coreGraphicsPath) }
    let legendDotsBySeriesScenePaths: [DiagramScenePath]
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
        var faces = DiagramScenePath()
        var eyes = DiagramScenePath()
        var mouths = DiagramScenePath()
        var stems = DiagramScenePath()
        var cards = DiagramScenePath()
        let actorCount = layout.legend.count
        var cardDots = (0..<min(actorCount, Self.seriesColorCount)).map { _ in DiagramScenePath() }
        for task in layout.tasks {
            UserJourneyFaceShape.add(task.mood, at: task.faceCenter, circles: &faces, eyes: &eyes, mouths: &mouths)
            stems.addEdgePath(task.stem)
            cards.addPath(Self.roundedRectangle(task.frame))
            for dot in task.actorDots { Self.add(dot, to: &cardDots) }
        }
        var legendDots = (0..<min(actorCount, Self.seriesColorCount)).map { _ in DiagramScenePath() }
        for entry in layout.legend { Self.add(entry.dot, to: &legendDots) }
        var scaleLines = DiagramScenePath()
        for level in layout.scaleLevels { scaleLines.addEdgePath(level.line) }
        var bands = DiagramScenePath()
        for section in layout.sections { bands.addPath(Self.roundedRectangle(section.frame)) }
        self.scaleLinesScenePath = scaleLines
        self.stemsScenePath = stems
        scoreLineScenePath = layout.scoreLine.map(DiagramEdgeDrawing.path) ?? DiagramScenePath()
        self.facesScenePath = faces
        self.eyesScenePath = eyes
        self.mouthsScenePath = mouths
        sectionBandsScenePath = bands
        self.cardsScenePath = cards
        cardDotsBySeriesScenePaths = cardDots
        legendDotsBySeriesScenePaths = legendDots
        scaleTexts = layout.scaleLevels.map(\.text)
        sectionTexts = layout.sections.map(\.text)
        taskTexts = layout.tasks.map(\.text)
        legendTexts = layout.legend.map(\.text)
        title = layout.title
    }

    private static func add(_ dot: UserJourneyActorDot, to dotsBySeries: inout [DiagramScenePath]) {
        let radius = UserJourneyGeometry.dotRadius
        dotsBySeries[dot.seriesIndex % seriesColorCount].addEllipse(in: CGRect(x: dot.center.x - radius, y: dot.center.y - radius,
                                                                               width: 2 * radius, height: 2 * radius))
    }

    private static func roundedRectangle(_ frame: CGRect) -> DiagramScenePath {
        DiagramScenePath(roundedRect: frame, cornerWidth: cornerRadius, cornerHeight: cornerRadius)
    }
}
