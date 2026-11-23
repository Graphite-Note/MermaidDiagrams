/**
 * File: TimelineMeasurement.swift
 * -------------------------------
 * Layer: Core
 * Description: A timeline's period and event texts measured and wrapped at Pele's column widths, which share a narrow
 *              container's width when the timeline runs down.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

import CoreGraphics

/// A timeline's text measured as Pele measures it: periods wrapped at a column 152 points wide, and events at the
/// same width across or 264 points running down; a word too wide widens the columns up to 216 points, past which it
/// is cut. Running down in a container of a known width, the two columns share what the container leaves (Pele's
/// `room`): the periods 38 % of it, 80 to 152 points, the events the rest, 110 to 264, and a word too wide is cut at
/// those widths.
struct TimelineMeasurement {
    /// The width of a period's text, and of an event's across.
    let textWidth: CGFloat
    /// The width of an event's text.
    let eventTextWidth: CGFloat
    let periodTexts: [DiagramTextBlock]
    /// Each period's events' text.
    let eventTexts: [[DiagramTextBlock]]

    static let narrowestTextWidth: CGFloat = 152
    static let widestTextWidth: CGFloat = 216
    /// The width of an event's text when the timeline runs down, beside its period.
    static let eventTextWidthDown: CGFloat = 264

    /// The narrowest a period's and an event's text are made in a narrow container.
    static let narrowestPeriodTextWidth: CGFloat = 80
    static let narrowestEventTextWidth: CGFloat = 110
    /// The share of a narrow container's room a period's text takes.
    static let periodShareOfRoom: CGFloat = 0.38

    /// `room`: the width a timeline running down has for its two columns and what is between them (Pele's `maxWidth`
    /// less the page's padding), infinity for none.
    init<Measurer: DiagramTextMeasuring>(diagram: TimelineDiagram, periodText: Measurer, eventText: Measurer, isDown: Bool, room: CGFloat = .infinity) {
        let taken = TimelineGeometry.axisGap + 2 * TimelineGeometry.spineGap + 4 * TimelineGeometry.boxPadding.width
        let periodTextWidth = room.isFinite
            ? min(Self.narrowestTextWidth, max(Self.narrowestPeriodTextWidth, ((room - taken) * Self.periodShareOfRoom).rounded(.toNearestOrAwayFromZero)))
            : Self.narrowestTextWidth
        let eventTextWidthDown = room.isFinite
            ? min(Self.eventTextWidthDown, max(Self.narrowestEventTextWidth, room - taken - periodTextWidth)) : Self.eventTextWidthDown
        var textWidth = periodTextWidth
        func eventWidth() -> CGFloat { isDown ? eventTextWidthDown : textWidth }
        var periodTexts = diagram.periods.map { period in TimelineTextFitting.wrapped(period.label, measurer: periodText, maximumWidth: textWidth) }
        var eventTexts = diagram.periods.map { period in
            period.events.map { event in TimelineTextFitting.wrapped(event, measurer: eventText, maximumWidth: eventWidth()) }
        }
        var widest = periodTexts.map(\.size.width).max() ?? 0
        if !isDown { widest = max(widest, eventTexts.joined().map(\.size.width).max() ?? 0) }
        let eventOverflows = isDown && eventTexts.joined().contains { text in text.size.width > eventTextWidthDown }
        if widest > textWidth || eventOverflows {
            textWidth = min(max(widest.rounded(.up), periodTextWidth), room.isFinite ? periodTextWidth : Self.widestTextWidth)
            periodTexts = diagram.periods.map { period in TimelineTextFitting.fitted(period.label, measurer: periodText, maximumWidth: textWidth) }
            eventTexts = diagram.periods.map { period in
                period.events.map { event in TimelineTextFitting.fitted(event, measurer: eventText, maximumWidth: eventWidth()) }
            }
        }
        self.textWidth = textWidth
        eventTextWidth = eventWidth()
        self.periodTexts = periodTexts
        self.eventTexts = eventTexts
    }
}
