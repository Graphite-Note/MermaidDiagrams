/**
 * File: DiagramScenePath.swift
 * ----------------------------
 * Layer: Core
 * Description: A scene's path as a value: its elements' kinds and points in two flat arrays, built as Core Graphics
 *              builds a mutable path, element for element and bit for bit, without a Core Graphics object.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import CoreGraphics

/// One element of a scene path, as Core Graphics names them.
enum DiagramScenePathElement: UInt8, Sendable {
    case move
    case line
    case quadCurve
    case curve
    case close

    /// How many points the element has: its end, after its control points.
    var pointCount: Int {
        switch self {
        case .move, .line: 1
        case .quadCurve: 2
        case .curve: 3
        case .close: 0
        }
    }
}

/// A path a drawing part builds and a scene holds: the same elements, to the bit, as the `CGMutablePath` built by the same
/// calls, kept as an array of kinds and one of points. Core Graphics' rules are kept: a move after a move replaces it, a
/// line or curve needs a current point, a close after a close or on an empty path does nothing, and a shape added to an
/// empty path is held whole as Core Graphics holds it (`DiagramScenePathPrimitive`): its elements are made only when they
/// are read or the path grows, and its bounds come from its transform.
struct DiagramScenePath: Sendable {
    private var storedElements: [DiagramScenePathElement] = []
    private var storedPoints: [CGPoint] = []
    /// The one shape the path is, held whole with no elements made yet; nil for a path of elements.
    private(set) var primitive: DiagramScenePathPrimitive?

    init() {}

    /// A path holding one shape whole.
    init(holding primitive: DiagramScenePathPrimitive) {
        self.primitive = primitive
    }

    var isEmpty: Bool {
        storedElements.isEmpty && primitive == nil
    }

    /// The elements' kinds, those of a held shape made for the reading.
    var elements: [DiagramScenePathElement] {
        guard let primitive else { return storedElements }
        return primitive.elements.storedElements
    }

    /// The elements' points, in order.
    var points: [CGPoint] {
        guard let primitive else { return storedPoints }
        return primitive.elements.storedPoints
    }

    /// The point the next line starts from: the last point, or the subpath's start after a close.
    var currentPoint: CGPoint {
        guard let last = storedElements.last, last != .close, let point = storedPoints.last else { return subpathStart }
        return point
    }

    /// Where the current subpath starts, its last move's point: the current point after a close. Found from the end, as
    /// it is asked for only after a close.
    private var subpathStart: CGPoint {
        var pointIndex = storedPoints.count
        for element in storedElements.reversed() {
            pointIndex -= element.pointCount
            if element == .move { return storedPoints[pointIndex] }
        }
        return .zero
    }

    // MARK: Elements

    mutating func move(to point: CGPoint) {
        makeHeldShapeElements()
        if storedElements.last == .move {
            storedPoints[storedPoints.count - 1] = point
            return
        }
        storedElements.append(.move)
        storedPoints.append(point)
    }

    /// A line from the current point; nothing on an empty path, which has none.
    mutating func addLine(to point: CGPoint) {
        guard !isEmpty else { return }
        makeHeldShapeElements()
        storedElements.append(.line)
        storedPoints.append(point)
    }

    mutating func addCurve(to end: CGPoint, control1: CGPoint, control2: CGPoint) {
        guard !isEmpty else { return }
        makeHeldShapeElements()
        appendCurve(control1, control2, end)
    }

    mutating func addQuadCurve(to end: CGPoint, control: CGPoint) {
        guard !isEmpty else { return }
        makeHeldShapeElements()
        storedElements.append(.quadCurve)
        storedPoints.append(control)
        storedPoints.append(end)
    }

    /// A move to the first point and lines to the others, as `CGPathAddLines` adds them.
    mutating func addLines(between linePoints: [CGPoint]) {
        guard let first = linePoints.first else { return }
        move(to: first)
        for point in linePoints.dropFirst() { addLine(to: point) }
    }

    /// Closes the current subpath: nothing on an empty path or after a close. A held ellipse left open is closed and
    /// stays held, as Core Graphics marks it; every other shape held is closed already.
    mutating func closeSubpath() {
        if let primitive {
            if case .ellipse(false, let isClockwise) = primitive.shape {
                self.primitive = DiagramScenePathPrimitive(shape: .ellipse(closes: true, isClockwise: isClockwise), transform: primitive.transform)
                return
            }
            guard case .arc = primitive.shape else { return }
            makeHeldShapeElements()
        }
        guard let last = storedElements.last, last != .close else { return }
        storedElements.append(.close)
    }

    /// `other`'s elements after this path's. Into an empty path, `other` is copied as it is, a held shape still held; a
    /// held shape is added again as its shape, its first move replacing a move this path ends with; any other path's
    /// elements are copied as they are.
    mutating func addPath(_ other: DiagramScenePath) {
        guard !other.isEmpty else { return }
        guard !isEmpty else {
            self = other
            return
        }
        makeHeldShapeElements()
        let added = other.primitive?.elements ?? other
        if other.primitive != nil, storedElements.last == .move {
            storedElements.removeLast()
            storedPoints.removeLast()
        }
        storedElements.append(contentsOf: added.storedElements)
        storedPoints.append(contentsOf: added.storedPoints)
    }

    /// Makes room for `elementCount` more elements of `pointCount` more points at once, growing the arrays by at least
    /// half again so that a path built shape by shape reallocates as seldom as one built element by element.
    mutating func reserveCapacity(elements elementCount: Int, points pointCount: Int) {
        if storedElements.capacity < storedElements.count + elementCount {
            storedElements.reserveCapacity(max(storedElements.count + elementCount, storedElements.capacity + storedElements.capacity / 2))
        }
        if storedPoints.capacity < storedPoints.count + pointCount {
            storedPoints.reserveCapacity(max(storedPoints.count + pointCount, storedPoints.capacity + storedPoints.capacity / 2))
        }
    }

    /// The path with arrays no longer than its elements, for a path that is finished and kept.
    func compacted() -> DiagramScenePath {
        guard primitive == nil, storedPoints.capacity > storedPoints.count + 1 || storedElements.capacity > storedElements.count + 16 else { return self }
        var copy = self
        copy.storedElements = Array(storedElements[...])
        copy.storedPoints = Array(storedPoints[...])
        return copy
    }

    /// The elements of the shape held whole, made when the path is to grow: Core Graphics turns a held shape into its
    /// elements before it adds any other.
    private mutating func makeHeldShapeElements() {
        guard let primitive else { return }
        self = primitive.elements
    }

    // MARK: Elements as Core Graphics adds them

    /// A move that starts a subpath even after a move, as a path's own elements are copied after another path's.
    mutating func appendMoveCopied(to point: CGPoint) {
        makeHeldShapeElements()
        storedElements.append(.move)
        storedPoints.append(point)
    }

    /// A move through `transform`, as Core Graphics' shapes add their first point.
    mutating func appendMove(to point: CGPoint, transform: CGAffineTransform?) {
        move(to: DiagramScenePathArithmetic.point(point, transformedBy: transform))
    }

    /// A line through `transform`, which Core Graphics' shapes add without asking for a current point.
    mutating func appendLine(to point: CGPoint, transform: CGAffineTransform?) {
        makeHeldShapeElements()
        storedElements.append(.line)
        storedPoints.append(DiagramScenePathArithmetic.point(point, transformedBy: transform))
    }

    /// A curve through `transform`.
    mutating func appendCurve(_ control1: CGPoint, _ control2: CGPoint, _ end: CGPoint, transform: CGAffineTransform?) {
        makeHeldShapeElements()
        appendCurve(DiagramScenePathArithmetic.point(control1, transformedBy: transform),
                    DiagramScenePathArithmetic.point(control2, transformedBy: transform),
                    DiagramScenePathArithmetic.point(end, transformedBy: transform))
    }

    private mutating func appendCurve(_ control1: CGPoint, _ control2: CGPoint, _ end: CGPoint) {
        storedElements.append(.curve)
        storedPoints.append(control1)
        storedPoints.append(control2)
        storedPoints.append(end)
    }

    // MARK: Reading

    /// Calls `body` with each element and its points, in order, as Core Graphics gives a path's elements out
    /// (`CGPathApply`): a held arc's last curve as it works that out from the arc's stored sine, cosine and tangent.
    func forEachElement(_ body: (DiagramScenePathElement, UnsafeBufferPointer<CGPoint>) -> Void) {
        guard let primitive else { return Self.forEachElement(of: storedElements, points: storedPoints, body) }
        let made = primitive.elements
        var written = made.storedPoints
        if let lastCurve = primitive.writtenLastCurve, made.storedElements.last == .curve {
            written.replaceSubrange(written.count - 3..<written.count, with: lastCurve)
        }
        Self.forEachElement(of: made.storedElements, points: written, body)
    }

    /// Calls `body` with each element as the path holds it, which Core Graphics bounds and adds to other paths.
    func forEachStoredElement(_ body: (DiagramScenePathElement, UnsafeBufferPointer<CGPoint>) -> Void) {
        guard let primitive else { return Self.forEachElement(of: storedElements, points: storedPoints, body) }
        let made = primitive.elements
        Self.forEachElement(of: made.storedElements, points: made.storedPoints, body)
    }

    /// The most bytes of points and elements `forEachElement` gives: its counts of elements and of points.
    var elementAndPointCounts: (elements: Int, points: Int) {
        guard let primitive else { return (storedElements.count, storedPoints.count) }
        return primitive.elementAndPointCounts
    }

    private static func forEachElement(of elements: [DiagramScenePathElement], points: [CGPoint],
                                       _ body: (DiagramScenePathElement, UnsafeBufferPointer<CGPoint>) -> Void) {
        points.withUnsafeBufferPointer { allPoints in
            var pointIndex = 0
            for element in elements {
                let count = element.pointCount
                body(element, UnsafeBufferPointer(rebasing: allPoints[pointIndex..<pointIndex + count]))
                pointIndex += count
            }
        }
    }

    /// The path as a Core Graphics path with the same elements.
    var coreGraphicsPath: CGPath {
        coreGraphicsMutablePath
    }

    /// The path as a new Core Graphics mutable path with the same elements.
    var coreGraphicsMutablePath: CGMutablePath {
        let path = CGMutablePath()
        forEachElement { element, elementPoints in
            switch element {
            case .move: path.move(to: elementPoints[0])
            case .line: path.addLine(to: elementPoints[0])
            case .quadCurve: path.addQuadCurve(to: elementPoints[1], control: elementPoints[0])
            case .curve: path.addCurve(to: elementPoints[2], control1: elementPoints[0], control2: elementPoints[1])
            case .close: path.closeSubpath()
            }
        }
        return path
    }

    /// The elements of a Core Graphics path, as it gives them (`applyWithBlock`).
    init(_ path: CGPath) {
        path.applyWithBlock { pointer in
            let element = pointer.pointee
            switch element.type {
            case .moveToPoint:
                storedElements.append(.move)
                storedPoints.append(element.points[0])
            case .addLineToPoint:
                storedElements.append(.line)
                storedPoints.append(element.points[0])
            case .addQuadCurveToPoint:
                storedElements.append(.quadCurve)
                storedPoints.append(contentsOf: [element.points[0], element.points[1]])
            case .addCurveToPoint:
                storedElements.append(.curve)
                storedPoints.append(contentsOf: [element.points[0], element.points[1], element.points[2]])
            case .closeSubpath:
                storedElements.append(.close)
            @unknown default:
                break
            }
        }
    }
}

extension DiagramScenePath: Equatable {
    /// The same elements and points; how each path holds them does not count.
    static func == (left: DiagramScenePath, right: DiagramScenePath) -> Bool {
        if let leftShape = left.primitive, let rightShape = right.primitive, leftShape == rightShape { return true }
        return left.elements == right.elements && left.points == right.points
    }
}

extension DiagramScenePath {
    /// Whether `point` is inside the path filled by the nonzero rule, as Core Graphics answers for its path.
    func contains(_ point: CGPoint) -> Bool {
        coreGraphicsPath.contains(point)
    }

    /// Calls `body` with each element as `CGPath.applyWithBlock` gives it.
    func applyWithBlock(_ body: (UnsafePointer<CGPathElement>) -> Void) {
        coreGraphicsPath.applyWithBlock(body)
    }

    /// The path with every point through `transform`, as `CGPath.copy(using:)` makes it.
    func applying(_ transform: CGAffineTransform) -> DiagramScenePath {
        var copy = primitive?.elements ?? self
        for index in copy.storedPoints.indices {
            copy.storedPoints[index] = DiagramScenePathArithmetic.point(copy.storedPoints[index], transformedBy: transform)
        }
        return copy
    }
}
