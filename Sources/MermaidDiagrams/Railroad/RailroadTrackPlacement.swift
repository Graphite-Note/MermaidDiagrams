/**
 * File: RailroadTrackPlacement.swift
 * ----------------------------------
 * Layer: Core
 * Description: Places a measured railroad rule as Pele draws it: the track through each part, its turns as quarter
 *              circles, the branches of choices below the baseline, bypasses above, loops below with their counts,
 *              folded rows inside rails.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */

import CoreGraphics

/// The track, arrows, boxes and counts of one rule, placed part by part from its measured boxes.
struct RailroadTrackPlacement {
    let metrics: RailroadMetrics
    private(set) var track = RailroadTrackDrawing()
    private(set) var arrows: [RailroadLayoutArrow] = []
    private(set) var boxes: [RailroadLayoutBox] = []
    private(set) var counts: [DiagramTextBlock] = []

    init(metrics: RailroadMetrics) {
        self.metrics = metrics
    }

    /// A straight piece of track from `start` to `end` on `y`, when it has a length.
    mutating func line(from start: CGFloat, to end: CGFloat, at y: CGFloat) {
        guard end > start else { return }
        track.move(to: CGPoint(x: start, y: y))
        track.horizontal(to: end)
    }

    /// Places `box` with its track entering at `left` on `baseline`. Each kind is placed by a function of its own, so that
    /// this one, which every level of a rule's tree passes through, keeps a small frame on the stack: a tree nested as
    /// deep as `RailroadExpression.maximumNestingDepth` allows is placed on a secondary thread's 512 KiB stack in a debug
    /// build too.
    mutating func place(_ box: RailroadTrackBox, left: CGFloat, baseline: CGFloat) {
        let right = left + box.width
        switch box.kind {
        case .terminal, .nonterminal, .special: placeLeaf(box, left: left, baseline: baseline)
        case .sequence: placeSequence(box, left: left, baseline: baseline)
        case .folded: placeFolded(box, left: left, right: right, baseline: baseline)
        case .choice: placeChoice(box, left: left, right: right, baseline: baseline)
        case .bypass: placeBypass(box, left: left, right: right, baseline: baseline)
        case .loop: placeLoop(box, left: left, right: right, baseline: baseline)
        }
    }

    /// The parts one after another on the baseline, the gap between them a straight track.
    private mutating func placeSequence(_ box: RailroadTrackBox, left: CGFloat, baseline: CGFloat) {
        var x = left
        for (index, child) in box.children.enumerated() {
            if index > 0 { line(from: x - metrics.gap, to: x, at: baseline) }
            place(child, left: x, baseline: baseline)
            x += child.width + metrics.gap
        }
    }

    /// The part on the baseline, and a track above it from its left over to its right.
    private mutating func placeBypass(_ box: RailroadTrackBox, left: CGFloat, right: CGFloat, baseline: CGFloat) {
        let child = box.children[0]
        let childLeft = left + 2 * metrics.arc
        line(from: left, to: childLeft, at: baseline)
        line(from: childLeft + child.width, to: right, at: baseline)
        track.move(to: CGPoint(x: left, y: baseline))
        track.turn(.eastToNorth, radius: metrics.arc)
        track.vertical(to: baseline - box.reach + metrics.arc)
        track.turn(.northToEast, radius: metrics.arc)
        track.horizontal(to: right - 2 * metrics.arc)
        track.turn(.eastToSouth, radius: metrics.arc)
        track.vertical(to: baseline - metrics.arc)
        track.turn(.southToEast, radius: metrics.arc)
        place(child, left: childLeft, baseline: baseline)
    }

    private mutating func placeLeaf(_ box: RailroadTrackBox, left: CGFloat, baseline: CGFloat) {
        let frame = CGRect(x: left, y: baseline - metrics.height / 2, width: box.width, height: metrics.height)
        let center = CGPoint(x: frame.midX, y: baseline)
        switch box.kind {
        case .terminal:
            boxes.append(RailroadLayoutBox(kind: .terminal, frame: frame, text: placed([box.text], metrics.terminalText, center: center), questionMarks: []))
        case .special:
            // `? ` and ` ?` in the muted color around the text, the three centered together.
            let inside = String(box.text.dropFirst(2).dropLast(2))
            let pieces = ["? ", inside, " ?"].map { piece in metrics.specialText.width(of: piece) }
            var x = center.x - pieces.reduce(0, +) / 2
            var blocks: [DiagramTextBlock] = []
            for (piece, width) in zip(["? ", inside, " ?"], pieces) {
                blocks.append(placed([piece], metrics.specialText, center: CGPoint(x: x + width / 2, y: baseline)))
                x += width
            }
            boxes.append(RailroadLayoutBox(kind: .special, frame: frame, text: blocks[1], questionMarks: [blocks[0], blocks[2]]))
        default:
            boxes.append(RailroadLayoutBox(kind: .nonterminal, frame: frame, text: placed([box.text], metrics.nameText, center: center), questionMarks: []))
        }
    }

    /// The rows one below the other: each row's end runs to the right rail, down, back along the gap to the left rail
    /// and down into the next row, an arrow where it enters; the last row's end runs up to the baseline at the right.
    private mutating func placeFolded(_ box: RailroadTrackBox, left: CGFloat, right: CGFloat, baseline: CGFloat) {
        let arc = metrics.arc
        let start = left + 2 * arc
        let rowGap = RailroadTrackBox.rowGap(metrics)
        let arrow = RailroadMetrics.arrowLength
        line(from: left, to: start, at: baseline)
        var offset: CGFloat = 0
        for (index, row) in box.children.enumerated() {
            let rowBaseline = baseline + offset
            if index + 1 < box.children.count {
                let next = box.children[index + 1]
                let nextOffset = offset + row.down + rowGap + next.up
                track.move(to: CGPoint(x: start + row.width, y: rowBaseline))
                track.horizontal(to: right - 2 * arc)
                track.vertical(to: baseline + offset + row.down + rowGap / 2)
                track.horizontal(to: left + arc)
                track.vertical(to: baseline + nextOffset)
                track.horizontal(to: start)
                let tip = CGPoint(x: start, y: baseline + nextOffset)
                arrows.append(RailroadLayoutArrow(points: [CGPoint(x: tip.x - arrow, y: tip.y - arrow / 2), tip, CGPoint(x: tip.x - arrow, y: tip.y + arrow / 2)]))
                offset = nextOffset
            } else {
                track.move(to: CGPoint(x: start + row.width, y: rowBaseline))
                track.horizontal(to: right - arc)
                track.vertical(to: baseline)
                track.horizontal(to: right)
            }
            place(row, left: start, baseline: rowBaseline)
        }
    }

    /// The first branch on the baseline; each next one below, reached by a turn down from the left rail and a turn up
    /// into the right one, each branch centered between the rails.
    private mutating func placeChoice(_ box: RailroadTrackBox, left: CGFloat, right: CGFloat, baseline: CGFloat) {
        let arc = metrics.arc
        let inner = box.width - 4 * arc
        let railIn = left + arc
        let railOut = right - arc
        var offset: CGFloat = 0
        for (index, child) in box.children.enumerated() {
            if index > 0 { offset = RailroadTrackBox.offset(below: box.children[index - 1], at: offset, of: child, metrics: metrics) }
            let childBaseline = baseline + offset
            let childLeft = left + 2 * arc + (inner - child.width) / 2
            let isLast = index == box.children.count - 1
            if index == 0 {
                line(from: left, to: childLeft, at: baseline)
                line(from: childLeft + child.width, to: right, at: baseline)
            } else {
                if isLast {
                    track.move(to: CGPoint(x: left, y: baseline))
                    track.turn(.eastToSouth, radius: arc)
                    track.vertical(to: childBaseline - arc)
                } else {
                    track.move(to: CGPoint(x: railIn, y: childBaseline - arc))
                }
                track.turn(.southToEast, radius: arc)
                if childLeft > railIn + arc { track.horizontal(to: childLeft) }
                track.move(to: CGPoint(x: childLeft + child.width, y: childBaseline))
                if childLeft > railIn + arc { track.horizontal(to: railOut - arc) }
                track.turn(.eastToNorth, radius: arc)
                if isLast {
                    track.vertical(to: baseline + arc)
                    track.turn(.northToEast, radius: arc)
                }
            }
            place(child, left: childLeft, baseline: childBaseline)
        }
    }

    /// The part centered on the baseline, and a track below it from its left back round to its right, an arrow in its
    /// middle pointing back, and the count under it.
    private mutating func placeLoop(_ box: RailroadTrackBox, left: CGFloat, right: CGFloat, baseline: CGFloat) {
        let arc = metrics.arc
        let child = box.children[0]
        let childLeft = left + (box.width - child.width) / 2
        let loopY = baseline + box.reach
        let middle = left + box.width / 2
        let arrow = RailroadMetrics.arrowLength
        line(from: left, to: childLeft, at: baseline)
        line(from: childLeft + child.width, to: right, at: baseline)
        track.move(to: CGPoint(x: left + arc, y: baseline))
        track.turn(.westToSouth, radius: arc)
        track.vertical(to: loopY - arc)
        track.turn(.southToEast, radius: arc)
        track.horizontal(to: right - arc)
        track.turn(.eastToNorth, radius: arc)
        track.vertical(to: baseline + arc)
        track.turn(.northToWest, radius: arc)
        let tip = CGPoint(x: middle - arrow / 2, y: loopY)
        arrows.append(RailroadLayoutArrow(points: [tip, CGPoint(x: tip.x + arrow, y: loopY - arrow / 2), CGPoint(x: tip.x + arrow, y: loopY + arrow / 2)]))
        if !box.text.isEmpty {
            let baselineOfCount = loopY + RailroadMetrics.countSize + 3
            counts.append(placed([box.text], metrics.countText,
                                 center: CGPoint(x: middle, y: baselineOfCount - DiagramTextDrawing.baselineShiftRatio * RailroadMetrics.countSize)))
        }
        place(child, left: childLeft, baseline: baseline)
    }

    private func placed(_ lines: [String], _ measurer: CoreTextDiagramTextMeasurer, center: CGPoint) -> DiagramTextBlock {
        EventModelText.placed(EventModelText.block(lines, measurer: measurer), center: center)
    }
}

/// A track's pieces: lines from a point, and quarter turns of a radius drawn as Bézier curves, as SVG's arcs of a
/// quarter circle are.
struct RailroadTrackDrawing {
    /// A quarter turn, by the heading the track enters and leaves it with.
    enum Turn {
        case eastToSouth
        case southToEast
        case eastToNorth
        case northToEast
        case westToSouth
        case northToWest
    }

    private(set) var paths: [DiagramPath] = []
    private var start = CGPoint.zero
    private var segments: [DiagramPathSegment] = []
    private var current = CGPoint.zero

    /// How far along its tangents a cubic Bézier's handles reach to draw a quarter circle.
    private static let handle: CGFloat = 0.5522847498

    mutating func move(to point: CGPoint) {
        finish()
        start = point
        current = point
    }

    mutating func horizontal(to x: CGFloat) {
        add(.line(to: CGPoint(x: x, y: current.y)), ending: CGPoint(x: x, y: current.y))
    }

    mutating func vertical(to y: CGFloat) {
        add(.line(to: CGPoint(x: current.x, y: y)), ending: CGPoint(x: current.x, y: y))
    }

    mutating func turn(_ turn: Turn, radius: CGFloat) {
        let handle = radius * Self.handle
        let point = current
        let (end, first, second): (CGVector, CGVector, CGVector)
        switch turn {
        case .eastToSouth: (end, first, second) = (CGVector(dx: radius, dy: radius), CGVector(dx: handle, dy: 0), CGVector(dx: radius, dy: radius - handle))
        case .southToEast: (end, first, second) = (CGVector(dx: radius, dy: radius), CGVector(dx: 0, dy: handle), CGVector(dx: radius - handle, dy: radius))
        case .eastToNorth: (end, first, second) = (CGVector(dx: radius, dy: -radius), CGVector(dx: handle, dy: 0), CGVector(dx: radius, dy: handle - radius))
        case .northToEast: (end, first, second) = (CGVector(dx: radius, dy: -radius), CGVector(dx: 0, dy: -handle), CGVector(dx: radius - handle, dy: -radius))
        case .westToSouth: (end, first, second) = (CGVector(dx: -radius, dy: radius), CGVector(dx: -handle, dy: 0), CGVector(dx: -radius, dy: radius - handle))
        case .northToWest: (end, first, second) = (CGVector(dx: -radius, dy: -radius), CGVector(dx: 0, dy: -handle), CGVector(dx: handle - radius, dy: -radius))
        }
        let ending = point.translated(by: end)
        add(.curve(to: ending, control1: point.translated(by: first), control2: point.translated(by: second)), ending: ending)
    }

    /// The pieces, the last one finished.
    var finishedPaths: [DiagramPath] {
        var copy = self
        copy.finish()
        return copy.paths
    }

    private mutating func add(_ segment: DiagramPathSegment, ending: CGPoint) {
        segments.append(segment)
        current = ending
    }

    private mutating func finish() {
        guard !segments.isEmpty else { return }
        paths.append(DiagramPath(start: start, segments: segments))
        segments = []
    }
}
