/**
 * File: ReferenceTimelineLayout.swift
 * -----------------------------------
 * Layer: Tests
 * Description: 0.7.0's timeline Layout, frozen as main ba176e5 kept it (labels and text blocks in lists), which the
 *              flat timeline is compared with.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// A timeline laid out on a page whose origin is the top left corner and whose y runs down, in points. Drawing it
/// needs only colors: every position, path and text measurement is here.
struct ReferenceTimelineLayout: Equatable, Sendable {
    /// The series colors the diagram's theme variables set, which its scene carries.
    var seriesColors = DiagramSeriesColors.none
    let size: CGSize
    /// The font the periods' and sections' text was measured in; events' text is in the same font at its own size.
    let font: DiagramFont
    let direction: TimelineDirection
    /// The section headings, each over or before the periods written under it.
    let sections: [ReferenceTimelineLayoutSection]
    /// The periods in the order they are written.
    let periods: [ReferenceTimelineLayoutPeriod]
    /// The axis the periods hang from, which stops where its arrow begins, and the arrow; nil without periods.
    let axis: DiagramPath?
    let axisArrow: DiagramEdgeMark?
    /// The diagram's title above it, or nil.
    let title: DiagramTextBlock?
}

/// A section heading: a box in its section's series color with its text, drawn bold in the background color.
struct ReferenceTimelineLayoutSection: Equatable, Sendable {
    let sectionIndex: Int
    let frame: CGRect
    let text: DiagramTextBlock
}

/// A period: its box, in its color, with its text in the background color; its dot on the axis; the lines from it to
/// the axis and on to its events; and its events' boxes, tinted in its color, with their text.
struct ReferenceTimelineLayoutPeriod: Equatable, Sendable {
    let color: TimelineColor
    let frame: CGRect
    let text: DiagramTextBlock
    /// The center of the dot where the period meets the axis.
    let dot: CGPoint
    let connectors: [DiagramPath]
    let events: [ReferenceTimelineLayoutEvent]
}

struct ReferenceTimelineLayoutEvent: Equatable, Sendable {
    let frame: CGRect
    let text: DiagramTextBlock
}
