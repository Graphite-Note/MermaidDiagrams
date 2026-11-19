/**
 * File: RailroadLayoutEngine.swift
 * --------------------------------
 * Layer: Core
 * Description: Lays a railroad diagram out as Pele does: each rule's name, then its track from a dot through its parts
 *              to a dot, one rule below the other, in the measurements of the diagram's options and Pele's defaults.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// Lays a railroad diagram out as Pele's renderer does: boxes 14 points tall around text at seven eighths of the font
/// size, 16 points between the parts of a sequence and 10 between stacked branches, turns of 10 points, a dot of 4
/// points at each end of a track 12 points from its first and last part, 18 points between rules. A narrow column gets
/// Pele's tighter layout (`layout(_:typography:columnWidth:)`): 12 points between parts, turns of 6, and sequences
/// folded into rows that fit the column.
public enum RailroadLayoutEngine {
    /// Between a track's dot and its first part, below a rule's name, between rules, around the page.
    static let lead: CGFloat = 12
    static let headGap: CGFloat = 6
    static let ruleGap: CGFloat = 18
    static let padding: CGFloat = 8
    static let titleGap: CGFloat = 16
    /// The widest a title is before it wraps across, and the narrowest a folded rule's room is.
    static let unwrappedWidth: CGFloat = 4_000
    static let smallestTightRoom: CGFloat = 80

    public static func layout(_ diagram: RailroadDiagram, typography: DiagramTypography) -> RailroadLayout {
        layout(diagram, typography: typography, tightColumnWidth: nil)
    }

    /// The diagram with Pele's tighter gaps and turns, each rule's long sequences folded to fit `columnWidth`.
    public static func layout(_ diagram: RailroadDiagram, typography: DiagramTypography, columnWidth: CGFloat) -> RailroadLayout {
        layout(diagram, typography: typography, tightColumnWidth: columnWidth)
    }

    private static func layout(_ diagram: RailroadDiagram, typography: DiagramTypography, tightColumnWidth: CGFloat?) -> RailroadLayout {
        let options = RailroadResolvedOptions(diagram.options, fontSize: typography.font.size, isTight: tightColumnWidth != nil)
        let metrics = options.metrics(typography: typography)
        let headText = typography.measurer(size: options.headSize, isBold: true)
        let titleRoom = tightColumnWidth.map { width in max(80, width - 2 * padding) } ?? unwrappedWidth
        let title = EventModelText.label(diagram.title, measurer: typography.boldNodeText, maximumWidth: titleRoom)
        var width = title?.size.width ?? 0
        var top = padding + (title.map { title in title.size.height + titleGap } ?? 0)
        var bottom = padding + (title?.size.height ?? 0)
        let room = tightColumnWidth.map { width in max(smallestTightRoom, width - 2 * padding - 4 * options.markerRadius - 2 * lead - 1) } ?? .infinity
        let headHeight = (options.headSize * 1.5).rounded()
        let measurement = RailroadTrackMeasurement(metrics: metrics)
        var rules: [RailroadLayoutRule] = []
        for rule in diagram.rules {
            let box = measurement.box(of: rule.definition, room: room)
            let baseline = top + headHeight + headGap + box.up
            let start = padding + 2 * options.markerRadius
            let left = start + lead
            let end = left + box.width + lead
            var placement = RailroadTrackPlacement(metrics: metrics)
            placement.line(from: start, to: left, at: baseline)
            placement.line(from: left + box.width, to: end, at: baseline)
            placement.place(box, left: left, baseline: baseline)
            let name = EventModelText.block([RailroadText.shown(rule.name)], measurer: headText)
            let markers = options.markerRadius > 0 ? [CGPoint(x: padding + options.markerRadius, y: baseline), CGPoint(x: end + options.markerRadius, y: baseline)] : []
            rules.append(RailroadLayoutRule(
                name: EventModelText.placed(name, center: CGPoint(x: padding + name.size.width / 2, y: top + headHeight / 2)),
                track: placement.track.finishedPaths, arrows: placement.arrows, markerCenters: markers, boxes: placement.boxes,
                counts: placement.counts).translated(by: halfPoint))
            width = max(width, end + 2 * options.markerRadius - padding, name.size.width)
            bottom = baseline + box.down
            top = bottom + metrics.separation + ruleGap
        }
        let size = CGSize(width: (width + 2 * padding).rounded(.up), height: (bottom + padding).rounded(.up))
        return RailroadLayout(size: size, font: typography.font,
                              title: title.map { title in EventModelText.placed(title, center: CGPoint(x: size.width / 2, y: padding + title.size.height / 2)) },
                              rules: rules, lineWidth: options.strokeWidth, markerRadius: options.markerRadius, isTight: tightColumnWidth != nil)
    }

    /// Pele moves the rules half a point right and down, so that one-point lines on whole coordinates fall on pixels.
    private static let halfPoint = CGVector(dx: 0.5, dy: 0.5)
}

/// A railroad diagram's options with Pele's defaults and bounds applied: a value is used when it is a number of zero or
/// more, up to its bound.
struct RailroadResolvedOptions {
    let size: CGFloat
    let headSize: CGFloat
    let padding: CGFloat
    let height: CGFloat
    let gap: CGFloat
    let separation: CGFloat
    let arc: CGFloat
    let markerRadius: CGFloat
    let strokeWidth: CGFloat

    init(_ options: RailroadOptions, fontSize base: CGFloat, isTight: Bool) {
        func option(_ value: Double?, _ fallback: CGFloat, maximum: CGFloat) -> CGFloat {
            guard let value, value >= 0 else { return fallback }
            return min(CGFloat(value), maximum)
        }
        let fontSize = option(options.fontSize, 0, maximum: 200)
        size = fontSize > 0 ? fontSize : (base * 0.875).rounded()
        headSize = fontSize > 0 ? fontSize : base
        let writtenPadding = option(options.padding, -1, maximum: 200)
        padding = writtenPadding < 0 ? 12 : writtenPadding
        height = RailroadMetrics.even((size * 1.5).rounded() + (writtenPadding < 0 ? 9 : 2 * writtenPadding))
        gap = min(option(options.horizontalSeparation, 16, maximum: 500), isTight ? 12 : .infinity)
        separation = option(options.verticalSeparation, 10, maximum: 500)
        arc = min(option(options.arcRadius, 10, maximum: 200), isTight ? 6 : .infinity)
        markerRadius = options.showsMarkers ? option(options.markerRadius, 4, maximum: 50) : 0
        let writtenStrokeWidth = option(options.strokeWidth, 0, maximum: 20)
        strokeWidth = writtenStrokeWidth > 0 ? writtenStrokeWidth : 1
    }

    func metrics(typography: DiagramTypography) -> RailroadMetrics {
        RailroadMetrics(terminalText: typography.measurer(size: size, isMonospaced: true), nameText: typography.measurer(size: size),
                        specialText: typography.measurer(size: size, isItalic: true), countText: typography.measurer(size: RailroadMetrics.countSize),
                        padding: padding, height: height, gap: gap, separation: separation, arc: arc)
    }
}

extension RailroadLayoutRule {
    func translated(by offset: CGVector) -> RailroadLayoutRule {
        RailroadLayoutRule(name: name.translated(by: offset), track: track.map { path in path.translated(by: offset) },
                           arrows: arrows.map { arrow in RailroadLayoutArrow(points: arrow.points.map { point in point.translated(by: offset) }) },
                           markerCenters: markerCenters.map { center in center.translated(by: offset) },
                           boxes: boxes.map { box in
                               RailroadLayoutBox(kind: box.kind, frame: box.frame.offsetBy(dx: offset.dx, dy: offset.dy), text: box.text.translated(by: offset),
                                                 questionMarks: box.questionMarks.map { mark in mark.translated(by: offset) })
                           },
                           counts: counts.map { count in count.translated(by: offset) })
    }
}
