/**
 * File: ReferenceTimelineDiagram.swift
 * ------------------------------------
 * Layer: Tests
 * Description: 0.7.0's timeline Diagram, frozen as main ba176e5 kept it (labels and text blocks in lists), which the
 *              flat timeline is compared with.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */
import CoreGraphics
@testable import MermaidDiagrams


/// A Mermaid timeline (`timeline`) as its text describes it: time periods in the order they are written, each with
/// its events, grouped under the sections written before them.
struct ReferenceTimelineDiagram: Equatable, Sendable {
    /// The series colors its theme variables set, which its series are painted in over a palette's; none unless it
    /// sets them.
    var seriesColors = DiagramSeriesColors.none
    var direction: TimelineDirection
    /// `title …` in the diagram, else `title:` in the front matter, else nil.
    var title: String?
    /// The `section …` headings, in the order they are written.
    var sections: [DiagramLabel]
    var periods: [ReferenceTimelinePeriod]
    /// `accTitle: …`, the short name a screen reader gives the diagram, or nil.
    var accessibilityTitle: String?
    /// `accDescr: …` or `accDescr { … }`, the longer description a screen reader reads, or nil.
    var accessibilityDescription: String?

    init(direction: TimelineDirection = .leftToRight, title: String? = nil, sections: [DiagramLabel] = [], periods: [ReferenceTimelinePeriod] = [],
         accessibilityTitle: String? = nil, accessibilityDescription: String? = nil) {
        self.direction = direction
        self.title = title
        self.sections = sections
        self.periods = periods
        self.accessibilityTitle = accessibilityTitle
        self.accessibilityDescription = accessibilityDescription
    }
}

/// A time period of a timeline and the events that happened in it.
struct ReferenceTimelinePeriod: Equatable, Sendable {
    let label: DiagramLabel
    /// The events, in the order they are written: after the period on its line (`2004 : Facebook : Google`) and on
    /// the lines that follow it (`     : Google`).
    var events: [DiagramLabel]
    /// The index in `ReferenceTimelineDiagram.sections` of the section the period is written under, or nil for a period
    /// written before the first section.
    let sectionIndex: Int?

    init(label: DiagramLabel, events: [DiagramLabel] = [], sectionIndex: Int?) {
        self.label = label
        self.events = events
        self.sectionIndex = sectionIndex
    }
}

extension ReferenceTimelineDiagram {
    /// The timeline with its periods one below the other, or nil when it already runs down.
    var turnedToRunDown: ReferenceTimelineDiagram? {
        switch direction {
        case .leftToRight:
            var turned = self
            turned.direction = .topToBottom
            return turned
        case .topToBottom:
            return nil
        }
    }
}
