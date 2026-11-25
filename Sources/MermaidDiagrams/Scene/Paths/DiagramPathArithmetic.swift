/**
 * File: DiagramPathArithmetic.swift
 * ---------------------------------
 * Layer: Core
 * Description: The arithmetic Core Graphics' paths do on their points, step by step and with its fused multiply-adds:
 *              transforming a point, joining two transforms, undoing a transform, and the sines it takes.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

import CoreGraphics
import Darwin

/// Core Graphics' own arithmetic on a path's points, written out so that a path lane's elements are Core Graphics' to the
/// last bit: every product added to another is one fused multiply-add where Core Graphics' code has one, in its order.
enum DiagramPathArithmetic {
    /// `point` through `transform`: `tx + (a·x + c·y)` and `ty + (b·x + d·y)`, each sum in parentheses one fused step.
    @inline(__always)
    static func point(_ point: CGPoint, transformedBy transform: CGAffineTransform) -> CGPoint {
        CGPoint(x: transform.tx + (transform.c * point.y).addingProduct(transform.a, point.x),
                y: transform.ty + (transform.d * point.y).addingProduct(transform.b, point.x))
    }

    /// `point` through `transform` when there is one, else `point`.
    @inline(__always)
    static func point(_ point: CGPoint, transformedBy transform: CGAffineTransform?) -> CGPoint {
        guard let transform else { return point }
        return self.point(point, transformedBy: transform)
    }

    /// `first` and then `second`, as Core Graphics joins a shape's own transform with the one a caller gives.
    static func concatenation(_ first: CGAffineTransform, then second: CGAffineTransform) -> CGAffineTransform {
        CGAffineTransform(a: (second.c * first.b).addingProduct(second.a, first.a),
                          b: (second.d * first.b).addingProduct(second.b, first.a),
                          c: (second.c * first.d).addingProduct(second.a, first.c),
                          d: (second.d * first.d).addingProduct(second.b, first.c),
                          tx: second.tx + (second.c * first.ty).addingProduct(second.a, first.tx),
                          ty: second.ty + (second.d * first.ty).addingProduct(second.b, first.tx))
    }

    /// `point` taken back through `transform` (`CGPointApplyInverseAffineTransform`); unchanged for a transform that
    /// cannot be undone.
    static func point(_ point: CGPoint, inverselyTransformedBy transform: CGAffineTransform) -> CGPoint {
        self.point(point, inverselyTransformedBy: transform, determinant: determinant(of: transform))
    }

    /// `point` taken back through `transform`, whose determinant (`determinant(of:)`) is worked out once for several
    /// points.
    @inline(__always)
    static func point(_ point: CGPoint, inverselyTransformedBy transform: CGAffineTransform, determinant: CGFloat) -> CGPoint {
        guard determinant != 0 else { return point }
        let across = point.x - transform.tx
        let down = point.y - transform.ty
        return CGPoint(x: (-(down * transform.c)).addingProduct(transform.d, across) / determinant,
                       y: (-(across * transform.b)).addingProduct(transform.a, down) / determinant)
    }

    /// `a·d - c·b`, as `CGPointApplyInverseAffineTransform` works it out.
    @inline(__always)
    static func determinant(of transform: CGAffineTransform) -> CGFloat {
        (-(transform.c * transform.b)).addingProduct(transform.a, transform.d)
    }

    /// The sine and cosine of `angle` as the system's `__sincos_stret` gives them, which Core Graphics calls; the angles
    /// of a rounded rectangle's corners are looked up, their values taken from the same function once.
    @inline(__always)
    static func sineAndCosine(of angle: CGFloat) -> (sine: CGFloat, cosine: CGFloat) {
        if angle == 0, angle.sign == .plus { return (0, 1) }
        if angle == halfPi { return halfPiValues }
        if angle == 3.141592653589793 { return piValues }
        if angle == -halfPi { return negativeHalfPiValues }
        if angle == -3.141592653589793 { return negativePiValues }
        let values = __sincos_stret(angle)
        return (values.__sinval, values.__cosval)
    }

    /// `sin(angle)`, which Core Graphics calls for half a tangent arc's corner.
    @inline(__always)
    static func sine(of angle: CGFloat) -> CGFloat {
        angle == quarterPi ? quarterPiSine : sin(angle)
    }

    /// `cos(angle)`.
    @inline(__always)
    static func cosine(of angle: CGFloat) -> CGFloat {
        angle == quarterPi ? quarterPiCosine : cos(angle)
    }

    /// The angle of the vector (`across`, `down`), as `atan2` gives it; along an axis, its exact value (C's Annex F).
    @inline(__always)
    static func angle(across: CGFloat, down: CGFloat) -> CGFloat {
        if across == 0, !down.isNaN, down != 0 { return down > 0 ? halfPi : -halfPi }
        if down == 0, !across.isNaN, across != 0 {
            if across > 0 { return down.sign == .plus ? 0 : -0.0 }
            return down.sign == .plus ? 3.141592653589793 : -3.141592653589793
        }
        return atan2(down, across)
    }

    /// π / 2 as a double, the angle `atan2` gives straight down the y axis.
    static let halfPi: CGFloat = 1.5707963267948966
    /// `__sincos_stret` of π / 2, π, -π / 2 and -π, and `sin` and `cos` of π / 4, as the system gives them
    /// (`DiagramPathLaneEquivalenceTests` checks each against the functions).
    static let halfPiValues: (sine: CGFloat, cosine: CGFloat) = (1, 6.123233995736766e-17)
    static let piValues: (sine: CGFloat, cosine: CGFloat) = (1.2246467991473532e-16, -1)
    static let negativeHalfPiValues: (sine: CGFloat, cosine: CGFloat) = (-1, 6.123233995736766e-17)
    static let negativePiValues: (sine: CGFloat, cosine: CGFloat) = (-1.2246467991473532e-16, -1)
    static let quarterPi: CGFloat = 0.7853981633974483
    static let quarterPiSine: CGFloat = 0.7071067811865475
    static let quarterPiCosine: CGFloat = 0.7071067811865476

    /// Core Graphics' distance along the tangent of a quarter circle of radius 1 to its control points.
    static let quarterTurnControlDistance: CGFloat = 0.5522847498

    /// The fused minimum of two numbers (`fminnm`): a number beats NaN, and -0 is less than 0.
    @inline(__always)
    static func minimum(_ first: CGFloat, _ second: CGFloat) -> CGFloat {
        if first.isNaN { return second }
        if second.isNaN { return first }
        if first == second { return first.sign == .minus ? first : second }
        return first < second ? first : second
    }

    /// The fused maximum of two numbers (`fmaxnm`): a number beats NaN, and 0 is more than -0.
    @inline(__always)
    static func maximum(_ first: CGFloat, _ second: CGFloat) -> CGFloat {
        if first.isNaN { return second }
        if second.isNaN { return first }
        if first == second { return first.sign == .minus ? second : first }
        return first > second ? first : second
    }
}
