/**
 * File: UserJourneyColumnLayout.swift
 * -----------------------------------
 * Layer: Core
 * Description: A user journey laid out as a column of cards, for a container too narrow for the cards side by side.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// A user journey turned to run down, as Pele turns it for a column under 640 points that its cards side by side do not
/// fit: the title, then each section's heading, then a card per task, one below the other with a short line between
/// them, each with the task's text, its face and score at the right, and a row per actor. There is no scale, line through
/// the faces or legend. Its origin is the top left corner and its y runs down, in points. Drawing it needs only colors.
public struct UserJourneyColumnLayout: Equatable, Sendable {
    public let size: CGSize
    /// The font the title was measured in, bold; the headings are bold in the same size, the cards' text, scores and
    /// actors' names seven eighths of it.
    public let font: DiagramFont
    /// The sections' headings, bold, each above the first card of its run of tasks; a section with no tasks has none.
    public let headings: [DiagramTextBlock]
    /// The tasks in the order they are written, top to bottom.
    public let steps: [UserJourneyColumnStep]
    /// The short line from the bottom of a card to the top of the next one, centered on the card: one fewer than the steps.
    public let connectors: [DiagramPath]
    /// The diagram's title above it, drawn bold, or nil.
    public let title: DiagramTextBlock?
}

/// A task's card in a column: its text at the top left, its face at the top right with its score below, and a row per actor.
public struct UserJourneyColumnStep: Equatable, Sendable {
    /// The card, filled in the surface color and outlined in the border color.
    public let frame: CGRect
    public let text: DiagramTextBlock
    /// The center of the face and its mood.
    public let faceCenter: CGPoint
    public let mood: UserJourneyMood
    /// The score kept within the scale, under the face; nil for a task without a score.
    public let score: DiagramTextBlock?
    /// The actors named on the task, a row each below its text, in the order they are written.
    public let actors: [UserJourneyColumnActor]
}

/// An actor's row on a card: its dot in its series color and its name beside it.
public struct UserJourneyColumnActor: Equatable, Sendable {
    public let dot: UserJourneyActorDot
    public let text: DiagramTextBlock
}
