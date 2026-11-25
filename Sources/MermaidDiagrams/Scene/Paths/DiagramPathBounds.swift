/**
 * File: DiagramPathBounds.swift
 * -----------------------------
 * Layer: Core
 * Description: A path lane's bounds as Core Graphics' `boundingBoxOfPath` gives them: a held shape's from its transform,
 *              any other lane's from its points and the extremes of its curves, found as Core Graphics finds them.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

import CoreGraphics

extension DiagramPathLaneState {
    /// The smallest rectangle holding the lane, its curves' extremes included (`CGPathGetPathBoundingBox`); null for an
    /// empty lane. Exactly Core Graphics' numbers, which a scene's merging of shapes depends on; worked out when first
    /// asked and kept until the lane changes.
    mutating func boundsOfPath() -> CGRect {
        if let cachedBounds { return cachedBounds }
        let bounds = computedBounds()
        cachedBounds = bounds
        return bounds
    }

    private mutating func computedBounds() -> CGRect {
        guard !isEmpty else { return .null }
        if let shape = held, let bounds = shape.bounds { return bounds }
        var collector = DiagramPathBoundsCollector()
        forEachStoredElement { verb, elementPoints in collector.add(verb, elementPoints) }
        return collector.rectangle
    }
}

/// Core Graphics' `path_element_bounding_box`, element by element: each end point, and each point of a curve where it
/// turns back across or down, found from its polynomial with Core Graphics' tolerances.
struct DiagramPathBoundsCollector {
    private var lowest = CGPoint(x: CGFloat.infinity, y: .infinity)
    private var highest = CGPoint(x: -CGFloat.infinity, y: -.infinity)
    private var current = CGPoint.zero
    private var subpathStart = CGPoint.zero

    var rectangle: CGRect {
        CGRect(x: lowest.x, y: lowest.y, width: highest.x - lowest.x, height: highest.y - lowest.y)
    }

    mutating func add(_ verb: DiagramPathVerb, _ elementPoints: UnsafePointer<CGPoint>) {
        switch verb {
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
        case .quadraticCurve:
            addQuadCurve(control: elementPoints[0], end: elementPoints[1])
        case .cubicCurve:
            addCurve(control1: elementPoints[0], control2: elementPoints[1], end: elementPoints[2])
        }
    }

    @inline(__always)
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
        current = end
        include(end)
        if let parameter = Self.quadraticTurn(linear: linear.x, square: square.x) {
            include(Self.quadraticPoint(start: start, linear: linear, square: square, at: parameter))
        }
        if let parameter = Self.quadraticTurn(linear: linear.y, square: square.y) {
            include(Self.quadraticPoint(start: start, linear: linear, square: square, at: parameter))
        }
    }

    @inline(__always)
    private static func quadraticPoint(start: CGPoint, linear: CGPoint, square: CGPoint, at parameter: CGFloat) -> CGPoint {
        CGPoint(x: start.x.addingProduct(linear.x.addingProduct(square.x, parameter), parameter),
                y: start.y.addingProduct(linear.y.addingProduct(square.y, parameter), parameter))
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
        let acrossTurns = Self.cubicTurns(linear: linear.x, square: square.x, cube: cube.x)
        let downTurns = Self.cubicTurns(linear: linear.y, square: square.y, cube: cube.y)
        current = end
        include(end)
        includeTurn(acrossTurns.first, start: start, linear: linear, square: square, cube: cube)
        includeTurn(acrossTurns.second, start: start, linear: linear, square: square, cube: cube)
        includeTurn(downTurns.first, start: start, linear: linear, square: square, cube: cube)
        includeTurn(downTurns.second, start: start, linear: linear, square: square, cube: cube)
    }

    @inline(__always)
    private mutating func includeTurn(_ parameter: CGFloat?, start: CGPoint, linear: CGPoint, square: CGPoint, cube: CGPoint) {
        guard let parameter else { return }
        include(Self.cubicPoint(start: start, linear: linear, square: square, cube: cube, at: parameter))
    }

    @inline(__always)
    private static func cubicPoint(start: CGPoint, linear: CGPoint, square: CGPoint, cube: CGPoint, at parameter: CGFloat) -> CGPoint {
        CGPoint(x: start.x.addingProduct(linear.x.addingProduct(square.x.addingProduct(cube.x, parameter), parameter), parameter),
                y: start.y.addingProduct(linear.y.addingProduct(square.y.addingProduct(cube.y, parameter), parameter), parameter))
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
