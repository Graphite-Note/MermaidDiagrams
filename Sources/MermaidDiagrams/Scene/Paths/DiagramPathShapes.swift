/**
 * File: DiagramPathShapes.swift
 * -----------------------------
 * Layer: Core
 * Description: The rectangles, rounded rectangles and ellipses a path lane adds, built by Core Graphics' own
 *              construction, and held whole as Core Graphics holds one such shape added to an empty path.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

import CoreGraphics

extension DiagramPathLaneState {
    /// A rectangle, from its smaller corner: a move, three lines and a close (`CGPathAddRect`).
    mutating func addRect(_ rect: CGRect) {
        let standard = Self.standardized(rect)
        appendRectangle(origin: standard.origin, size: standard.size)
    }

    /// `rect` from its smaller corner, its size positive, as Core Graphics' shapes take it.
    @inline(__always)
    static func standardized(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.origin.x + DiagramPathArithmetic.minimum(rect.size.width, 0),
               y: rect.origin.y + DiagramPathArithmetic.minimum(rect.size.height, 0), width: abs(rect.size.width), height: abs(rect.size.height))
    }

    /// The transform of the unit square to a rectangle.
    @inline(__always)
    static func unitSquareTransform(origin: CGPoint, size: CGSize) -> CGAffineTransform {
        CGAffineTransform(a: size.width, b: 0, c: 0, d: size.height, tx: origin.x, ty: origin.y)
    }

    private mutating func appendRectangle(origin: CGPoint, size: CGSize) {
        guard !isEmpty else { return hold(DiagramPathPrimitive(shape: .rectangle, transform: Self.unitSquareTransform(origin: origin, size: size))) }
        let far = CGPoint(x: size.width + origin.x, y: size.height + origin.y)
        appendMove(to: origin, transform: nil)
        appendLine(to: CGPoint(x: far.x, y: origin.y), transform: nil)
        appendLine(to: far, transform: nil)
        appendLine(to: CGPoint(x: origin.x, y: far.y), transform: nil)
        closeElements()
    }

    /// The ellipse in `rect`, from its right end, against the clock on a page whose y runs up (`CGPathAddEllipseInRect`).
    mutating func addEllipse(in rect: CGRect) {
        var origin = rect.origin
        var size = CGSize.zero
        if origin.x != .infinity, origin.y != .infinity {
            let standard = Self.standardized(rect)
            origin = standard.origin
            size = standard.size
        }
        appendEllipse(CGRect(origin: origin, size: size), closes: true, isClockwise: false, transform: nil)
    }

    /// Core Graphics' `append_ellipse`: into an empty lane the ellipse is held whole as the transform of the unit square,
    /// else its elements are added.
    mutating func appendEllipse(_ rect: CGRect, closes: Bool, isClockwise: Bool, transform: CGAffineTransform?) {
        guard !isEmpty else {
            var whole = Self.unitSquareTransform(origin: rect.origin, size: rect.size)
            if let transform { whole = DiagramPathArithmetic.concatenation(whole, then: transform) }
            return hold(DiagramPathPrimitive(shape: .ellipse(closes: closes, isClockwise: isClockwise), transform: whole))
        }
        appendEllipseElements(rect, closes: closes, isClockwise: isClockwise, transform: transform)
    }

    /// Four quarter curves of the unit circle through the ellipse's transform.
    mutating func appendEllipseElements(_ rect: CGRect, closes: Bool, isClockwise: Bool, transform: CGAffineTransform?) {
        let center = CGPoint(x: abs(rect.size.width) * 0.5 + (rect.origin.x + DiagramPathArithmetic.minimum(rect.size.width, 0)),
                             y: abs(rect.size.height) * 0.5 + (rect.origin.y + DiagramPathArithmetic.minimum(rect.size.height, 0)))
        var ellipse = CGAffineTransform(a: 0.5 * rect.size.width, b: 0, c: 0, d: (isClockwise ? -0.5 : 0.5) * rect.size.height,
                                        tx: center.x, ty: center.y)
        if let transform { ellipse = DiagramPathArithmetic.concatenation(ellipse, then: transform) }
        let control = DiagramPathArithmetic.quarterTurnControlDistance
        reserve(verbs: 6, points: 13)
        appendMove(to: CGPoint(x: 1, y: 0), transform: ellipse)
        appendCurve(CGPoint(x: 1, y: control), CGPoint(x: control, y: 1), CGPoint(x: 0, y: 1), transform: ellipse)
        appendCurve(CGPoint(x: -control, y: 1), CGPoint(x: -1, y: control), CGPoint(x: -1, y: 0), transform: ellipse)
        appendCurve(CGPoint(x: -1, y: -control), CGPoint(x: -control, y: -1), CGPoint(x: 0, y: -1), transform: ellipse)
        appendCurve(CGPoint(x: control, y: -1), CGPoint(x: 1, y: -control), CGPoint(x: 1, y: 0), transform: ellipse)
        if closes { closeElements() }
    }

    /// The radii of a rounded rectangle's corners as Core Graphics clamps them: at most half the sides, at least 0.
    @inline(__always)
    static func clampedRadii(_ rect: CGRect, cornerWidth: CGFloat, cornerHeight: CGFloat) -> CGSize {
        CGSize(width: DiagramPathArithmetic.maximum(DiagramPathArithmetic.minimum(cornerWidth, abs(rect.size.width) * 0.5), 0),
               height: DiagramPathArithmetic.maximum(DiagramPathArithmetic.minimum(cornerHeight, abs(rect.size.height) * 0.5), 0))
    }

    /// A rectangle with rounded corners (`CGPathAddRoundedRect`): the corners' radii at most half the sides; a plain
    /// rectangle when either radius is 0.
    mutating func addRoundedRect(in rect: CGRect, cornerWidth: CGFloat, cornerHeight: CGFloat, transform: CGAffineTransform?) {
        let radii = Self.clampedRadii(rect, cornerWidth: cornerWidth, cornerHeight: cornerHeight)
        let standard = Self.standardized(rect)
        guard radii.width != 0, radii.height != 0 else {
            if let transform { return appendTransformedRectangle(origin: standard.origin, size: standard.size, transform: transform) }
            return appendRectangle(origin: standard.origin, size: standard.size)
        }
        guard !isEmpty else {
            var whole = Self.unitSquareTransform(origin: standard.origin, size: standard.size)
            if let transform { whole = DiagramPathArithmetic.concatenation(whole, then: transform) }
            let unitRadii = CGSize(width: radii.width / standard.size.width, height: radii.height / standard.size.height)
            return hold(DiagramPathPrimitive(shape: .roundedRectangle(unitRadii: unitRadii), transform: whole))
        }
        appendRoundedRectangle(origin: standard.origin, size: standard.size, radii: radii, transform: transform)
    }

    /// The rounded rectangle `addPath(CGPath(roundedRect:cornerWidth:cornerHeight:transform: nil))` adds, its radii
    /// clamped, without making that path: into an empty lane, held whole; after other elements, as Core Graphics adds a
    /// held rounded rectangle, the unit square's through the rectangle's transform, its first move replacing a move the
    /// lane ends with.
    mutating func addPathOfRoundedRect(_ rect: CGRect, cornerWidth: CGFloat, cornerHeight: CGFloat) {
        guard !isEmpty else { return addRoundedRect(in: rect, cornerWidth: cornerWidth, cornerHeight: cornerHeight, transform: nil) }
        let radii = Self.clampedRadii(rect, cornerWidth: cornerWidth, cornerHeight: cornerHeight)
        let standard = Self.standardized(rect)
        guard radii.width != 0, radii.height != 0 else { return appendRectangle(origin: standard.origin, size: standard.size) }
        expandHeldShape()
        appendRoundedRectangle(origin: .zero, size: CGSize(width: 1, height: 1),
                               radii: CGSize(width: radii.width / standard.size.width, height: radii.height / standard.size.height),
                               transform: Self.unitSquareTransform(origin: standard.origin, size: standard.size))
    }

    /// A rectangle through a transform, as Core Graphics adds one: through the transform's points, or, into an empty
    /// lane, held whole as the transform of the unit square.
    private mutating func appendTransformedRectangle(origin: CGPoint, size: CGSize, transform: CGAffineTransform) {
        let whole = DiagramPathArithmetic.concatenation(Self.unitSquareTransform(origin: origin, size: size), then: transform)
        guard !isEmpty else { return hold(DiagramPathPrimitive(shape: .rectangle, transform: whole)) }
        let far = CGPoint(x: size.width + origin.x, y: size.height + origin.y)
        appendMove(to: origin, transform: transform)
        appendLine(to: CGPoint(x: far.x, y: origin.y), transform: transform)
        appendLine(to: far, transform: transform)
        appendLine(to: CGPoint(x: origin.x, y: far.y), transform: transform)
        closeElements()
    }

    /// Core Graphics' `append_rounded_rect`: in the space where both radii are 1, a move to the middle of the right side
    /// and four corners, each a tangent arc (`appendTangentArc`), then a close.
    mutating func appendRoundedRectangle(origin: CGPoint, size: CGSize, radii: CGSize, transform: CGAffineTransform?) {
        var unitRadii = CGAffineTransform(a: radii.width, b: 0, c: 0, d: radii.height, tx: origin.x, ty: origin.y)
        if let transform { unitRadii = DiagramPathArithmetic.concatenation(unitRadii, then: transform) }
        let width = abs(size.width) / radii.width
        let height = abs(size.height) / radii.height
        let halfHeight = height * 0.5
        let halfWidth = width * 0.5
        let determinant = DiagramPathArithmetic.determinant(of: unitRadii)
        reserve(verbs: 10, points: 17)
        appendMove(to: CGPoint(x: width, y: halfHeight), transform: unitRadii)
        appendTangentArc(corner: CGPoint(x: width, y: height), next: CGPoint(x: halfWidth, y: height), radius: 1, transform: unitRadii,
                         determinant: determinant)
        appendTangentArc(corner: CGPoint(x: 0, y: height), next: CGPoint(x: 0, y: halfHeight), radius: 1, transform: unitRadii,
                         determinant: determinant)
        appendTangentArc(corner: CGPoint(x: 0, y: 0), next: CGPoint(x: halfWidth, y: 0), radius: 1, transform: unitRadii, determinant: determinant)
        appendTangentArc(corner: CGPoint(x: width, y: 0), next: CGPoint(x: width, y: halfHeight), radius: 1, transform: unitRadii,
                         determinant: determinant)
        closeElements()
    }
}
