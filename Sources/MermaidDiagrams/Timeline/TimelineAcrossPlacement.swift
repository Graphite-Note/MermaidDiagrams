/**
 * File: TimelineAcrossPlacement.swift
 * -----------------------------------
 * Layer: Core
 * Description: Places a timeline that runs across as Pele does, into flat records: periods in columns under their
 *              sections' headings, the axis below them and each period's events stacked under it.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.2
 * Date: 26/11/2026
 */

import CoreGraphics

/// Places a timeline that runs across, as Pele does: each period in a column, a section's heading over its periods'
/// columns, the periods in a row, the axis below them with a dot under each, and each period's events stacked under
/// the axis, joined to it by a line.
struct TimelineAcrossPlacement<Measurer: DiagramTextMeasuring> {
    var placement: TimelinePlacement<Measurer>

    /// The body placed with its top left corner at `origin`.
    mutating func placed(at origin: CGPoint) -> TimelinePlacedBody {
        let columnWidth = placement.columnWidth
        let pitch = columnWidth + TimelineGeometry.gap
        var body = TimelinePlacedBody()
        body.reserve(periodCount: placement.diagram.periodRecords.count, eventCount: placement.measured.eventTexts.count, connectorsPerEvent: 1)
        let headerHeight = measureHeadings(pitch: pitch, into: &body)
        var chipHeight: CGFloat = 0
        for (index, text) in placement.measured.periodTexts.enumerated() {
            let height = placement.chipHeight(text)
            if index == 0 || chipHeight < height { chipHeight = height }
        }
        let periodsTop = origin.y + (placement.diagram.sectionTexts.isEmpty ? 0 : headerHeight + TimelineGeometry.sectionGap)
        let axisY = periodsTop + chipHeight + (chipHeight > 0 ? TimelineGeometry.axisGap : 0)
        body.bottom = placement.hasPeriods ? axisY + TimelineGeometry.axisTail : origin.y + headerHeight
        var slot: CGFloat = 0
        var sectionPosition = 0
        for group in placement.groups {
            let groupLeft = origin.x + slot * pitch
            if group.sectionIndex != nil {
                let frame = CGRect(x: groupLeft, y: origin.y, width: span(of: group) * pitch - TimelineGeometry.gap, height: headerHeight)
                body.sections[sectionPosition].frame = frame
                body.sections[sectionPosition].text = body.sections[sectionPosition].text.centered(at: CGPoint(x: frame.midX, y: frame.midY))
                sectionPosition += 1
            }
            for (position, periodIndex) in group.periodIndices.enumerated() {
                let frame = CGRect(x: groupLeft + CGFloat(position) * pitch, y: periodsTop, width: columnWidth, height: chipHeight)
                placePeriod(periodIndex, in: group, frame: frame, axisY: axisY, into: &body)
            }
            slot += span(of: group)
        }
        if placement.hasPeriods {
            let tip = CGPoint(x: origin.x + placement.bodyWidth(isDown: false), y: axisY)
            body.axis = TimelineGeometry.line(CGPoint(x: origin.x, y: axisY), CGPoint(x: tip.x - DiagramEdgeMark.arrowLength + 1, y: axisY))
            body.axisArrow = DiagramEdgeMark(arrowhead: .arrow, tip: tip, direction: CGVector(dx: 1, dy: 0))
        }
        return body
    }

    /// Every section's heading measured, as 0.7.0 measured them before placing any, its section appended to `body` to be
    /// placed; the tallest heading's box height, 0 without sections.
    private mutating func measureHeadings(pitch: CGFloat, into body: inout TimelinePlacedBody) -> CGFloat {
        var headerHeight: CGFloat = 0
        var hasHeading = false
        body.sections.reserveCapacity(placement.groups.count)
        for group in placement.groups {
            guard let section = group.sectionIndex else { continue }
            let text = placement.sectionText(section, boxWidth: span(of: group) * pitch - TimelineGeometry.gap)
            let height = placement.chipHeight(text)
            if !hasHeading || headerHeight < height { headerHeight = height }
            hasHeading = true
            body.sections.append(TimelinePlacedSection(sectionIndex: section, frame: .zero, text: text))
        }
        return headerHeight
    }

    /// How many columns a group takes: one per period, and one for a section without periods.
    private func span(of group: TimelineGroup) -> CGFloat {
        CGFloat(max(group.periodCount, 1))
    }

    /// A period in its column: its box, its dot on the axis, and its events stacked below the axis.
    private func placePeriod(_ periodIndex: Int, in group: TimelineGroup, frame: CGRect, axisY: CGFloat, into body: inout TimelinePlacedBody) {
        let eventIndices = placement.diagram.periodRecords[periodIndex].eventIndices
        let eventsTop = axisY + TimelineGeometry.axisGap
        let firstConnector = body.connectors.count
        let firstEvent = body.events.count
        body.appendConnector(CGPoint(x: frame.midX, y: frame.maxY), CGPoint(x: frame.midX, y: eventIndices.isEmpty ? axisY : eventsTop))
        var eventTop = eventsTop
        for eventIndex in eventIndices {
            let eventText = placement.measured.eventTexts[eventIndex]
            if eventTop > eventsTop {
                body.appendConnector(CGPoint(x: frame.midX, y: eventTop - TimelineGeometry.eventGap), CGPoint(x: frame.midX, y: eventTop))
            }
            let eventFrame = CGRect(x: frame.minX, y: eventTop, width: placement.eventWidth, height: placement.eventHeight(eventText))
            body.events.append(TimelinePlacement<Measurer>.event(eventText, frame: eventFrame))
            eventTop = eventFrame.maxY + TimelineGeometry.eventGap
        }
        if let last = body.events.last, body.events.count > firstEvent { body.bottom = max(body.bottom, last.frame.maxY) }
        body.periods.append(TimelinePlacedPeriod(color: placement.color(ofPeriod: periodIndex, in: group), frame: frame,
                                                 text: placement.measured.periodTexts[periodIndex].centered(at: CGPoint(x: frame.midX, y: frame.midY)),
                                                 dot: CGPoint(x: frame.midX, y: axisY), firstConnector: Int32(firstConnector),
                                                 connectorCount: Int32(body.connectors.count - firstConnector), firstEvent: Int32(firstEvent),
                                                 eventCount: Int32(body.events.count - firstEvent)))
    }
}
