/**
 * File: ReferenceTimelineDiagramBuilder.swift
 * -------------------------------------------
 * Layer: Tests
 * Description: 0.7.0's timeline DiagramBuilder, frozen as main ba176e5 kept it (labels and text blocks in lists), which the
 *              flat timeline is compared with.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams
/// Collects a timeline as its statements are read: each period under the section written last, each event on the
/// period written last, and every section, period and event counted against the node limit.
struct ReferenceTimelineDiagramBuilder {
    private(set) var diagram = ReferenceTimelineDiagram()
    private let limits: MermaidDiagramLimits
    private var itemCount = 0

    init(limits: MermaidDiagramLimits) {
        self.limits = limits
    }

    mutating func setDirection(_ direction: TimelineDirection) {
        diagram.direction = direction
    }

    /// A later `title` replaces an earlier one; an empty one leaves none.
    mutating func setTitle(_ title: String) {
        diagram.title = title.isEmpty ? nil : title
    }

    mutating func addSection(_ label: DiagramLabel) throws(MermaidDiagramReadError) {
        try countItem()
        diagram.sections.append(label)
    }

    mutating func addPeriod(_ label: DiagramLabel) throws(MermaidDiagramReadError) {
        try countItem()
        diagram.periods.append(ReferenceTimelinePeriod(label: label, sectionIndex: diagram.sections.isEmpty ? nil : diagram.sections.count - 1))
    }

    /// An event written on `line`, for the period written last; an event before any period is an error, as in Mermaid.
    mutating func addEvent(_ label: DiagramLabel, line: Int) throws(MermaidDiagramReadError) {
        guard !diagram.periods.isEmpty else { throw .invalidSyntax(line: line, problem: .eventWithoutPeriod) }
        try countItem()
        diagram.periods[diagram.periods.count - 1].events.append(label)
    }

    mutating func apply(_ statement: MermaidAccessibilityStatement) {
        switch statement {
        case .title(let title): diagram.accessibilityTitle = title
        case .description(let description): diagram.accessibilityDescription = description
        }
    }

    /// Sections, periods and events are each a node for `MermaidDiagramLimits.maximumNodeCount`.
    private mutating func countItem() throws(MermaidDiagramReadError) {
        guard itemCount < limits.maximumNodeCount else { throw .tooManyNodes(limit: limits.maximumNodeCount) }
        itemCount += 1
    }
}
