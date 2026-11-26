/**
 * File: TimelineDiagramBuilder.swift
 * ----------------------------------
 * Layer: Core
 * Description: Collects a timeline as its statements are read, its texts as ranges of its text's bytes, and counts
 *              them against the node limit.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.2
 * Date: 26/11/2026
 */

/// Collects a timeline as its statements are read: each period under the section written last, each event on the
/// period written last, and every section, period and event counted against the node limit.
struct TimelineDiagramBuilder {
    private(set) var diagram: TimelineDiagram
    private let limits: MermaidDiagramLimits
    private var itemCount = 0

    /// A builder of a timeline whose texts are ranges of `text`.
    init(text: MermaidSourceText, limits: MermaidDiagramLimits) {
        diagram = TimelineDiagram(text: text)
        self.limits = limits
    }

    mutating func setDirection(_ direction: TimelineDirection) {
        diagram.direction = direction
    }

    /// A later `title` replaces an earlier one; an empty one leaves none.
    mutating func setTitle(_ title: String) {
        diagram.title = title.isEmpty ? nil : title
    }

    mutating func addSection(_ text: TimelineText) throws(MermaidDiagramReadError) {
        try countItem()
        diagram.appendSection(text)
    }

    mutating func addPeriod(_ text: TimelineText) throws(MermaidDiagramReadError) {
        try countItem()
        diagram.appendPeriod(text)
    }

    /// An event written on `line`, for the period written last; an event before any period is an error, as in Mermaid.
    mutating func addEvent(_ text: TimelineText, line: Int) throws(MermaidDiagramReadError) {
        guard !diagram.periodRecords.isEmpty else { throw .invalidSyntax(line: line, problem: .eventWithoutPeriod) }
        try countItem()
        diagram.appendEvent(text)
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
