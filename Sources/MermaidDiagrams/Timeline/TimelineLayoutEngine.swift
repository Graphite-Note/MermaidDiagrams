/**
 * File: TimelineLayoutEngine.swift
 * --------------------------------
 * Layer: Core
 * Description: Lays a timeline out across or down with Pele's measurements, and for a narrow container turned to run down
 *              with its columns sharing the container's width, as Pele turns it.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.4
 * Date: 26/11/2026
 */

import CoreGraphics

/// Lays a timeline out in Pele's style: across, its periods in columns along an axis with their events below; down
/// (`timeline TD`), its periods in a column beside the axis with their events to the right. Periods and sections are
/// boxes in their series colors, events tinted boxes, text wrapped in columns 152 to 216 points wide (events at
/// seven eighths of the size), and the title above.
public enum TimelineLayoutEngine {
    /// Around the whole diagram.
    static let padding: CGFloat = 8
    /// Between the title and the diagram.
    static let titleGap: CGFloat = 16
    /// The narrowest a title wraps at, when the body is narrower.
    static let narrowestTitleWidth: CGFloat = 320

    public static func layout(_ diagram: TimelineDiagram, typography: DiagramTypography) -> TimelineLayout {
        layout(diagram, periodText: typography.nodeText, eventText: typography.edgeText, font: typography.font)
    }

    /// The timeline for a container `availableWidth` wide (nil for none), as Pele draws it: one written to run down runs
    /// down with its columns sharing the container's width; one across stays across unless it does not fit a container
    /// under 640 points and turned down (`turnedToRunDown`, its columns sharing the width) is narrower (`turnToFit`).
    public static func layout(_ diagram: TimelineDiagram, typography: DiagramTypography, availableWidth: CGFloat?) -> TimelineLayout {
        let room = DiagramWidthFitting.limit(availableWidth).map { width in width - 2 * padding } ?? .infinity
        func laidOut(_ diagram: TimelineDiagram, room: CGFloat) -> TimelineLayout {
            layout(diagram, periodText: typography.nodeText, eventText: typography.edgeText, font: typography.font, room: room)
        }
        guard let turned = diagram.turnedToRunDown else { return laidOut(diagram, room: room) }
        return DiagramWidthFitting.turnToFit(availableWidth: availableWidth, width: { (layout: TimelineLayout) in layout.size.width }) { isDown in
            isDown ? laidOut(turned, room: room) : laidOut(diagram, room: .infinity)
        }
    }

    /// `room`: what a timeline running down has for its columns (`TimelineMeasurement`), infinity for no limit.
    static func layout<Measurer: DiagramTextMeasuring>(_ diagram: TimelineDiagram, periodText: Measurer, eventText: Measurer,
                                                       font: DiagramFont, room: CGFloat = .infinity) -> TimelineLayout {
        let isDown = diagram.direction == .topToBottom
        let measured = TimelineMeasurement(diagram: diagram, periodText: periodText, eventText: eventText, isDown: isDown, room: isDown ? room : .infinity)
        let placement = TimelinePlacement(diagram: diagram, measured: consume measured, groups: TimelineGroup.groups(of: diagram), periodText: periodText,
                                          eventText: eventText)
        let bodyWidth = placement.bodyWidth(isDown: isDown)
        let title = diagram.title.map { title in
            TimelineTextFitting.fitted(DiagramLabelDecoder.label(from: title, form: .literal), measurer: periodText,
                                       maximumWidth: max(bodyWidth, narrowestTitleWidth))
        }
        let titleSize = title?.size ?? .zero
        let width = max(bodyWidth, titleSize.width)
        let origin = CGPoint(x: padding + (width - bodyWidth) / 2, y: padding + (title == nil ? 0 : titleSize.height + titleGap))
        // The placement is handed over whole, so that the sections' headings are measured into lines no one else holds.
        let body: TimelinePlacedBody
        let lines: DiagramMeasuredLines
        if isDown {
            var down = TimelineDownPlacement(placement: consume placement)
            body = down.placed(at: origin)
            lines = down.placement.measured.lines
        } else {
            var across = TimelineAcrossPlacement(placement: consume placement)
            body = across.placed(at: origin)
            lines = across.placement.measured.lines
        }
        let size = CGSize(width: (width + 2 * padding).rounded(.up), height: max(body.bottom + padding, 2 * padding).rounded(.up))
        var placedTitle = title
        placedTitle?.center = CGPoint(x: size.width / 2, y: padding + titleSize.height / 2)
        var layout = TimelineLayout(size: size, font: font, direction: diagram.direction, body: body, title: placedTitle, text: diagram.text,
                                    lines: lines)
        layout.seriesColors = diagram.seriesColors
        return layout
    }
}
