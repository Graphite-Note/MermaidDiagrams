/**
 * File: TimelineLayout.swift
 * --------------------------
 * Layer: Core
 * Description: A laid-out timeline: its sections, periods, events and connectors as flat records whose texts are
 *              measured from the timeline's bytes, read by its scene where they lie, with its public parts made from
 *              them when read.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.3
 * Date: 26/11/2026
 */

import CoreGraphics

/// A timeline laid out on a page whose origin is the top left corner and whose y runs down, in points. Drawing it
/// needs only colors: every position, path and text measurement is here. Its sections, periods and events are kept
/// as flat records with their texts measured into one list of lines over the timeline's text (`lines`, `text`);
/// `sections` and `periods` make their text blocks and paths when read.
public struct TimelineLayout: Equatable, Sendable {
    /// The series colors the diagram's theme variables set, which its scene carries.
    public internal(set) var seriesColors = DiagramSeriesColors.none
    public let size: CGSize
    /// The font the periods' and sections' text was measured in; events' text is in the same font at its own size.
    public let font: DiagramFont
    public let direction: TimelineDirection
    /// The axis the periods hang from, which stops where its arrow begins, and the arrow; nil without periods.
    public let axis: DiagramPath?
    public let axisArrow: DiagramEdgeMark?
    /// The diagram's title above it, or nil.
    public let title: DiagramTextBlock?
    /// The text the measured lines' ranges index.
    let text: MermaidSourceText
    let lines: DiagramMeasuredLines
    let body: TimelinePlacedBody

    init(size: CGSize, font: DiagramFont, direction: TimelineDirection, body: TimelinePlacedBody, title: DiagramTextBlock?, text: MermaidSourceText,
         lines: DiagramMeasuredLines) {
        self.size = size
        self.font = font
        self.direction = direction
        axis = body.axis
        axisArrow = body.axisArrow
        self.title = title
        self.text = text
        self.lines = lines
        self.body = body
    }

    /// The section headings, each over or before the periods written under it.
    public var sections: [TimelineLayoutSection] {
        text.withBytes { source in
            body.sections.map { section in
                TimelineLayoutSection(sectionIndex: section.sectionIndex, frame: section.frame, text: DiagramTextBlock(section.text, of: lines, source: source))
            }
        }
    }

    /// The periods in the order they are written.
    public var periods: [TimelineLayoutPeriod] {
        text.withBytes { source in
            body.periods.map { period in
                let events = body.events[period.eventIndices].map { event in
                    TimelineLayoutEvent(frame: event.frame, text: DiagramTextBlock(event.text, of: lines, source: source))
                }
                let connectors = body.connectors[period.connectorIndices].map { connector in body.path(of: connector) }
                return TimelineLayoutPeriod(color: period.color, frame: period.frame, text: DiagramTextBlock(period.text, of: lines, source: source),
                                            dot: period.dot, connectors: connectors, events: events)
            }
        }
    }

    /// Equal when they draw the same: their parts, not how their texts' lines are kept.
    public static func == (left: TimelineLayout, right: TimelineLayout) -> Bool {
        left.seriesColors == right.seriesColors && left.size == right.size && left.font == right.font && left.direction == right.direction
            && left.axis == right.axis && left.axisArrow == right.axisArrow && left.title == right.title && left.sections == right.sections
            && left.periods == right.periods
    }
}

/// A section heading: a box in its section's series color with its text, drawn bold in the background color.
public struct TimelineLayoutSection: Equatable, Sendable {
    public let sectionIndex: Int
    public let frame: CGRect
    public let text: DiagramTextBlock
}

/// A period: its box, in its color, with its text in the background color; its dot on the axis; the lines from it to
/// the axis and on to its events; and its events' boxes, tinted in its color, with their text.
public struct TimelineLayoutPeriod: Equatable, Sendable {
    public let color: TimelineColor
    public let frame: CGRect
    public let text: DiagramTextBlock
    /// The center of the dot where the period meets the axis.
    public let dot: CGPoint
    public let connectors: [DiagramPath]
    public let events: [TimelineLayoutEvent]
}

public struct TimelineLayoutEvent: Equatable, Sendable {
    public let frame: CGRect
    public let text: DiagramTextBlock
}

/// The color a period takes, as Pele colors them: its section's series color; without sections, the series colors
/// in turn; a period before the first section of a timeline that has sections is muted.
public enum TimelineColor: Equatable, Sendable {
    case series(Int)
    case muted
}
