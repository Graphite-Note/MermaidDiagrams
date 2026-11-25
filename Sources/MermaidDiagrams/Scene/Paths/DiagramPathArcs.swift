/**
 * File: DiagramPathArcs.swift
 * ---------------------------
 * Layer: Core
 * Description: Arcs of circles as Core Graphics adds them to a path: whole quarter turns as cubic curves with its fixed
 *              control distance, the rest as one curve, and an arc held whole in an empty lane.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

import CoreGraphics

extension DiagramPathLaneState {
    /// The arc of the circle about `center` from `startAngle` to `endAngle`, clockwise on a page whose y runs up when
    /// `clockwise` (`CGPathAddArc`); a line joins it to the current point, if there is one.
    mutating func addArc(center: CGPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, clockwise: Bool, transform: CGAffineTransform?) {
        guard center.x.isFinite, center.y.isFinite, abs(startAngle) <= Self.largestArcAngle, abs(endAngle) <= Self.largestArcAngle else { return }
        appendArcBetweenAngles(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, isClockwise: clockwise, transform: transform)
    }

    /// The largest angle Core Graphics takes for an arc's end.
    private static let largestArcAngle: CGFloat = 1e7
    static let fullTurn: CGFloat = 6.283185307179586
    /// The most an arc may differ from a whole turn and be drawn as an ellipse.
    private static let wholeTurnTolerance: CGFloat = 9.9999999999999995E-7
    /// The largest sweep Core Graphics holds whole as one arc in an empty path: two and a half turns.
    private static let largestHeldSweep: CGFloat = 7.8539816339744828
    /// The smallest rest of a sweep after its quarter turns that Core Graphics draws.
    static let smallestDrawnSweep: CGFloat = 1.0E-8

    /// Core Graphics' `add_arc`: a whole turn from angle 0 into an empty lane as an ellipse; else the arc's end moved by
    /// whole turns until it lies past its start in its direction.
    mutating func appendArcBetweenAngles(center: CGPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, isClockwise: Bool,
                                         transform: CGAffineTransform?) {
        if isEmpty {
            let pastWholeTurn = endAngle + -Self.fullTurn
            let isWholeClockwiseTurn = isClockwise && startAngle == 0 && !(endAngle < Self.fullTurn) && pastWholeTurn < Self.wholeTurnTolerance
            let isWholeTurn = !isClockwise && startAngle == 0 && abs(pastWholeTurn) < Self.wholeTurnTolerance
            if isWholeClockwiseTurn || isWholeTurn {
                let diameter = radius + radius
                let rect = CGRect(x: center.x - radius, y: center.y - radius, width: diameter, height: diameter)
                return appendEllipse(rect, closes: false, isClockwise: isClockwise, transform: transform)
            }
        }
        var start = startAngle
        var end = endAngle
        if isClockwise {
            if start < end { start = start.addingProduct(((start - end) / -Self.fullTurn).rounded(.up), Self.fullTurn) }
        } else if end < start {
            end = end.addingProduct(((end - start) / -Self.fullTurn).rounded(.up), Self.fullTurn)
        }
        appendRelativeArc(center: center, radius: radius, startAngle: start, sweep: end - start, transform: transform, startsWithMove: false)
    }

    /// Core Graphics' `add_arc_relative`: from the point at `startAngle`, joined by a line to the current point unless
    /// `startsWithMove` or the lane is empty, a curve per quarter turn and one for what is left. Into an empty lane, an arc
    /// of at most two and a half turns is held whole: the unit circle's arc from angle 0 through its transform.
    mutating func appendRelativeArc(center: CGPoint, radius: CGFloat, startAngle: CGFloat, sweep: CGFloat, transform: CGAffineTransform?,
                                    startsWithMove: Bool, mayHoldWhole: Bool = true) {
        if mayHoldWhole, isEmpty, abs(sweep) <= Self.largestHeldSweep {
            return appendHeldArc(center: center, radius: radius, startAngle: startAngle, sweep: sweep, transform: transform)
        }
        let start = DiagramPathArithmetic.sineAndCosine(of: startAngle)
        var radial = CGPoint(x: start.cosine * radius, y: start.sine * radius)
        var current = CGPoint(x: radial.x + center.x, y: radial.y + center.y)
        if startsWithMove || isEmpty {
            appendMove(to: current, transform: transform)
        } else {
            appendLine(to: current, transform: transform)
        }
        let turnsForward = sweep >= 0
        let quarterTurn = turnsForward ? DiagramPathArithmetic.halfPi : -DiagramPathArithmetic.halfPi
        let control = turnsForward ? DiagramPathArithmetic.quarterTurnControlDistance : -DiagramPathArithmetic.quarterTurnControlDistance
        var remaining = sweep
        var angle = startAngle
        var remainingMagnitude = abs(sweep)
        while remainingMagnitude >= DiagramPathArithmetic.halfPi {
            let next = turnsForward ? CGPoint(x: -radial.y, y: radial.x) : CGPoint(x: radial.y, y: -radial.x)
            let control1 = CGPoint(x: current.x.addingProduct(-control, radial.y), y: current.y.addingProduct(control, radial.x))
            let end = CGPoint(x: next.x + center.x, y: next.y + center.y)
            let control2 = CGPoint(x: end.x.addingProduct(control, next.y), y: end.y.addingProduct(-control, next.x))
            appendCurve(control1, control2, end, transform: transform)
            angle = quarterTurn + angle
            remainingMagnitude = abs(remaining - quarterTurn)
            remaining = remaining - quarterTurn
            current = end
            radial = next
        }
        guard !(remainingMagnitude <= Self.smallestDrawnSweep) else { return }
        appendArcRest(center: center, radius: radius, from: current, radial: radial, angle: angle, sweep: remaining, transform: transform)
    }

    /// The last curve of an arc, through what is left of its sweep after its quarter turns.
    @inline(__always)
    mutating func appendArcRest(center: CGPoint, radius: CGFloat, from current: CGPoint, radial: CGPoint, angle: CGFloat, sweep: CGFloat,
                                        transform: CGAffineTransform?) {
        let half = DiagramPathArithmetic.sineAndCosine(of: sweep * 0.5)
        let control = ((1 - half.cosine) * 4) / (half.sine * 3)
        let endAngle = DiagramPathArithmetic.sineAndCosine(of: sweep + angle)
        let radialEnd = CGPoint(x: radius * endAngle.cosine, y: radius * endAngle.sine)
        let control1 = CGPoint(x: current.x.addingProduct(-control, radial.y), y: current.y.addingProduct(control, radial.x))
        let end = CGPoint(x: radialEnd.x + center.x, y: radialEnd.y + center.y)
        let control2 = CGPoint(x: end.x.addingProduct(control, radialEnd.y), y: end.y.addingProduct(-control, radialEnd.x))
        appendCurve(control1, control2, end, transform: transform)
    }

    /// An arc held whole in an empty lane: its transform takes the unit circle's arc from angle 0 to it, a sweep with
    /// decreasing angle mirrored.
    private mutating func appendHeldArc(center: CGPoint, radius: CGFloat, startAngle: CGFloat, sweep: CGFloat, transform: CGAffineTransform?) {
        let start = DiagramPathArithmetic.sineAndCosine(of: startAngle)
        let across = CGPoint(x: radius, y: 0)
        let down = CGPoint(x: 0, y: radius)
        var arc = CGAffineTransform(a: (down.x * start.sine).addingProduct(across.x, start.cosine),
                                    b: (down.y * start.sine).addingProduct(across.y, start.cosine),
                                    c: (down.x * start.cosine).addingProduct(-across.x, start.sine),
                                    d: (down.y * start.cosine).addingProduct(-across.y, start.sine),
                                    tx: center.x + (0 * down.x).addingProduct(0, across.x), ty: center.y + (0 * down.y).addingProduct(0, across.y))
        if sweep < 0 {
            arc.c = -arc.c
            arc.d = -arc.d
        }
        if let transform { arc = DiagramPathArithmetic.concatenation(arc, then: transform) }
        let wholeTurnArc = abs(sweep) >= Self.fullTurn
            ? DiagramPathWholeTurnArc(center: center, radius: radius, startAngle: startAngle, sweep: sweep, transform: transform) : nil
        hold(DiagramPathPrimitive(shape: .arc(sweep: sweep), transform: arc, wholeTurnArc: wholeTurnArc))
    }
}
