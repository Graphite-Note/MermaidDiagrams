/**
 * File: UserJourneyLayout.swift
 * -----------------------------
 * Layer: Core
 * Description: A laid-out user journey: its tasks as flat records with their dots in one list, its scale as its numbers
 *              and where its lines run, and its public parts made from them when read.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.2
 * Date: 26/11/2026
 */

import CoreGraphics

/// A user journey laid out on a page whose origin is the top left corner and whose y runs down, in points: the
/// title, the section bands over their tasks' cards, the scale below the cards with a face per task at its score, the
/// line from face to face, and the legend of actors. Drawing it needs only colors.
public struct UserJourneyLayout: Equatable, Sendable {
    public let size: CGSize
    /// The font the title was measured in, bold; the cards, bands and legend are in its size seven eighths, the
    /// scale's numbers three quarters.
    public let font: DiagramFont
    /// A band over each run of tasks written one after the other under sections of one name.
    public let sections: [UserJourneyLayoutSection]
    /// One entry per actor, in `UserJourneyDiagram.actorNames`'s order, centered below the scale in rows.
    public let legend: [UserJourneyLegendEntry]
    /// The diagram's title above it, drawn bold, or nil.
    public let title: DiagramTextBlock?
    /// The tasks as flat records, their actors' dots runs of `dots`, which the scene reads where they lie.
    let placedTasks: [UserJourneyPlacedTask]
    let dots: [UserJourneyActorDot]
    /// The scale's numbers, from 5 at the top, and where its lines run; no numbers without tasks.
    let scale: UserJourneyPlacedScale

    init(size: CGSize, font: DiagramFont, body: UserJourneyPlacedBody, legend: [UserJourneyLegendEntry], title: DiagramTextBlock?) {
        self.size = size
        self.font = font
        sections = body.sections
        self.legend = legend
        self.title = title
        placedTasks = body.tasks
        dots = body.dots
        scale = body.scale
    }

    /// The tasks in the order they are written, left to right, made from the records when read.
    public var tasks: [UserJourneyLayoutTask] {
        placedTasks.map { task in
            UserJourneyLayoutTask(frame: task.frame, text: task.text, faceCenter: task.faceCenter, mood: task.mood,
                                  stem: DiagramPath(start: task.stemTop, segments: [.line(to: task.stemBottom)]), actorDots: Array(dots[task.dotIndices]))
        }
    }

    /// The scale's levels from 5 at the top to 1 at the bottom; none without tasks.
    public var scaleLevels: [UserJourneyScaleLevel] {
        scale.texts.indices.map { index in
            let y = scale.lineY(at: index)
            return UserJourneyScaleLevel(score: UserJourneyGeometry.levels[index],
                                         line: DiagramPath(start: CGPoint(x: scale.lineStart, y: y), segments: [.line(to: CGPoint(x: scale.lineEnd, y: y))]),
                                         text: scale.texts[index])
        }
    }

    /// The line from face to face, in the order the tasks are written; nil with fewer than two tasks.
    public var scoreLine: DiagramPath? {
        guard placedTasks.count > 1, let first = placedTasks.first else { return nil }
        return DiagramPath(start: first.faceCenter, segments: placedTasks.dropFirst().map { task in .line(to: task.faceCenter) })
    }

    /// Equal when they draw the same: their parts, not how the tasks are kept.
    public static func == (left: UserJourneyLayout, right: UserJourneyLayout) -> Bool {
        left.size == right.size && left.font == right.font && left.sections == right.sections && left.legend == right.legend
            && left.title == right.title && left.placedTasks == right.placedTasks && left.dots == right.dots && left.scale == right.scale
    }
}

/// A placed task: its card with its text, its face on the scale with the dashed stem from the card's bottom down to the
/// face's top, and its actors' dots as a run of `UserJourneyLayout.dots`.
struct UserJourneyPlacedTask: Equatable, Sendable {
    var frame: CGRect
    var text: DiagramTextBlock
    var faceCenter: CGPoint
    var mood: UserJourneyMood
    var firstDot: Int32
    var dotCount: Int32

    var dotIndices: Range<Int> { Int(firstDot)..<Int(firstDot + dotCount) }
    var stemTop: CGPoint { CGPoint(x: frame.midX, y: frame.maxY) }
    var stemBottom: CGPoint { CGPoint(x: frame.midX, y: faceCenter.y - UserJourneyGeometry.faceRadius) }
}

/// The scale: a line at each level from `lineStart` to `lineEnd`, the levels `UserJourneyGeometry.levelSpacing` apart from
/// the highest at `chartTop`'s offset, and each level's number.
struct UserJourneyPlacedScale: Equatable, Sendable {
    var texts: [DiagramTextBlock] = []
    var lineStart: CGFloat = 0
    var lineEnd: CGFloat = 0
    var chartTop: CGFloat = 0

    /// The y of the line of the level at `index` of `UserJourneyGeometry.levels`.
    func lineY(at index: Int) -> CGFloat {
        chartTop + UserJourneyGeometry.offset(ofLevel: Double(UserJourneyGeometry.levels[index]))
    }
}

/// The band over a run of tasks under one section, filled in the second surface, with its heading drawn bold.
public struct UserJourneyLayoutSection: Equatable, Sendable {
    public let frame: CGRect
    public let text: DiagramTextBlock
}

/// A task: its card with its text and its actors' dots, and its face on the scale with the dashed stem down to it.
public struct UserJourneyLayoutTask: Equatable, Sendable {
    /// The card, filled in the surface color and outlined in the border color.
    public let frame: CGRect
    public let text: DiagramTextBlock
    /// The center of the face, at the task's level on the scale.
    public let faceCenter: CGPoint
    public let mood: UserJourneyMood
    /// The dashed line from the card's bottom to the top of the face.
    public let stem: DiagramPath
    /// The dots of the actors named on the task, in the order they are written, along the card's bottom.
    public let actorDots: [UserJourneyActorDot]
}

/// An actor's dot, on a task's card or in the legend.
public struct UserJourneyActorDot: Equatable, Sendable {
    public let center: CGPoint
    /// The actor's place in `UserJourneyDiagram.actorNames`, which picks its series color.
    public let seriesIndex: Int
}

/// A level of the scale: the line across the chart at it and its number at the left.
public struct UserJourneyScaleLevel: Equatable, Sendable {
    public let score: Int
    public let line: DiagramPath
    public let text: DiagramTextBlock
}

/// A row of the legend: an actor's dot in its series color, then its name.
public struct UserJourneyLegendEntry: Equatable, Sendable {
    public let dot: UserJourneyActorDot
    public let text: DiagramTextBlock
}
