/**
 * File: TimelineDiagram.swift
 * ---------------------------
 * Layer: Core
 * Description: A Mermaid timeline as its text describes it: periods, events and sections kept as ranges of its text's
 *              bytes, with the labels made from them when read, and the series colors its theme variables set.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.3
 * Date: 26/11/2026
 */

/// A Mermaid timeline (`timeline`) as its text describes it: time periods in the order they are written, each with
/// its events, grouped under the sections written before them. Its sections', periods' and events' texts are ranges of
/// the text it was read from (`TimelineText`); `sections` and `periods` make their labels when read.
public struct TimelineDiagram: Equatable, Sendable {
    /// The series colors its theme variables set, which its series are painted in over a palette's; none unless it
    /// sets them.
    public internal(set) var seriesColors = DiagramSeriesColors.none
    public internal(set) var direction: TimelineDirection = .leftToRight
    /// `title …` in the diagram, else `title:` in the front matter, else nil.
    public internal(set) var title: String?
    /// `accTitle: …`, the short name a screen reader gives the diagram, or nil.
    public internal(set) var accessibilityTitle: String?
    /// `accDescr: …` or `accDescr { … }`, the longer description a screen reader reads, or nil.
    public internal(set) var accessibilityDescription: String?
    /// The text the ranges index.
    let text: MermaidSourceText
    /// The `section …` headings' texts, in the order they are written.
    private(set) var sectionTexts: [TimelineText] = []
    /// The periods in the order they are written, each with its run of `eventTexts`.
    private(set) var periodRecords: [TimelinePeriodRecord] = []
    /// Every period's events, a period's after the period before it.
    private(set) var eventTexts: [TimelineText] = []

    init(text: MermaidSourceText) {
        self.text = text
    }

    /// The `section …` headings, in the order they are written.
    public var sections: [DiagramLabel] { sectionTexts.map(label) }

    public var periods: [TimelinePeriod] {
        periodRecords.map { record in
            TimelinePeriod(label: label(record.text), events: eventTexts[record.eventIndices].map(label),
                           sectionIndex: record.sectionIndex < 0 ? nil : Int(record.sectionIndex))
        }
    }

    /// The label of `text`, as the reader made it in 0.7.0: an ASCII text decoded from its bytes, any other from its
    /// String, both trimmed already.
    func label(_ text: TimelineText) -> DiagramLabel {
        self.text.withBytes { bytes in TimelineText.label(text, in: bytes) }
    }

    mutating func appendSection(_ section: TimelineText) {
        sectionTexts.append(section)
    }

    mutating func appendPeriod(_ period: TimelineText) {
        periodRecords.append(TimelinePeriodRecord(text: period, firstEvent: Int32(eventTexts.count), eventCount: 0,
                                                  sectionIndex: Int32(sectionTexts.count) - 1))
    }

    /// An event of the period appended last, which the caller made sure of.
    mutating func appendEvent(_ event: TimelineText) {
        eventTexts.append(event)
        periodRecords[periodRecords.count - 1].eventCount += 1
    }

    /// Equal when they draw and read the same: their labels, not where those lie in their texts.
    public static func == (left: TimelineDiagram, right: TimelineDiagram) -> Bool {
        left.seriesColors == right.seriesColors && left.direction == right.direction && left.title == right.title
            && left.accessibilityTitle == right.accessibilityTitle && left.accessibilityDescription == right.accessibilityDescription
            && left.sections == right.sections && left.periods == right.periods
    }
}

/// A period's text, its events as a run of `TimelineDiagram.eventTexts`, and the index of the section it is written
/// under (-1 before the first section).
struct TimelinePeriodRecord: Equatable, Sendable {
    var text: TimelineText
    var firstEvent: Int32
    var eventCount: Int32
    var sectionIndex: Int32

    var eventIndices: Range<Int> { Int(firstEvent)..<Int(firstEvent + eventCount) }
}

/// A time period of a timeline and the events that happened in it.
public struct TimelinePeriod: Equatable, Sendable {
    public let label: DiagramLabel
    /// The events, in the order they are written: after the period on its line (`2004 : Facebook : Google`) and on
    /// the lines that follow it (`     : Google`).
    public internal(set) var events: [DiagramLabel]
    /// The index in `TimelineDiagram.sections` of the section the period is written under, or nil for a period
    /// written before the first section.
    public let sectionIndex: Int?

    init(label: DiagramLabel, events: [DiagramLabel] = [], sectionIndex: Int?) {
        self.label = label
        self.events = events
        self.sectionIndex = sectionIndex
    }
}

/// The way a timeline runs.
public enum TimelineDirection: Equatable, Sendable, CaseIterable {
    /// `timeline` or `timeline LR`: periods side by side along an axis that runs right, their events below them.
    case leftToRight
    /// `timeline TD`: periods one below the other along an axis that runs down, their events beside them.
    case topToBottom
}
