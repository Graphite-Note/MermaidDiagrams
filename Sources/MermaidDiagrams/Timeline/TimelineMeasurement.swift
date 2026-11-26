/**
 * File: TimelineMeasurement.swift
 * -------------------------------
 * Layer: Core
 * Description: A timeline's period and event texts measured from its bytes and wrapped at Pele's column widths, which
 *              share a narrow container's width when the timeline runs down, into one list of lines.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.3
 * Date: 26/11/2026
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
    /// Each period's text, by period.
    let periodTexts: [DiagramMeasuredText]
    /// Each event's text, in `TimelineDiagram.eventTexts`'s order: a period's after the period before it.
    let eventTexts: [DiagramMeasuredText]
    /// The lines of the texts, over the timeline's text; the placement adds its sections' headings.
    var lines = DiagramMeasuredLines()

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
        let periodMeasurer = DiagramFlatMeasurer(periodText)
        let eventMeasurer = DiagramFlatMeasurer(eventText)
        var lines = DiagramMeasuredLines()
        lines.reserveCapacity(lines: diagram.periodRecords.count + diagram.eventTexts.count, derivedBytes: 0)
        var periodTexts: [DiagramMeasuredText] = []
        var eventTexts: [DiagramMeasuredText] = []
        diagram.text.withBytes { bytes in
            // Measured as 0.7.0 measured them, wrapped first, then fitted at the widened width when a word is too wide.
            Self.measureEvery(diagram, bytes, periodMeasurer, eventMeasurer, textWidth: textWidth, eventWidth: eventWidth(), cutsWideWords: false,
                              periodTexts: &periodTexts, eventTexts: &eventTexts, lines: &lines)
            var widest: CGFloat = 0
            var eventOverflows = false
            for text in periodTexts where widest < text.width { widest = text.width }
            for text in eventTexts {
                if !isDown, widest < text.width { widest = text.width }
                if isDown, text.width > eventTextWidthDown { eventOverflows = true }
            }
            guard widest > textWidth || eventOverflows else { return }
            textWidth = min(max(widest.rounded(.up), periodTextWidth), room.isFinite ? periodTextWidth : Self.widestTextWidth)
            lines.removeAll()
            Self.measureEvery(diagram, bytes, periodMeasurer, eventMeasurer, textWidth: textWidth, eventWidth: eventWidth(), cutsWideWords: true,
                              periodTexts: &periodTexts, eventTexts: &eventTexts, lines: &lines)
        }
        self.textWidth = textWidth
        eventTextWidth = eventWidth()
        self.periodTexts = periodTexts
        self.eventTexts = eventTexts
        self.lines = lines
    }

    /// Every period's text at `textWidth` and every event's at `eventWidth`, wrapped, or fitted when `cutsWideWords`.
    private static func measureEvery<Measurer>(_ diagram: TimelineDiagram, _ bytes: UnsafeBufferPointer<UInt8>, _ periodMeasurer: DiagramFlatMeasurer<Measurer>,
                                               _ eventMeasurer: DiagramFlatMeasurer<Measurer>, textWidth: CGFloat, eventWidth: CGFloat, cutsWideWords: Bool,
                                               periodTexts: inout [DiagramMeasuredText], eventTexts: inout [DiagramMeasuredText],
                                               lines: inout DiagramMeasuredLines) {
        periodTexts = diagram.periodRecords.map { period in
            TimelineText.measured(period.text, in: bytes, measurer: periodMeasurer, maximumWidth: textWidth, cutsWideWords: cutsWideWords, into: &lines)
        }
        eventTexts = diagram.eventTexts.map { event in
            TimelineText.measured(event, in: bytes, measurer: eventMeasurer, maximumWidth: eventWidth, cutsWideWords: cutsWideWords, into: &lines)
        }
    }
}
