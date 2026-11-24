/**
 * File: DiagramScenePathBounds.swift
 * ----------------------------------
 * Layer: Core
 * Description: A scene path's bounds as Core Graphics' `boundingBoxOfPath` gives them: a held shape's from its transform,
 *              any other path's from its points and the extremes of its curves, found as Core Graphics finds them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import CoreGraphics

extension DiagramScenePath {
    /// The smallest rectangle holding the path, its curves' extremes included (`CGPathGetPathBoundingBox`); null for an
    /// empty path. Exactly Core Graphics' numbers, which a scene's merging of shapes depends on.
    var boundingBoxOfPath: CGRect {
        guard !isEmpty else { return .null }
        if let primitive, let bounds = primitive.bounds { return bounds }
        var bounds = DiagramScenePathBoundsCollector()
        forEachStoredElement { element, elementPoints in bounds.add(element, elementPoints) }
        return bounds.rectangle
    }
}

extension DiagramScenePathPrimitive {
    /// The bounds Core Graphics gives a held shape without its elements: a rectangle's always, a rounded rectangle's and
    /// an ellipse's when their transform keeps the axes; nil when they come from the elements.
    var bounds: CGRect? {
        switch shape {
        case .rectangle: return unitSquareBounds
        case .roundedRectangle, .ellipse:
            let keepsAxes = (transform.b == 0 && transform.c == 0) || (transform.a == 0 && transform.d == 0)
            return keepsAxes ? unitSquareBounds : nil
        case .arc(_, let wholeTurnBounds): return wholeTurnBounds?.rectangle
        }
    }

    /// The bounds of the unit square through the transform (Core Graphics' `transform_unit_rect`).
    private var unitSquareBounds: CGRect {
        let across = Self.range(of: [transform.a, transform.c, transform.a + transform.c], keepsAxes: transform.b == 0 && transform.c == 0,
                                single: transform.a)
        let down = Self.range(of: [transform.b, transform.d, transform.b + transform.d], keepsAxes: transform.b == 0 && transform.c == 0,
                              single: transform.d)
        return CGRect(x: across.lowest + transform.tx, y: down.lowest + transform.ty, width: across.highest - across.lowest,
                      height: down.highest - down.lowest)
    }

    /// The least and greatest of 0 and `values`, or of 0 and `single` when the transform keeps the axes.
    private static func range(of values: [CGFloat], keepsAxes: Bool, single: CGFloat) -> (lowest: CGFloat, highest: CGFloat) {
        if keepsAxes { return (DiagramScenePathArithmetic.minimum(single, 0), DiagramScenePathArithmetic.maximum(single, 0)) }
        var lowest: CGFloat = 0
        var highest: CGFloat = 0
        for value in values {
            if value < lowest { lowest = value }
            if highest < value { highest = value }
        }
        return (lowest, highest)
    }
}

/// Core Graphics' `path_element_bounding_box`, element by element: each end point, and each point of a curve where it
/// turns back across or down, found from its polynomial with Core Graphics' tolerances.
struct DiagramScenePathBoundsCollector {
    private var lowest = CGPoint(x: CGFloat.infinity, y: .infinity)
    private var highest = CGPoint(x: -CGFloat.infinity, y: -.infinity)
    private var current = CGPoint.zero
    private var subpathStart = CGPoint.zero

    var rectangle: CGRect {
        CGRect(x: lowest.x, y: lowest.y, width: highest.x - lowest.x, height: highest.y - lowest.y)
    }

    mutating func add(_ element: DiagramScenePathElement, _ elementPoints: UnsafeBufferPointer<CGPoint>) {
        switch element {
        case .move:
            subpathStart = elementPoints[0]
            current = elementPoints[0]
            include(current)
        case .line:
            current = elementPoints[0]
            include(current)
        case .close:
            current = subpathStart
            include(current)
        case .quadCurve:
            addQuadCurve(control: elementPoints[0], end: elementPoints[1])
        case .curve:
            addCurve(control1: elementPoints[0], control2: elementPoints[1], end: elementPoints[2])
        }
    }

    private mutating func include(_ point: CGPoint) {
        if point.x < lowest.x { lowest.x = point.x }
        if point.y < lowest.y { lowest.y = point.y }
        if highest.x < point.x { highest.x = point.x }
        if highest.y < point.y { highest.y = point.y }
    }

    private static let lowTolerance: CGFloat = 0.0001
    private static let highTolerance: CGFloat = 0.99990000000000001

    private mutating func addQuadCurve(control: CGPoint, end: CGPoint) {
        let start = current
        let linear = CGPoint(x: (control.x - start.x) + (control.x - start.x), y: (control.y - start.y) + (control.y - start.y))
        let square = CGPoint(x: (end.x - linear.x) - start.x, y: (end.y - linear.y) - start.y)
        func point(at parameter: CGFloat) -> CGPoint {
            CGPoint(x: start.x.addingProduct(linear.x.addingProduct(square.x, parameter), parameter),
                    y: start.y.addingProduct(linear.y.addingProduct(square.y, parameter), parameter))
        }
        let acrossTurn = Self.quadraticTurn(linear: linear.x, square: square.x).map(point(at:))
        let downTurn = Self.quadraticTurn(linear: linear.y, square: square.y).map(point(at:))
        current = end
        include(end)
        if let acrossTurn { include(acrossTurn) }
        if let downTurn { include(downTurn) }
    }

    /// Where `linear·t + square·t²` turns, when it does well inside the curve.
    private static func quadraticTurn(linear: CGFloat, square: CGFloat) -> CGFloat? {
        let twice = -2 * square
        let low = twice * lowTolerance
        let high = twice * highTolerance
        let isInside = square > 0 ? (high < linear && linear < low) : (square < 0 && low < linear && linear < high)
        return isInside ? -linear / (square + square) : nil
    }

    private mutating func addCurve(control1: CGPoint, control2: CGPoint, end: CGPoint) {
        let start = current
        let linear = CGPoint(x: (control1.x - start.x) * 3, y: (control1.y - start.y) * 3)
        let square = CGPoint(x: (-linear.x).addingProduct(3, control2.x - control1.x), y: (-linear.y).addingProduct(3, control2.y - control1.y))
        let cube = CGPoint(x: ((end.x - square.x) - linear.x) - start.x, y: ((end.y - square.y) - linear.y) - start.y)
        func point(at parameter: CGFloat) -> CGPoint {
            CGPoint(x: start.x.addingProduct(linear.x.addingProduct(square.x.addingProduct(cube.x, parameter), parameter), parameter),
                    y: start.y.addingProduct(linear.y.addingProduct(square.y.addingProduct(cube.y, parameter), parameter), parameter))
        }
        let acrossTurns = Self.cubicTurns(linear: linear.x, square: square.x, cube: cube.x)
        let downTurns = Self.cubicTurns(linear: linear.y, square: square.y, cube: cube.y)
        current = end
        include(end)
        for parameter in [acrossTurns.first, acrossTurns.second, downTurns.first, downTurns.second] {
            if let parameter { include(point(at: parameter)) }
        }
    }

    /// Where `linear·t + square·t² + cube·t³` turns well inside the curve: its derivative's roots, the first from the
    /// stable form of the quadratic formula, the second from the product of the roots.
    private static func cubicTurns(linear: CGFloat, square: CGFloat, cube: CGFloat) -> (first: CGFloat?, second: CGFloat?) {
        let squared = square * square
        let threeCube = 3 * cube
        let product = threeCube * linear
        let tolerance = (squared + abs(product)) * lowTolerance
        let discriminant = abs(squared - product) > tolerance ? squared - product : 0
        guard !(discriminant < 0) else { return (nil, nil) }
        let scaled = (square < 0 ? 1 : -1) * discriminant.squareRoot() - square
        let low = threeCube * lowTolerance
        let high = threeCube * highTolerance
        var first: CGFloat?
        if cube > 0 ? (low < scaled && scaled < high) : (cube < 0 && high < scaled && scaled < low) {
            first = scaled / threeCube
        }
        let secondLow = scaled * lowTolerance
        let secondHigh = scaled * highTolerance
        var second: CGFloat?
        if scaled > 0 ? (secondLow < linear && linear < secondHigh) : (scaled < 0 && secondHigh < linear && linear < secondLow) {
            second = linear / scaled
        }
        return (first, second)
    }
}
