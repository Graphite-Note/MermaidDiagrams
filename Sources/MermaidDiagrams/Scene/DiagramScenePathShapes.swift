/**
 * File: DiagramScenePathShapes.swift
 * ----------------------------------
 * Layer: Core
 * Description: The rectangles, rounded rectangles and ellipses a scene path adds, built by Core Graphics' own
 *              construction, and held whole as Core Graphics holds one such shape added to an empty path.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import CoreGraphics

/// The one shape a path is when it was added to an empty path, as Core Graphics keeps it: the transform of the unit
/// square to the shape, from which its elements are made and its bounds taken.
struct DiagramScenePathPrimitive: Sendable, Equatable {
    enum Shape: Sendable, Equatable {
        case rectangle
        /// Its corners' radii as fractions of its sides.
        case roundedRectangle(unitRadii: CGSize)
        case ellipse(closes: Bool, isClockwise: Bool)
        /// An arc of a circle of radius 1 from angle 0, turned through the size of `sweep` (the transform mirrors one
        /// with decreasing angle); `bounds` is Core Graphics' own for an arc of a whole turn or more, which it bounds by a
        /// rule of its own.
        case arc(sweep: CGFloat, wholeTurnBounds: WholeTurnBounds?)
    }

    /// Core Graphics' bounds of an arc of a whole turn or more, boxed so that the rare case costs a path no room.
    final class WholeTurnBounds: Sendable, Equatable {
        let rectangle: CGRect

        init(_ rectangle: CGRect) {
            self.rectangle = rectangle
        }

        static func == (left: WholeTurnBounds, right: WholeTurnBounds) -> Bool {
            left.rectangle == right.rectangle
        }
    }

    let shape: Shape
    let transform: CGAffineTransform

    /// The shape's elements, as Core Graphics makes them from what it holds.
    var elements: DiagramScenePath {
        var path = DiagramScenePath()
        let unitSquare = CGRect(x: 0, y: 0, width: 1, height: 1)
        switch shape {
        case .rectangle:
            path.appendMove(to: .zero, transform: transform)
            for corner in [CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)] { path.appendLine(to: corner, transform: transform) }
            path.closeSubpath()
        case .roundedRectangle(let unitRadii):
            path.appendRoundedRectangle(origin: .zero, size: unitSquare.size, radii: unitRadii, transform: transform)
        case .ellipse(let closes, let isClockwise):
            path.appendEllipse(unitSquare, closes: closes, isClockwise: isClockwise, transform: transform, mayHoldWhole: false)
        case .arc(let sweep, _):
            path.appendRelativeArc(center: .zero, radius: 1, startAngle: 0, sweep: abs(sweep), transform: transform, startsWithMove: true,
                                   mayHoldWhole: false)
        }
        return path
    }

    /// How many elements and points `elements` has.
    var elementAndPointCounts: (elements: Int, points: Int) {
        switch shape {
        case .rectangle: return (5, 4)
        case .roundedRectangle: return (10, 17)
        case .ellipse(let closes, _): return (closes ? 6 : 5, 13)
        case .arc:
            let made = elements
            return (made.elements.count, made.points.count)
        }
    }

    /// An arc's last curve as Core Graphics gives it out (`DiagramScenePath.writtenLastCurve(sweep:transform:)`).
    var writtenLastCurve: [CGPoint]? {
        guard case .arc(let sweep, _) = shape else { return nil }
        return DiagramScenePath.writtenLastCurve(sweep: sweep, transform: transform)
    }
}

extension DiagramScenePath {
    /// The path of a rectangle (`CGPath(rect:transform:)` with no transform).
    init(rect: CGRect) {
        self.init()
        addRect(rect)
    }

    init(ellipseIn rect: CGRect) {
        self.init()
        addEllipse(in: rect)
    }

    init(roundedRect rect: CGRect, cornerWidth: CGFloat, cornerHeight: CGFloat) {
        self.init()
        addRoundedRect(in: rect, cornerWidth: cornerWidth, cornerHeight: cornerHeight)
    }

    /// A rectangle, from its smaller corner: a move, three lines and a close (`CGPathAddRect`).
    mutating func addRect(_ rect: CGRect) {
        let standard = Self.standardized(rect)
        appendRectangle(origin: standard.origin, size: standard.size)
    }

    mutating func addRects(_ rects: [CGRect]) {
        for rect in rects { addRect(rect) }
    }

    /// `rect` from its smaller corner, its size positive, as Core Graphics' shapes take it.
    private static func standardized(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.origin.x + DiagramScenePathArithmetic.minimum(rect.size.width, 0),
               y: rect.origin.y + DiagramScenePathArithmetic.minimum(rect.size.height, 0), width: abs(rect.size.width), height: abs(rect.size.height))
    }

    /// The transform of the unit square to a rectangle.
    private static func unitSquareTransform(origin: CGPoint, size: CGSize) -> CGAffineTransform {
        CGAffineTransform(a: size.width, b: 0, c: 0, d: size.height, tx: origin.x, ty: origin.y)
    }

    private mutating func appendRectangle(origin: CGPoint, size: CGSize) {
        guard !isEmpty else {
            self = DiagramScenePath(holding: DiagramScenePathPrimitive(shape: .rectangle, transform: Self.unitSquareTransform(origin: origin, size: size)))
            return
        }
        let far = CGPoint(x: size.width + origin.x, y: size.height + origin.y)
        reserveCapacity(elements: 5, points: 4)
        appendMove(to: origin, transform: nil)
        appendLine(to: CGPoint(x: far.x, y: origin.y), transform: nil)
        appendLine(to: far, transform: nil)
        appendLine(to: CGPoint(x: origin.x, y: far.y), transform: nil)
        closeSubpath()
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

    /// Core Graphics' `append_ellipse`: four quarter curves of the unit circle through the ellipse's transform. Into an
    /// empty path, the ellipse is held whole as the transform of the unit square.
    mutating func appendEllipse(_ rect: CGRect, closes: Bool, isClockwise: Bool, transform: CGAffineTransform?, mayHoldWhole: Bool = true) {
        guard !mayHoldWhole || !isEmpty else {
            var whole = Self.unitSquareTransform(origin: rect.origin, size: rect.size)
            if let transform { whole = DiagramScenePathArithmetic.concatenation(whole, then: transform) }
            self = DiagramScenePath(holding: DiagramScenePathPrimitive(shape: .ellipse(closes: closes, isClockwise: isClockwise), transform: whole))
            return
        }
        let center = CGPoint(x: abs(rect.size.width) * 0.5 + (rect.origin.x + DiagramScenePathArithmetic.minimum(rect.size.width, 0)),
                             y: abs(rect.size.height) * 0.5 + (rect.origin.y + DiagramScenePathArithmetic.minimum(rect.size.height, 0)))
        var ellipse = CGAffineTransform(a: 0.5 * rect.size.width, b: 0, c: 0, d: (isClockwise ? -0.5 : 0.5) * rect.size.height,
                                        tx: center.x, ty: center.y)
        if let transform { ellipse = DiagramScenePathArithmetic.concatenation(ellipse, then: transform) }
        let control = DiagramScenePathArithmetic.quarterTurnControlDistance
        reserveCapacity(elements: 6, points: 13)
        appendMove(to: CGPoint(x: 1, y: 0), transform: ellipse)
        appendCurve(CGPoint(x: 1, y: control), CGPoint(x: control, y: 1), CGPoint(x: 0, y: 1), transform: ellipse)
        appendCurve(CGPoint(x: -control, y: 1), CGPoint(x: -1, y: control), CGPoint(x: -1, y: 0), transform: ellipse)
        appendCurve(CGPoint(x: -1, y: -control), CGPoint(x: -control, y: -1), CGPoint(x: 0, y: -1), transform: ellipse)
        appendCurve(CGPoint(x: control, y: -1), CGPoint(x: 1, y: -control), CGPoint(x: 1, y: 0), transform: ellipse)
        if closes { closeSubpath() }
    }

    /// The radii of a rounded rectangle's corners as Core Graphics clamps them: at most half the sides, at least 0.
    private static func clampedRadii(_ rect: CGRect, cornerWidth: CGFloat, cornerHeight: CGFloat) -> CGSize {
        CGSize(width: DiagramScenePathArithmetic.maximum(DiagramScenePathArithmetic.minimum(cornerWidth, abs(rect.size.width) * 0.5), 0),
               height: DiagramScenePathArithmetic.maximum(DiagramScenePathArithmetic.minimum(cornerHeight, abs(rect.size.height) * 0.5), 0))
    }

    /// A rectangle with rounded corners (`CGPathAddRoundedRect`): the corners' radii at most half the sides; a plain
    /// rectangle when either radius is 0.
    mutating func addRoundedRect(in rect: CGRect, cornerWidth: CGFloat, cornerHeight: CGFloat, transform: CGAffineTransform? = nil) {
        let radii = Self.clampedRadii(rect, cornerWidth: cornerWidth, cornerHeight: cornerHeight)
        let standard = Self.standardized(rect)
        guard radii.width != 0, radii.height != 0 else {
            if let transform { return appendTransformedRectangle(origin: standard.origin, size: standard.size, transform: transform) }
            return appendRectangle(origin: standard.origin, size: standard.size)
        }
        guard !isEmpty else {
            var whole = Self.unitSquareTransform(origin: standard.origin, size: standard.size)
            if let transform { whole = DiagramScenePathArithmetic.concatenation(whole, then: transform) }
            let unitRadii = CGSize(width: radii.width / standard.size.width, height: radii.height / standard.size.height)
            self = DiagramScenePath(holding: DiagramScenePathPrimitive(shape: .roundedRectangle(unitRadii: unitRadii), transform: whole))
            return
        }
        appendRoundedRectangle(origin: standard.origin, size: standard.size, radii: radii, transform: transform)
    }

    /// The rounded rectangle added as `addPath(DiagramScenePath(roundedRect:cornerWidth:cornerHeight:))` adds it, without
    /// making that path: into an empty path, held whole; after other elements, as Core Graphics adds a held rounded
    /// rectangle, the unit square's through the rectangle's transform.
    mutating func addPathOfRoundedRect(_ rect: CGRect, cornerWidth: CGFloat, cornerHeight: CGFloat) {
        guard !isEmpty else { return addRoundedRect(in: rect, cornerWidth: cornerWidth, cornerHeight: cornerHeight) }
        let radii = Self.clampedRadii(rect, cornerWidth: cornerWidth, cornerHeight: cornerHeight)
        let standard = Self.standardized(rect)
        guard radii.width != 0, radii.height != 0 else { return appendRectangle(origin: standard.origin, size: standard.size) }
        appendRoundedRectangle(origin: .zero, size: CGSize(width: 1, height: 1),
                               radii: CGSize(width: radii.width / standard.size.width, height: radii.height / standard.size.height),
                               transform: Self.unitSquareTransform(origin: standard.origin, size: standard.size))
    }

    /// A rectangle through a transform, as Core Graphics adds one: through the transform's points, or, into an empty
    /// path, held whole as the transform of the unit square.
    private mutating func appendTransformedRectangle(origin: CGPoint, size: CGSize, transform: CGAffineTransform) {
        let whole = DiagramScenePathArithmetic.concatenation(Self.unitSquareTransform(origin: origin, size: size), then: transform)
        guard !isEmpty else {
            self = DiagramScenePath(holding: DiagramScenePathPrimitive(shape: .rectangle, transform: whole))
            return
        }
        let far = CGPoint(x: size.width + origin.x, y: size.height + origin.y)
        appendMove(to: origin, transform: transform)
        for corner in [CGPoint(x: far.x, y: origin.y), far, CGPoint(x: origin.x, y: far.y)] { appendLine(to: corner, transform: transform) }
        closeSubpath()
    }

    /// Core Graphics' `append_rounded_rect`: in the space where both radii are 1, a move to the middle of the right side
    /// and four corners, each a tangent arc (`appendTangentArc`), then a close.
    mutating func appendRoundedRectangle(origin: CGPoint, size: CGSize, radii: CGSize, transform: CGAffineTransform?) {
        var unitRadii = CGAffineTransform(a: radii.width, b: 0, c: 0, d: radii.height, tx: origin.x, ty: origin.y)
        if let transform { unitRadii = DiagramScenePathArithmetic.concatenation(unitRadii, then: transform) }
        let width = abs(size.width) / radii.width
        let height = abs(size.height) / radii.height
        let halfHeight = height * 0.5
        let halfWidth = width * 0.5
        reserveCapacity(elements: 10, points: 17)
        appendMove(to: CGPoint(x: width, y: halfHeight), transform: unitRadii)
        appendTangentArc(corner: CGPoint(x: width, y: height), next: CGPoint(x: halfWidth, y: height), radius: 1, transform: unitRadii)
        appendTangentArc(corner: CGPoint(x: 0, y: height), next: CGPoint(x: 0, y: halfHeight), radius: 1, transform: unitRadii)
        appendTangentArc(corner: CGPoint(x: 0, y: 0), next: CGPoint(x: halfWidth, y: 0), radius: 1, transform: unitRadii)
        appendTangentArc(corner: CGPoint(x: width, y: 0), next: CGPoint(x: width, y: halfHeight), radius: 1, transform: unitRadii)
        closeSubpath()
    }
}
