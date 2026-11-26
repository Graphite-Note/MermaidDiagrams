/**
 * File: TimelineDownPlacement.swift
 * ---------------------------------
 * Layer: Core
 * Description: Places a timeline that runs down as Pele does, into flat records: periods in a column beside the axis
 *              under their sections' headings, each period's events stacked beside it, reached by a spine.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.2
 * Date: 26/11/2026
 */

import CoreGraphics

/// Places a timeline that runs down, as Pele does: the periods one below the other in a column, a section's heading
/// across the whole width above its periods, the axis to the right of the periods with a dot level with each, and
/// each period's events stacked beside it, reached by a spine; a period and its first event share a center line.
struct TimelineDownPlacement<Measurer: DiagramTextMeasuring> {
    var placement: TimelinePlacement<Measurer>

    /// The body placed with its top left corner at `origin`.
    mutating func placed(at origin: CGPoint) -> TimelinePlacedBody {
        let bodyWidth = placement.bodyWidth(isDown: true)
        let axisX = origin.x + placement.columnWidth + TimelineGeometry.axisGap
        var body = TimelinePlacedBody()
        body.reserve(periodCount: placement.diagram.periodRecords.count, eventCount: placement.measured.eventTexts.count, connectorsPerEvent: 1)
        var top = origin.y
        for group in placement.groups {
            if let section = group.sectionIndex {
                let text = placement.sectionText(section, boxWidth: bodyWidth)
                let frame = CGRect(x: origin.x, y: top, width: bodyWidth, height: placement.chipHeight(text))
                body.sections.append(TimelinePlacedSection(sectionIndex: section, frame: frame, text: text.centered(at: CGPoint(x: frame.midX, y: frame.midY))))
                top = frame.maxY + TimelineGeometry.sectionGap + TimelineGeometry.sectionExtraGapDown
            }
            for periodIndex in group.periodIndices {
                let period = placePeriod(periodIndex, in: group, top: top, left: origin.x, axisX: axisX, into: &body)
                let lastEventBottom = period.eventCount > 0 ? body.events[Int(period.firstEvent + period.eventCount) - 1].frame.maxY : period.frame.maxY
                top = max(period.frame.maxY, lastEventBottom) + TimelineGeometry.gap
            }
            if group.periodIndices.isEmpty { top += TimelineGeometry.gap - TimelineGeometry.sectionGap - TimelineGeometry.sectionExtraGapDown }
        }
        if !placement.groups.isEmpty { top -= TimelineGeometry.gap }
        if placement.hasPeriods {
            let tip = CGPoint(x: axisX, y: top + TimelineGeometry.axisTail + DiagramEdgeMark.arrowLength)
            body.axis = TimelineGeometry.line(CGPoint(x: axisX, y: origin.y), CGPoint(x: axisX, y: tip.y - DiagramEdgeMark.arrowLength + 1))
            body.axisArrow = DiagramEdgeMark(arrowhead: .arrow, tip: tip, direction: CGVector(dx: 0, dy: 1))
            top = tip.y
        }
        body.bottom = top
        return body
    }

    /// A period from `top`: its box and its first event centered on one line, the line to the axis and its dot, and
    /// its events stacked to the right, each reached from the spine; appended to `body` and returned.
    private func placePeriod(_ periodIndex: Int, in group: TimelineGroup, top: CGFloat, left: CGFloat, axisX: CGFloat,
                             into body: inout TimelinePlacedBody) -> TimelinePlacedPeriod {
        let periodText = placement.measured.periodTexts[periodIndex]
        let eventIndices = placement.diagram.periodRecords[periodIndex].eventIndices
        let height = placement.chipHeight(periodText)
        let firstEventHeight = eventIndices.first.map { index in placement.eventHeight(placement.measured.eventTexts[index]) } ?? height
        let centerY = top + max(height, firstEventHeight) / 2
        let frame = CGRect(x: left, y: centerY - height / 2, width: placement.columnWidth, height: height)
        let spineX = axisX + TimelineGeometry.spineGap
        let eventsX = spineX + TimelineGeometry.spineGap
        let firstConnector = body.connectors.count
        let firstEvent = body.events.count
        body.appendConnector(CGPoint(x: frame.maxX, y: centerY), CGPoint(x: axisX, y: centerY))
        var eventTop = centerY - firstEventHeight / 2
        for eventIndex in eventIndices {
            let eventText = placement.measured.eventTexts[eventIndex]
            let eventFrame = CGRect(x: eventsX, y: eventTop, width: placement.eventWidth, height: placement.eventHeight(eventText))
            body.appendConnector(CGPoint(x: spineX, y: eventFrame.midY), CGPoint(x: eventsX, y: eventFrame.midY))
            body.events.append(TimelinePlacement<Measurer>.event(eventText, frame: eventFrame))
            eventTop = eventFrame.maxY + TimelineGeometry.eventGap
        }
        if body.events.count > firstEvent, let lastEvent = body.events.last {
            body.appendConnector(CGPoint(x: axisX, y: centerY), CGPoint(x: spineX, y: centerY), CGPoint(x: spineX, y: lastEvent.frame.midY))
        }
        let period = TimelinePlacedPeriod(color: placement.color(ofPeriod: periodIndex, in: group), frame: frame,
                                          text: periodText.centered(at: CGPoint(x: frame.midX, y: frame.midY)), dot: CGPoint(x: axisX, y: centerY),
                                          firstConnector: Int32(firstConnector), connectorCount: Int32(body.connectors.count - firstConnector),
                                          firstEvent: Int32(firstEvent), eventCount: Int32(body.events.count - firstEvent))
        body.periods.append(period)
        return period
    }
}
