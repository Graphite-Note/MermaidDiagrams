/**
 * File: DiagramPathTangentArcs.swift
 * ----------------------------------
 * Layer: Core
 * Description: The arc Core Graphics puts in a corner between two lines (`add_arc_to_point`), which rounds a rounded
 *              rectangle's corners, worked out in the corner's own frame as Core Graphics does, in one stretch of code
 *              from the current point to the arc's last curve.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

import CoreGraphics

extension DiagramPathLaneState {
    /// The arc of `radius` tangent to the line from the current point, `currentPoint` on the page, to `corner` and to the
    /// line from `corner` to `next`, joined to the current point by a line, in the space `transform` takes to the page,
    /// whose determinant (`DiagramPathArithmetic.determinant(of:)`) the caller works out once for the four corners of a
    /// rectangle; gives the last point written, the current point after it. The lane holds elements and no shape whole (a
    /// rounded rectangle's move comes first), so that Core Graphics' `add_arc` and `add_arc_relative` take the same
    /// branches for every corner, which this follows without asking again: no whole turn held as an ellipse, no arc held
    /// whole, a line to the arc's start; and its elements are written without asking whether a held shape is to be made
    /// into elements first. Every operation is Core Graphics' own, in its order.
    @inline(__always)
    mutating func appendTangentArc(from currentPoint: CGPoint, corner: CGPoint, next: CGPoint, radius: CGFloat, transform: CGAffineTransform,
                                   determinant: CGFloat) -> CGPoint {
        let current = DiagramPathArithmetic.point(currentPoint, inverselyTransformedBy: transform, determinant: determinant)
        let towardCorner = CGPoint(x: corner.x - current.x, y: corner.y - current.y)
        let towardNext = CGPoint(x: next.x - current.x, y: next.y - current.y)
        let isAtCorner = towardCorner.x == 0 && towardCorner.y == 0
        let rawAngle = DiagramPathArithmetic.angle(across: towardCorner.x, down: towardCorner.y)
        let angle = isAtCorner ? 0 : rawAngle
        let turn = DiagramPathArithmetic.sineAndCosine(of: angle)
        // The corner and the next point in the frame of the first line: along it, and across it.
        let frame = DiagramPathTangentArcFrame(
            cornerAlong: (towardCorner.y * turn.sine).addingProduct(turn.cosine, towardCorner.x),
            cornerAcross: (towardCorner.y * turn.cosine).addingProduct(-turn.sine, towardCorner.x),
            nextAlong: (towardNext.y * turn.sine).addingProduct(turn.cosine, towardNext.x),
            nextAcross: (towardNext.y * turn.cosine).addingProduct(-turn.sine, towardNext.x))
        let placement = frame.placement(radius: isAtCorner ? 0 : radius)
        let center = CGPoint(x: current.x + ((placement.across * -turn.sine).addingProduct(turn.cosine, placement.distance) + 0),
                             y: current.y + ((placement.across * turn.cosine).addingProduct(turn.sine, placement.distance) + 0))
        return appendArcAfterElements(center: center, radius: placement.radius, startAngle: angle + placement.startOffset,
                                      endAngle: angle + placement.endOffset, isClockwise: frame.turnsClockwise, transform: transform)
    }

    /// `appendArcBetweenAngles` for a lane that holds elements and a transform: the end moved by whole turns past the
    /// start in the arc's direction, then a line from the current point to the arc's start, a curve per quarter turn and
    /// one for what is left (`appendRelativeArc` without its branches for an empty lane); gives the last point written.
    @inline(__always)
    private mutating func appendArcAfterElements(center: CGPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, isClockwise: Bool,
                                                 transform: CGAffineTransform) -> CGPoint {
        var start = startAngle
        var end = endAngle
        if isClockwise {
            if start < end { start = start.addingProduct(((start - end) / -Self.fullTurn).rounded(.up), Self.fullTurn) }
        } else if end < start {
            end = end.addingProduct(((end - start) / -Self.fullTurn).rounded(.up), Self.fullTurn)
        }
        let sweep = end - start
        let startTurn = DiagramPathArithmetic.sineAndCosine(of: start)
        var radial = CGPoint(x: startTurn.cosine * radius, y: startTurn.sine * radius)
        var arcPoint = CGPoint(x: radial.x + center.x, y: radial.y + center.y)
        var written = appendElementLine(to: arcPoint, transform: transform)
        let turnsForward = sweep >= 0
        let quarterTurn = turnsForward ? DiagramPathArithmetic.halfPi : -DiagramPathArithmetic.halfPi
        let control = turnsForward ? DiagramPathArithmetic.quarterTurnControlDistance : -DiagramPathArithmetic.quarterTurnControlDistance
        var remaining = sweep
        var angle = start
        var remainingMagnitude = abs(sweep)
        while remainingMagnitude >= DiagramPathArithmetic.halfPi {
            let nextRadial = turnsForward ? CGPoint(x: -radial.y, y: radial.x) : CGPoint(x: radial.y, y: -radial.x)
            let control1 = CGPoint(x: arcPoint.x.addingProduct(-control, radial.y), y: arcPoint.y.addingProduct(control, radial.x))
            let quarterEnd = CGPoint(x: nextRadial.x + center.x, y: nextRadial.y + center.y)
            let control2 = CGPoint(x: quarterEnd.x.addingProduct(control, nextRadial.y), y: quarterEnd.y.addingProduct(-control, nextRadial.x))
            written = appendElementCurve(control1, control2, quarterEnd, transform: transform)
            angle = quarterTurn + angle
            remainingMagnitude = abs(remaining - quarterTurn)
            remaining = remaining - quarterTurn
            arcPoint = quarterEnd
            radial = nextRadial
        }
        guard !(remainingMagnitude <= Self.smallestDrawnSweep) else { return written }
        return appendElementArcRest(center: center, radius: radius, from: arcPoint, radial: radial, angle: angle, sweep: remaining, transform: transform)
    }

    /// `appendArcRest` on a lane of elements: the last curve of an arc, through what is left of its sweep after its
    /// quarter turns; gives its end on the page.
    @inline(__always)
    private mutating func appendElementArcRest(center: CGPoint, radius: CGFloat, from current: CGPoint, radial: CGPoint, angle: CGFloat,
                                               sweep: CGFloat, transform: CGAffineTransform) -> CGPoint {
        let half = DiagramPathArithmetic.sineAndCosine(of: sweep * 0.5)
        let control = ((1 - half.cosine) * 4) / (half.sine * 3)
        let endAngle = DiagramPathArithmetic.sineAndCosine(of: sweep + angle)
        let radialEnd = CGPoint(x: radius * endAngle.cosine, y: radius * endAngle.sine)
        let control1 = CGPoint(x: current.x.addingProduct(-control, radial.y), y: current.y.addingProduct(control, radial.x))
        let end = CGPoint(x: radialEnd.x + center.x, y: radialEnd.y + center.y)
        let control2 = CGPoint(x: end.x.addingProduct(control, radialEnd.y), y: end.y.addingProduct(-control, radialEnd.x))
        return appendElementCurve(control1, control2, end, transform: transform)
    }

    /// A line through `transform` after the lane's elements, which hold no shape whole, as `appendLine` adds it; gives
    /// the point written.
    @inline(__always)
    private mutating func appendElementLine(to point: CGPoint, transform: CGAffineTransform) -> CGPoint {
        let written = DiagramPathArithmetic.point(point, transformedBy: transform)
        appendElement(.line, written)
        return written
    }

    /// A cubic curve through `transform` after the lane's elements, which hold no shape whole, as `appendCurve` adds it;
    /// gives its end as written.
    @inline(__always)
    private mutating func appendElementCurve(_ control1: CGPoint, _ control2: CGPoint, _ end: CGPoint, transform: CGAffineTransform) -> CGPoint {
        let written = DiagramPathArithmetic.point(end, transformedBy: transform)
        appendElement(DiagramPathArithmetic.point(control1, transformedBy: transform), DiagramPathArithmetic.point(control2, transformedBy: transform),
                      written)
        return written
    }
}

/// A tangent arc's corner and next point in the frame of its first line, as Core Graphics works them out (each a fused
/// sum, not yet rounded through `+ 0`).
private struct DiagramPathTangentArcFrame {
    let cornerAlong: CGFloat
    let cornerAcross: CGFloat
    let nextAlong: CGFloat
    let nextAcross: CGFloat

    /// Whether the second line turns clockwise from the first, on a page whose y runs up.
    var turnsClockwise: Bool {
        nextAcross <= cornerAcross
    }

    /// Where the arc's center lies along and across the first line, its radius, and its angles from the first line's.
    @inline(__always)
    func placement(radius: CGFloat) -> (distance: CGFloat, across: CGFloat, radius: CGFloat, startOffset: CGFloat, endOffset: CGFloat) {
        let along = cornerAlong + 0
        let acrossCorner = cornerAcross + 0
        var cornerAngle: CGFloat = 0
        if !(cornerAlong == nextAlong && cornerAcross == nextAcross) {
            let secondLine = DiagramPathArithmetic.angle(across: (nextAlong + 0) - along, down: (nextAcross + 0) - acrossCorner)
            cornerAngle = CGFloat.pi - abs(secondLine)
        }
        let halfSine = DiagramPathArithmetic.sine(of: cornerAngle * 0.5)
        guard halfSine != 0 else { return (along, acrossCorner, 0, 0, 0) }
        let cotangent = abs(DiagramPathArithmetic.cosine(of: cornerAngle * 0.5) / halfSine)
        let distance = along.addingProduct(-radius, cotangent)
        guard turnsClockwise else { return (distance, radius, radius, -DiagramPathArithmetic.halfPi, DiagramPathArithmetic.halfPi - cornerAngle) }
        return (distance, -radius, radius, DiagramPathArithmetic.halfPi, cornerAngle + -DiagramPathArithmetic.halfPi)
    }
}
