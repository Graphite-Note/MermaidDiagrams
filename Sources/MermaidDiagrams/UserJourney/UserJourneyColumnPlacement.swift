/**
 * File: UserJourneyColumnPlacement.swift
 * --------------------------------------
 * Layer: Core
 * Description: Lays a user journey out as a column of cards, as Pele's vertical journey does.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// Pele's spacing of a user journey's column, in points.
enum UserJourneyColumnGeometry {
    /// The container's width when it has none measured, before the padding, and the narrowest room the cards have.
    static let unmeasuredWidth: CGFloat = 320
    static let narrowestRoom: CGFloat = 140
    /// The text's width is the room less this, which the face keeps; an actor's name has the room less its dot and gutter.
    static let faceGutter: CGFloat = 72
    static let actorGutter: CGFloat = 44
    /// A heading has the room less this, and starts this far in and this far above the card below it.
    static let headingGutter: CGFloat = 16
    static let headingIndent: CGFloat = 8
    static let headingGap: CGFloat = 8
    /// A card's text is at least this tall, an actor's row at least this tall with this gap below it.
    static let tallestEmptyText: CGFloat = 42
    static let actorRowHeight: CGFloat = 16
    static let actorRowGap: CGFloat = 4
    /// The line between two cards.
    static let connectorLength: CGFloat = 16
    /// The face's center from the card's right edge; an actor's dot and name from its left.
    static let faceInset: CGFloat = 28
    static let actorDotInset: CGFloat = 16
    static let actorTextInset: CGFloat = 28
}

/// Lays a user journey out as a column (Pele's `verticalJourney`): a room as wide as the container less the padding (at
/// least 140 points, 320 less the padding for a container of no width), the title bold at the top, a bold heading where
/// the section changes, and a card per task as wide as the room (wider for a long word), 72 points of it kept clear of the
/// text on the right for the face and score, with a row of 16 points at least per actor, 16 points between cards.
struct UserJourneyColumnPlacement<Measurer: DiagramTextMeasuring> {
    let diagram: UserJourneyDiagram
    let taskText: Measurer
    let titleText: Measurer
    let font: DiagramFont
    let availableWidth: CGFloat?

    func layout() -> UserJourneyColumnLayout {
        let padding = UserJourneyLayoutEngine.padding
        let room = self.room
        var title = fittedTitle(room: room)
        let actorIndices = Dictionary(uniqueKeysWithValues: diagram.actorNames.enumerated().map { index, name in (name, index) })
        var y = padding + (title.map { title in title.size.height + UserJourneyLayoutEngine.titleGap } ?? 0)
        var width = title?.size.width ?? 0
        var headings: [DiagramTextBlock] = []
        var steps: [UserJourneyColumnStep] = []
        var connectors: [DiagramPath] = []
        var previousHeading: DiagramLabel?
        var isFirstTask = true
        for (index, task) in diagram.tasks.enumerated() {
            let heading = task.sectionIndex.map { sectionIndex in diagram.sections[sectionIndex] }
            if isFirstTask || heading != previousHeading {
                isFirstTask = false
                previousHeading = heading
                if let head = placedHeading(heading, top: y, room: room) {
                    headings.append(head)
                    width = max(width, head.size.width + UserJourneyColumnGeometry.headingGutter)
                    y += head.size.height + UserJourneyColumnGeometry.headingGap
                }
            }
            let step = card(for: task, top: y, room: room, actorIndices: actorIndices)
            steps.append(step)
            let frame = step.frame
            y += frame.height
            if index + 1 < diagram.tasks.count {
                connectors.append(DiagramPath(start: CGPoint(x: frame.midX, y: y), segments: [.line(to: CGPoint(x: frame.midX, y: y + UserJourneyColumnGeometry.connectorLength))]))
            }
            y += UserJourneyColumnGeometry.connectorLength
            width = max(width, frame.width)
        }
        let pageWidth = (width + 2 * padding).rounded(.up)
        let bottom = max(padding + (title?.size.height ?? 0), y - (diagram.tasks.isEmpty ? 0 : UserJourneyColumnGeometry.connectorLength))
        let titleHeight = title?.size.height ?? 0
        title?.center = CGPoint(x: pageWidth / 2, y: padding + titleHeight / 2)
        return UserJourneyColumnLayout(size: CGSize(width: pageWidth, height: (bottom + padding).rounded(.up)), font: font, headings: headings, steps: steps,
                                       connectors: connectors, title: title)
    }

    /// The width of the column's cards: the container's less the padding, but at least 140 points.
    private var room: CGFloat {
        max(UserJourneyColumnGeometry.narrowestRoom,
            (DiagramWidthFitting.limit(availableWidth) ?? UserJourneyColumnGeometry.unmeasuredWidth) - 2 * UserJourneyLayoutEngine.padding)
    }

    /// The title, bold and fitted to the room; nil without one.
    private func fittedTitle(room: CGFloat) -> DiagramTextBlock? {
        diagram.title.map { title in
            TimelineTextFitting.fitted(DiagramLabelDecoder.label(from: title, form: .literal), measurer: titleText, maximumWidth: room)
        }.flatMap { block in block.lines.isEmpty ? nil : block }
    }

    /// A section's heading, bold and fitted to the room, started a little in from the cards' left edge with its top at `top`; nil
    /// for a task before any section and for a section with no text.
    private func placedHeading(_ heading: DiagramLabel?, top: CGFloat, room: CGFloat) -> DiagramTextBlock? {
        guard let heading else { return nil }
        var block = TimelineTextFitting.fitted(heading, measurer: titleText, maximumWidth: room - UserJourneyColumnGeometry.headingGutter)
        guard !block.lines.isEmpty else { return nil }
        block.center = CGPoint(x: UserJourneyLayoutEngine.padding + UserJourneyColumnGeometry.headingIndent + block.size.width / 2,
                               y: top + block.size.height / 2)
        return block
    }

    /// The task's card with its top at `top`: as wide as `room`, or as its text and the face's gutter need; as tall as its text
    /// (at least 42 points), its actors' rows and the padding.
    private func card(for task: UserJourneyTask, top: CGFloat, room: CGFloat, actorIndices: [String: Int]) -> UserJourneyColumnStep {
        let cardPadding = UserJourneyGeometry.cardPadding
        let label = TimelineTextFitting.fitted(task.label, measurer: taskText, maximumWidth: room - UserJourneyColumnGeometry.faceGutter)
        let people = task.actors.filter { name in !name.isEmpty }.map { name in
            (name: name, text: TimelineTextFitting.fitted(DiagramLabel(name), measurer: taskText, maximumWidth: room - UserJourneyColumnGeometry.actorGutter))
        }
        let textHeight = max(label.size.height, UserJourneyColumnGeometry.tallestEmptyText)
        let height = 2 * cardPadding.height + textHeight + people.reduce(0) { sum, person in
            sum + max(UserJourneyColumnGeometry.actorRowHeight, person.text.size.height) + UserJourneyColumnGeometry.actorRowGap
        }
        let frame = CGRect(x: UserJourneyLayoutEngine.padding, y: top, width: max(room, label.size.width + UserJourneyColumnGeometry.faceGutter), height: height)
        return step(task, frame: frame, label: label, people: people, textHeight: textHeight, actorIndices: actorIndices)
    }

    private func step(_ task: UserJourneyTask, frame: CGRect, label: DiagramTextBlock, people: [(name: String, text: DiagramTextBlock)], textHeight: CGFloat,
                      actorIndices: [String: Int]) -> UserJourneyColumnStep {
        let cardPadding = UserJourneyGeometry.cardPadding
        let faceRadius = UserJourneyGeometry.faceRadius
        var text = label
        text.center = CGPoint(x: frame.minX + cardPadding.width + label.size.width / 2, y: frame.minY + cardPadding.height + label.size.height / 2)
        let faceCenter = CGPoint(x: frame.maxX - UserJourneyColumnGeometry.faceInset, y: frame.minY + cardPadding.height + faceRadius)
        var score: DiagramTextBlock?
        if task.score != nil {
            var block = DiagramTextBlock(label: DiagramLabel(JavaScriptNumberText.text(((task.level * 100).rounded()) / 100)), measurer: taskText,
                                         maximumWidth: XYChartScaleMarks.unwrappedWidth)
            // Written with its baseline a line of the text's size below the face.
            let baseline = frame.minY + cardPadding.height + 2 * faceRadius + taskText.fontSize
            block.center = CGPoint(x: faceCenter.x, y: baseline - taskText.fontSize * DiagramTextDrawing.baselineShiftRatio)
            score = block
        }
        var rowTop = frame.minY + cardPadding.height + textHeight + UserJourneyColumnGeometry.actorRowGap
        var actors: [UserJourneyColumnActor] = []
        for person in people {
            let rowHeight = max(UserJourneyColumnGeometry.actorRowHeight, person.text.size.height)
            let middle = rowTop + rowHeight / 2
            var name = person.text
            name.center = CGPoint(x: frame.minX + UserJourneyColumnGeometry.actorTextInset + name.size.width / 2, y: middle)
            let dot = UserJourneyActorDot(center: CGPoint(x: frame.minX + UserJourneyColumnGeometry.actorDotInset, y: middle), seriesIndex: actorIndices[person.name] ?? 0)
            actors.append(UserJourneyColumnActor(dot: dot, text: name))
            rowTop += rowHeight + UserJourneyColumnGeometry.actorRowGap
        }
        return UserJourneyColumnStep(frame: frame, text: text, faceCenter: faceCenter, mood: task.mood, score: score, actors: actors)
    }
}
