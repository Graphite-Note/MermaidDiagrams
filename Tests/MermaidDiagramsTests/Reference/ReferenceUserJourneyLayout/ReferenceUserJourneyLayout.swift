/**
 * File: ReferenceUserJourneyLayout.swift
 * --------------------------------------
 * Layer: Tests
 * Description: 0.7.0's user journey layout, frozen as main ba176e5 kept it (text blocks, paths and lists in each
 *              placed task), which the flat user journey layout is compared with.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// A user journey laid out on a page whose origin is the top left corner and whose y runs down, in points: the
/// title, the section bands over their tasks' cards, the scale below the cards with a face per task at its score, the
/// line from face to face, and the legend of actors. Drawing it needs only colors.
struct ReferenceUserJourneyLayout: Equatable, Sendable {
    let size: CGSize
    /// The font the title was measured in, bold; the cards, bands and legend are in its size seven eighths, the
    /// scale's numbers three quarters.
    let font: DiagramFont
    /// A band over each run of tasks written one after the other under sections of one name.
    let sections: [UserJourneyLayoutSection]
    /// The tasks in the order they are written, left to right.
    let tasks: [UserJourneyLayoutTask]
    /// The scale's levels from 5 at the top to 1 at the bottom; none without tasks.
    let scaleLevels: [UserJourneyScaleLevel]
    /// The line from face to face, in the order the tasks are written; nil with fewer than two tasks.
    let scoreLine: DiagramPath?
    /// One entry per actor, in `UserJourneyDiagram.actorNames`'s order, centered below the scale in rows.
    let legend: [UserJourneyLegendEntry]
    /// The diagram's title above it, drawn bold, or nil.
    let title: DiagramTextBlock?
}
