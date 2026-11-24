/**
 * File: DiagramPathPrimitive.swift
 * --------------------------------
 * Layer: Core
 * Description: The one rectangle, rounded rectangle, ellipse or arc a path lane holds whole when it was added to an empty
 *              lane, as Core Graphics holds it: the transform of the unit square or circle to the shape, its elements made
 *              only when they are read or the lane grows, its bounds taken from the transform.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
import Darwin

/// A shape held whole, as Core Graphics keeps one shape added to an empty path: what it is and the transform of the unit
/// square (a rectangle, a rounded rectangle, an ellipse) or of the unit circle's arc from angle 0 (an arc) to it.
struct DiagramPathPrimitive: Sendable, Equatable {
    enum Shape: Sendable, Equatable {
        case rectangle
        /// Its corners' radii as fractions of its sides.
        case roundedRectangle(unitRadii: CGSize)
        case ellipse(closes: Bool, isClockwise: Bool)
        /// An arc of the circle of radius 1 from angle 0, turned through the size of `sweep` (the transform mirrors one
        /// with decreasing angle).
        case arc(sweep: CGFloat)
    }

    var shape: Shape
    var transform: CGAffineTransform
    /// For an arc of a whole turn or more, the call that added it: Core Graphics bounds such an arc by a rule of its own,
    /// so its bounds are asked of Core Graphics itself, only when they are read (no diagram draws one).
    var wholeTurnArc: DiagramPathWholeTurnArc?

    init(shape: Shape, transform: CGAffineTransform, wholeTurnArc: DiagramPathWholeTurnArc? = nil) {
        self.shape = shape
        self.transform = transform
        self.wholeTurnArc = wholeTurnArc
    }

    /// Appends the shape's elements to `state` as Core Graphics makes them from what it holds: the form it bounds and
    /// adds to other paths (`writtenLastCurve` is the form it gives out). The first is a move, which replaces a move
    /// `state` ends with, as Core Graphics adds a held shape after other elements.
    func appendElements(to state: inout DiagramPathLaneState) {
        switch shape {
        case .rectangle:
            state.appendMove(to: .zero, transform: transform)
            state.appendLine(to: CGPoint(x: 1, y: 0), transform: transform)
            state.appendLine(to: CGPoint(x: 1, y: 1), transform: transform)
            state.appendLine(to: CGPoint(x: 0, y: 1), transform: transform)
            state.closeElements()
        case .roundedRectangle(let unitRadii):
            state.appendRoundedRectangle(origin: .zero, size: CGSize(width: 1, height: 1), radii: unitRadii, transform: transform)
        case .ellipse(let closes, let isClockwise):
            state.appendEllipseElements(CGRect(x: 0, y: 0, width: 1, height: 1), closes: closes, isClockwise: isClockwise, transform: transform)
        case .arc(let sweep):
            state.appendRelativeArc(center: .zero, radius: 1, startAngle: 0, sweep: abs(sweep), transform: transform, startsWithMove: true,
                                    mayHoldWhole: false)
        }
    }

    /// The most elements and points `appendElements` appends: an arc of two and a half turns has a move, ten quarter
    /// curves and one for the rest.
    static let largestElementCount = 12
    static let largestPointCount = 34

    /// The last curve of a held arc as Core Graphics gives it out (`CGPathApply`), which it works out from the arc's
    /// stored sine, cosine and tangent rather than as it adds the arc to a path: from the unit radius after the quarter
    /// turns to the point at the cosine and the sine of the sweep, its control distance `tan(rest / 4) · 4 / 3`; nil for
    /// any other shape, and when the quarter turns end the arc. The cosine is taken of the sweep itself, the sine of its
    /// size, as Core Graphics stores them.
    var writtenLastCurve: (control1: CGPoint, control2: CGPoint, end: CGPoint)? {
        guard case .arc(let sweep) = shape else { return nil }
        var radial = CGPoint(x: 1, y: 0)
        var rest = abs(sweep)
        while rest >= DiagramPathArithmetic.halfPi {
            radial = CGPoint(x: -radial.y, y: radial.x)
            rest = rest + -DiagramPathArithmetic.halfPi
        }
        guard !(rest <= DiagramPathLaneState.smallestDrawnSweep) else { return nil }
        let control = tan(rest * 0.25) * 1.3333333333333333
        let endCosine = cos(sweep)
        let endSine = sin(abs(sweep))
        let control1 = CGPoint(x: radial.x.addingProduct(-control, radial.y), y: radial.y.addingProduct(control, radial.x))
        let control2 = CGPoint(x: endCosine.addingProduct(control, endSine), y: endSine.addingProduct(-control, endCosine))
        return (DiagramPathArithmetic.point(control1, transformedBy: transform), DiagramPathArithmetic.point(control2, transformedBy: transform),
                DiagramPathArithmetic.point(CGPoint(x: endCosine, y: endSine), transformedBy: transform))
    }

    /// The current point of a lane holding the shape, as Core Graphics works it out from the transform rather than from
    /// the elements: a rectangle's first corner, a rounded rectangle's and an ellipse's middle of the right side, an arc's
    /// end at the cosine of the sweep and the sine of its size.
    var currentPoint: CGPoint {
        switch shape {
        case .rectangle: return DiagramPathArithmetic.point(.zero, transformedBy: transform)
        case .roundedRectangle, .ellipse: return DiagramPathArithmetic.point(CGPoint(x: 1, y: 0.5), transformedBy: transform)
        case .arc(let sweep): return DiagramPathArithmetic.point(CGPoint(x: cos(sweep), y: sin(abs(sweep))), transformedBy: transform)
        }
    }

    /// The bounds Core Graphics gives a held shape without its elements: a rectangle's always, a rounded rectangle's and
    /// an ellipse's when their transform keeps the axes, an arc's of a whole turn or more by asking Core Graphics; nil
    /// when they come from the elements.
    var bounds: CGRect? {
        switch shape {
        case .rectangle: return unitSquareBounds
        case .roundedRectangle, .ellipse:
            let keepsAxes = (transform.b == 0 && transform.c == 0) || (transform.a == 0 && transform.d == 0)
            return keepsAxes ? unitSquareBounds : nil
        case .arc: return wholeTurnArc?.coreGraphicsBounds
        }
    }

    /// The bounds of the unit square through the transform (Core Graphics' `transform_unit_rect`).
    private var unitSquareBounds: CGRect {
        let keepsAxes = transform.b == 0 && transform.c == 0
        let across = Self.range(transform.a, transform.c, transform.a + transform.c, keepsAxes: keepsAxes, single: transform.a)
        let down = Self.range(transform.b, transform.d, transform.b + transform.d, keepsAxes: keepsAxes, single: transform.d)
        return CGRect(x: across.lowest + transform.tx, y: down.lowest + transform.ty, width: across.highest - across.lowest,
                      height: down.highest - down.lowest)
    }

    /// The least and greatest of 0 and the three values, or of 0 and `single` when the transform keeps the axes.
    private static func range(_ first: CGFloat, _ second: CGFloat, _ third: CGFloat, keepsAxes: Bool,
                              single: CGFloat) -> (lowest: CGFloat, highest: CGFloat) {
        if keepsAxes { return (DiagramPathArithmetic.minimum(single, 0), DiagramPathArithmetic.maximum(single, 0)) }
        var lowest: CGFloat = 0
        var highest: CGFloat = 0
        if first < lowest { lowest = first }
        if highest < first { highest = first }
        if second < lowest { lowest = second }
        if highest < second { highest = second }
        if third < lowest { lowest = third }
        if highest < third { highest = third }
        return (lowest, highest)
    }
}

/// The call that added an arc of a whole turn or more to an empty lane, kept so that its bounds, which Core Graphics works
/// out by a rule of its own, are Core Graphics' own.
struct DiagramPathWholeTurnArc: Sendable, Equatable {
    let center: CGPoint
    let radius: CGFloat
    let startAngle: CGFloat
    let sweep: CGFloat
    let transform: CGAffineTransform?

    /// The bounds Core Graphics gives the same arc added to an empty path.
    var coreGraphicsBounds: CGRect {
        let reference = CGMutablePath()
        reference.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: startAngle + sweep, clockwise: sweep < 0,
                         transform: transform ?? .identity)
        return reference.boundingBoxOfPath
    }
}
