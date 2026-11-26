/**
 * File: TimelinePlacedBody.swift
 * ------------------------------
 * Layer: Core
 * Description: What a timeline's placement makes, as flat records: its sections, periods and events with their measured
 *              texts, its connectors as runs of one list of points, the axis and how far down the body reaches.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics

/// A section heading's box and its text, fitted inside it.
struct TimelinePlacedSection: Equatable, Sendable {
    var sectionIndex: Int
    var frame: CGRect
    var text: DiagramMeasuredText
}

/// A period's box, text and dot, its connectors a run of `TimelinePlacedBody.connectors` and its events a run of
/// `TimelinePlacedBody.events`.
struct TimelinePlacedPeriod: Equatable, Sendable {
    var color: TimelineColor
    var frame: CGRect
    var text: DiagramMeasuredText
    var dot: CGPoint
    var firstConnector: Int32
    var connectorCount: Int32
    var firstEvent: Int32
    var eventCount: Int32

    var connectorIndices: Range<Int> { Int(firstConnector)..<Int(firstConnector + connectorCount) }
    var eventIndices: Range<Int> { Int(firstEvent)..<Int(firstEvent + eventCount) }
}

struct TimelinePlacedEvent: Equatable, Sendable {
    var frame: CGRect
    var text: DiagramMeasuredText
}

/// A straight line through a run of `TimelinePlacedBody.connectorPoints`.
struct TimelineConnector: Equatable, Sendable {
    var firstPoint: Int32
    var pointCount: Int32

    var pointIndices: Range<Int> { Int(firstPoint)..<Int(firstPoint + pointCount) }
}

/// What a placement makes: the boxes, the connectors, the axis and how far down the body reaches. The periods are in
/// the order they are written, and so are their events.
struct TimelinePlacedBody: Sendable {
    var sections: [TimelinePlacedSection] = []
    var periods: [TimelinePlacedPeriod] = []
    var events: [TimelinePlacedEvent] = []
    var connectors: [TimelineConnector] = []
    var connectorPoints: [CGPoint] = []
    var axis: DiagramPath?
    var axisArrow: DiagramEdgeMark?
    var bottom: CGFloat = 0

    /// Room for the periods, events and connectors of a timeline of `periodCount` periods and `eventCount` events.
    mutating func reserve(periodCount: Int, eventCount: Int, connectorsPerEvent: Int) {
        periods.reserveCapacity(periodCount)
        events.reserveCapacity(eventCount)
        connectors.reserveCapacity(periodCount * 2 + eventCount * connectorsPerEvent)
        connectorPoints.reserveCapacity(periodCount * 4 + eventCount * 2 * connectorsPerEvent)
    }

    /// A straight line from `start` to `end`, appended.
    mutating func appendConnector(_ start: CGPoint, _ end: CGPoint) {
        connectors.append(TimelineConnector(firstPoint: Int32(connectorPoints.count), pointCount: 2))
        connectorPoints.append(start)
        connectorPoints.append(end)
    }

    /// A straight line from `start` through `corner` to `end`, appended.
    mutating func appendConnector(_ start: CGPoint, _ corner: CGPoint, _ end: CGPoint) {
        connectors.append(TimelineConnector(firstPoint: Int32(connectorPoints.count), pointCount: 3))
        connectorPoints.append(start)
        connectorPoints.append(corner)
        connectorPoints.append(end)
    }

    /// The line of `connector`, as 0.7.0's layout kept it (`TimelineGeometry.line`).
    func path(of connector: TimelineConnector) -> DiagramPath {
        let points = connectorPoints[connector.pointIndices]
        return DiagramPath(start: points[points.startIndex], segments: points.dropFirst().map { point in .line(to: point) })
    }
}
