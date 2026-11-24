/**
 * File: DiagramScenePathArcs.swift
 * --------------------------------
 * Layer: Core
 * Description: Arcs of circles as Core Graphics adds them to a path: whole quarter turns as cubic curves with its fixed
 *              control distance, the rest as one curve, tangent arcs between two lines, and an arc held whole.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import CoreGraphics
import Darwin

extension DiagramScenePath {
    /// The arc of the circle about `center` from `startAngle` to `endAngle`, clockwise on a page whose y runs up when
    /// `clockwise` (`CGPathAddArc`); a line joins it to the current point, if there is one.
    mutating func addArc(center: CGPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, clockwise: Bool,
                         transform: CGAffineTransform? = nil) {
        guard center.x.isFinite, center.y.isFinite, abs(startAngle) <= Self.largestArcAngle, abs(endAngle) <= Self.largestArcAngle else { return }
        appendArcBetweenAngles(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, isClockwise: clockwise, transform: transform)
    }

    /// The largest angle Core Graphics takes for an arc's end.
    private static let largestArcAngle: CGFloat = 1e7

    private static let fullTurn: CGFloat = 6.283185307179586
    /// The most an arc may differ from a whole turn and be drawn as an ellipse.
    private static let wholeTurnTolerance: CGFloat = 9.9999999999999995E-7

    /// Core Graphics' `add_arc`: a whole turn from angle 0 into an empty path as an ellipse; else the arc's end moved by
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

    /// The largest sweep Core Graphics holds whole as one arc in an empty path: two and a half turns.
    private static let largestHeldSweep: CGFloat = 7.8539816339744828
    /// The smallest rest of a sweep after its quarter turns that Core Graphics draws.
    private static let smallestDrawnSweep: CGFloat = 1.0E-8

    /// Core Graphics' `add_arc_relative`: from the point at `startAngle`, joined by a line to the current point unless
    /// `startsWithMove` or the path is empty, a curve per quarter turn and one for what is left. Into an empty path, an arc
    /// of at most two and a half turns is held whole: the unit circle's arc from angle 0 through its transform.
    mutating func appendRelativeArc(center: CGPoint, radius: CGFloat, startAngle: CGFloat, sweep: CGFloat, transform: CGAffineTransform?,
                                    startsWithMove: Bool, mayHoldWhole: Bool = true) {
        if mayHoldWhole, isEmpty, abs(sweep) <= Self.largestHeldSweep {
            return appendHeldArc(center: center, radius: radius, startAngle: startAngle, sweep: sweep, transform: transform)
        }
        let start = DiagramScenePathArithmetic.sineAndCosine(of: startAngle)
        var radial = CGPoint(x: start.cosine * radius, y: start.sine * radius)
        var current = CGPoint(x: radial.x + center.x, y: radial.y + center.y)
        if startsWithMove || isEmpty {
            appendMove(to: current, transform: transform)
        } else {
            appendLine(to: current, transform: transform)
        }
        let turnsForward = sweep >= 0
        let quarterTurn = turnsForward ? DiagramScenePathArithmetic.halfPi : -DiagramScenePathArithmetic.halfPi
        let control = turnsForward ? DiagramScenePathArithmetic.quarterTurnControlDistance : -DiagramScenePathArithmetic.quarterTurnControlDistance
        var remaining = sweep
        var angle = startAngle
        var remainingMagnitude = abs(sweep)
        while remainingMagnitude >= DiagramScenePathArithmetic.halfPi {
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
    private mutating func appendArcRest(center: CGPoint, radius: CGFloat, from current: CGPoint, radial: CGPoint, angle: CGFloat, sweep: CGFloat,
                                        transform: CGAffineTransform?) {
        let half = DiagramScenePathArithmetic.sineAndCosine(of: sweep * 0.5)
        let control = ((1 - half.cosine) * 4) / (half.sine * 3)
        let endAngle = DiagramScenePathArithmetic.sineAndCosine(of: sweep + angle)
        let radialEnd = CGPoint(x: radius * endAngle.cosine, y: radius * endAngle.sine)
        let control1 = CGPoint(x: current.x.addingProduct(-control, radial.y), y: current.y.addingProduct(control, radial.x))
        let end = CGPoint(x: radialEnd.x + center.x, y: radialEnd.y + center.y)
        let control2 = CGPoint(x: end.x.addingProduct(control, radialEnd.y), y: end.y.addingProduct(-control, radialEnd.x))
        appendCurve(control1, control2, end, transform: transform)
    }

    /// An arc held whole in an empty path: its transform takes the unit circle's arc from angle 0 to it, a sweep with
    /// decreasing angle mirrored.
    private mutating func appendHeldArc(center: CGPoint, radius: CGFloat, startAngle: CGFloat, sweep: CGFloat, transform: CGAffineTransform?) {
        let start = DiagramScenePathArithmetic.sineAndCosine(of: startAngle)
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
        if let transform { arc = DiagramScenePathArithmetic.concatenation(arc, then: transform) }
        let sweepMagnitude = abs(sweep)
        var bounds: DiagramScenePathPrimitive.WholeTurnBounds?
        if sweepMagnitude >= Self.fullTurn {
            let reference = CGMutablePath()
            reference.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: startAngle + sweep, clockwise: sweep < 0,
                             transform: transform ?? .identity)
            bounds = DiagramScenePathPrimitive.WholeTurnBounds(reference.boundingBoxOfPath)
        }
        self = DiagramScenePath(holding: DiagramScenePathPrimitive(shape: .arc(sweep: sweep, wholeTurnBounds: bounds), transform: arc))
    }

    /// The last curve of an arc held whole as Core Graphics gives it out (`CGPathApply`), which it works out from the
    /// arc's stored sine, cosine and tangent rather than as it adds the arc to a path: from the unit radius after the
    /// quarter turns to the point at the cosine and the sine of the sweep, its control distance `tan(rest / 4) · 4 / 3`;
    /// nil when the quarter turns end the arc. The cosine is taken of the sweep itself, the sine of its size, as Core
    /// Graphics stores them.
    static func writtenLastCurve(sweep: CGFloat, transform: CGAffineTransform) -> [CGPoint]? {
        var radial = CGPoint(x: 1, y: 0)
        var rest = abs(sweep)
        while rest >= DiagramScenePathArithmetic.halfPi {
            radial = CGPoint(x: -radial.y, y: radial.x)
            rest = rest + -DiagramScenePathArithmetic.halfPi
        }
        guard !(rest <= smallestDrawnSweep) else { return nil }
        let control = tan(rest * 0.25) * 1.3333333333333333
        let endCosine = cos(sweep)
        let endSine = sin(abs(sweep))
        let unitPoints = [CGPoint(x: radial.x.addingProduct(-control, radial.y), y: radial.y.addingProduct(control, radial.x)),
                          CGPoint(x: endCosine.addingProduct(control, endSine), y: endSine.addingProduct(-control, endCosine)),
                          CGPoint(x: endCosine, y: endSine)]
        return unitPoints.map { point in DiagramScenePathArithmetic.point(point, transformedBy: transform) }
    }
}
