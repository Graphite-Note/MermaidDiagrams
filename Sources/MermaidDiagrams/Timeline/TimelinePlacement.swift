/**
 * File: TimelinePlacement.swift
 * -----------------------------
 * Layer: Core
 * Description: What both of a timeline's placements share: Pele's measurements, the boxes' sizes, the colors, the
 *              sections' headings measured into the measurement's lines, and the body's width.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.2
 * Date: 26/11/2026
 */

import CoreGraphics

/// What both of a timeline's placements share: Pele's measurements, the boxes' sizes, and where the body starts.
/// `TimelineAcrossPlacement` and `TimelineDownPlacement` place the boxes.
struct TimelinePlacement<Measurer: DiagramTextMeasuring> {
    let diagram: TimelineDiagram
    /// The measured texts; the sections' headings are measured into its lines as they are placed.
    var measured: TimelineMeasurement
    let groups: [TimelineGroup]
    /// The measurer of periods' and sections' text.
    let periodText: Measurer
    let eventText: Measurer

    var columnWidth: CGFloat { measured.textWidth + 2 * TimelineGeometry.boxPadding.width }
    var eventWidth: CGFloat { measured.eventTextWidth + 2 * TimelineGeometry.boxPadding.width }
    var hasEvents: Bool { !measured.eventTexts.isEmpty }
    var hasPeriods: Bool { !diagram.periodRecords.isEmpty }

    /// The height of a period's or a section's box around its text, at least a line high.
    func chipHeight(_ text: DiagramMeasuredText) -> CGFloat {
        max(text.height, periodText.lineHeight) + 2 * TimelineGeometry.boxPadding.height
    }

    func eventHeight(_ text: DiagramMeasuredText) -> CGFloat {
        max(text.height, eventText.lineHeight) + 2 * TimelineGeometry.boxPadding.height
    }

    /// A section's heading text, fitted inside a box `width` wide, its lines added to the measurement's.
    mutating func sectionText(_ sectionIndex: Int, boxWidth width: CGFloat) -> DiagramMeasuredText {
        let measurer = DiagramFlatMeasurer(periodText)
        let section = diagram.sectionTexts[sectionIndex]
        return diagram.text.withBytes { bytes in
            TimelineText.measured(section, in: bytes, measurer: measurer, maximumWidth: width - 2 * TimelineGeometry.boxPadding.width, cutsWideWords: true,
                                  into: &measured.lines)
        }
    }

    /// A period's color: its section's, the series in turn without sections, muted before the first section.
    func color(ofPeriod periodIndex: Int, in group: TimelineGroup) -> TimelineColor {
        if let section = group.sectionIndex { return .series(section) }
        return diagram.sectionTexts.isEmpty ? .series(periodIndex) : .muted
    }

    /// The width of everything but the title.
    func bodyWidth(isDown: Bool) -> CGFloat {
        if isDown {
            if hasEvents { return columnWidth + TimelineGeometry.axisGap + 2 * TimelineGeometry.spineGap + eventWidth }
            return columnWidth + (hasPeriods ? TimelineGeometry.axisGap + TimelineGeometry.axisTail : 0)
        }
        let slots = groups.reduce(0) { slots, group in slots + max(group.periodCount, 1) }
        guard slots > 0 else { return 0 }
        let arrowRoom = hasPeriods ? TimelineGeometry.axisTail + DiagramEdgeMark.arrowLength : 0
        return CGFloat(slots) * (columnWidth + TimelineGeometry.gap) - TimelineGeometry.gap + arrowRoom
    }

    /// A placed event `frame`, with its text centered in it.
    static func event(_ text: DiagramMeasuredText, frame: CGRect) -> TimelinePlacedEvent {
        TimelinePlacedEvent(frame: frame, text: text.centered(at: CGPoint(x: frame.midX, y: frame.midY)))
    }
}
