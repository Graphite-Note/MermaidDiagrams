/**
 * File: DiagramPathLaneState.swift
 * --------------------------------
 * Layer: Core
 * Description: What a path lane records: its verbs and points in two blocks of memory kept between scenes, the point its
 *              subpath starts at, the one shape it may hold whole, and its bounds once asked; elements appended by Core
 *              Graphics' rules, and paths added to it as Core Graphics adds them.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

import CoreGraphics

/// A path lane's elements, built as Core Graphics builds a mutable path, element for element and bit for bit, without a
/// Core Graphics object: a move after a move replaces it, a line or curve needs a current point, a close after a close or
/// on an empty lane does nothing, and a shape added to an empty lane is held whole (`held`) as Core Graphics holds it, its
/// elements made only when they are read or the lane grows. Its memory is two blocks it grows, kept by the workspace
/// between scenes; past `elementLimit` verbs the lane is emptied and marked `hasOverflowed`, which its scene refuses,
/// instead of growing without bound. The lane's handle (`DiagramPathLane`) points at it, so it is never copied.
struct DiagramPathLaneState {
    private(set) var verbs: UnsafeMutablePointer<DiagramPathVerb>
    private(set) var points: UnsafeMutablePointer<CGPoint>
    private(set) var verbCount = 0
    private(set) var pointCount = 0
    private var verbCapacity: Int
    private var pointCapacity: Int
    /// Where the current subpath starts: its last move's point, the current point after a close.
    private(set) var subpathStart = CGPoint.zero
    /// Whether the lane is one shape held whole (`heldShape`), with no elements made yet: a flag beside the shape, so
    /// that each element appended checks one byte.
    private(set) var holdsShape = false
    private var heldShape = DiagramPathPrimitive(shape: .rectangle, transform: .identity)
    /// Whether `cachedBoundsValue` is the lane's bounds: asked once and the lane unchanged since.
    private var hasCachedBounds = false
    private var cachedBoundsValue = CGRect.null
    /// The most verbs the lane records; three points a verb at most.
    let elementLimit: Int
    /// Whether the lane went past `elementLimit` and was emptied.
    private(set) var hasOverflowed = false
    /// Whether the blocks are the lane's own, to grow and free; a lane over borrowed blocks never grows.
    private let ownsStorage: Bool
    /// The recording the lane belongs to, which debug builds check a handle against.
    var generation: UInt32 = 0

    /// A lane with blocks of its own for `verbCapacity` verbs and three times as many points.
    init(verbCapacity: Int, elementLimit: Int) {
        self.verbCapacity = max(verbCapacity, 1)
        pointCapacity = self.verbCapacity * 3
        verbs = .allocate(capacity: self.verbCapacity)
        points = .allocate(capacity: pointCapacity)
        self.elementLimit = elementLimit
        ownsStorage = true
    }

    /// A lane over blocks a caller lends for a moment, big enough for everything it will be given.
    init(borrowingVerbs verbs: UnsafeMutableBufferPointer<DiagramPathVerb>, points: UnsafeMutableBufferPointer<CGPoint>) {
        self.verbs = verbs.baseAddress.unsafelyUnwrapped
        self.points = points.baseAddress.unsafelyUnwrapped
        verbCapacity = verbs.count
        pointCapacity = points.count
        elementLimit = verbs.count
        ownsStorage = false
    }

    /// Frees the lane's own blocks; the lane is not used afterwards.
    func deallocate() {
        guard ownsStorage else { return }
        verbs.deallocate()
        points.deallocate()
    }

    /// The one shape the lane is, held whole; nil for a lane of elements.
    var held: DiagramPathPrimitive? {
        holdsShape ? heldShape : nil
    }

    /// The bounds, once asked and until the lane changes.
    var cachedBounds: CGRect? {
        get { hasCachedBounds ? cachedBoundsValue : nil }
        set {
            hasCachedBounds = newValue != nil
            cachedBoundsValue = newValue ?? .null
        }
    }

    /// Empties the lane, keeping its blocks.
    mutating func removeAll() {
        verbCount = 0
        pointCount = 0
        subpathStart = .zero
        holdsShape = false
        hasCachedBounds = false
        hasOverflowed = false
    }

    /// The bytes the lane's blocks take.
    var capacityByteCount: Int {
        verbCapacity * MemoryLayout<DiagramPathVerb>.stride + pointCapacity * MemoryLayout<CGPoint>.stride
    }

    var isEmpty: Bool {
        verbCount == 0 && !holdsShape
    }

    /// The last verb, nil for a lane without elements.
    @inline(__always)
    var lastVerb: DiagramPathVerb? {
        verbCount == 0 ? nil : verbs[verbCount &- 1]
    }

    /// The point the next line starts from: the last point, or the subpath's start after a close; for a held shape, the
    /// point Core Graphics works out from its transform (`DiagramPathPrimitive.currentPoint`).
    var currentPoint: CGPoint {
        @inline(__always) get {
            if holdsShape { return heldShapeCurrentPoint }
            guard verbCount > 0, verbs[verbCount &- 1] != .close, pointCount > 0 else { return subpathStart }
            return points[pointCount &- 1]
        }
    }

    @inline(never)
    private var heldShapeCurrentPoint: CGPoint {
        heldShape.currentPoint
    }

    // MARK: Room

    /// Makes room for `verbCount` more verbs and `pointCount` more points. Past the element limit the lane is emptied
    /// and marked, and the room is made in the emptied lane, so that what follows is written safely and thrown away.
    @inline(__always)
    mutating func reserve(verbs addedVerbs: Int, points addedPoints: Int) {
        hasCachedBounds = false
        guard verbCapacity &- verbCount < addedVerbs || pointCapacity &- pointCount < addedPoints else { return }
        grow(verbs: addedVerbs, points: addedPoints)
    }

    @inline(never)
    private mutating func grow(verbs addedVerbs: Int, points addedPoints: Int) {
        if verbCount + addedVerbs > elementLimit || pointCount + addedPoints > elementLimit * 3 {
            removeAll()
            hasOverflowed = true
        }
        guard ownsStorage else { preconditionFailure("a lane over borrowed blocks is given no more than they hold") }
        if verbCapacity - verbCount < addedVerbs {
            let grown = max(verbCapacity * 2, verbCount + addedVerbs)
            let block = UnsafeMutablePointer<DiagramPathVerb>.allocate(capacity: grown)
            block.initialize(from: verbs, count: verbCount)
            verbs.deallocate()
            verbs = block
            verbCapacity = grown
        }
        if pointCapacity - pointCount < addedPoints {
            let grown = max(pointCapacity * 2, pointCount + addedPoints)
            let block = UnsafeMutablePointer<CGPoint>.allocate(capacity: grown)
            block.initialize(from: points, count: pointCount)
            points.deallocate()
            points = block
            pointCapacity = grown
        }
    }

    /// Frees blocks grown past `byteCount` and starts again from small ones, after a scene that needed them.
    mutating func trim(toAtMost byteCount: Int, verbCapacity smallVerbCapacity: Int) {
        guard ownsStorage, capacityByteCount > byteCount else { return }
        deallocate()
        verbCapacity = smallVerbCapacity
        pointCapacity = smallVerbCapacity * 3
        verbs = .allocate(capacity: verbCapacity)
        points = .allocate(capacity: pointCapacity)
        removeAll()
    }

    @inline(__always)
    private mutating func push(_ verb: DiagramPathVerb) {
        verbs[verbCount] = verb
        verbCount &+= 1
    }

    @inline(__always)
    private mutating func push(_ point: CGPoint) {
        points[pointCount] = point
        pointCount &+= 1
    }

    // MARK: Elements

    mutating func move(to point: CGPoint) {
        expandHeldShape()
        reserve(verbs: 1, points: 1)
        if lastVerb == .move {
            points[pointCount &- 1] = point
        } else {
            push(.move)
            push(point)
        }
        subpathStart = point
    }

    /// The point of the move the lane ends with set to `writtenPoint`, its subpath starting at `subpathStartPoint`, as
    /// Core Graphics leaves a held shape's first move added through a transform after a move.
    mutating func replaceTrailingMove(writing writtenPoint: CGPoint, startingAt subpathStartPoint: CGPoint) {
        hasCachedBounds = false
        points[pointCount &- 1] = writtenPoint
        subpathStart = subpathStartPoint
    }

    /// A line from the current point; nothing on an empty lane, which has none.
    mutating func addLine(to point: CGPoint) {
        guard !isEmpty else { return }
        appendLine(to: point, transform: nil)
    }

    mutating func addQuadCurve(to end: CGPoint, control: CGPoint) {
        guard !isEmpty else { return }
        expandHeldShape()
        reserve(verbs: 1, points: 2)
        push(.quadraticCurve)
        push(control)
        push(end)
    }

    mutating func addCurve(to end: CGPoint, control1: CGPoint, control2: CGPoint) {
        guard !isEmpty else { return }
        appendCurve(control1, control2, end, transform: nil)
    }

    /// Closes the current subpath: nothing on an empty lane or after a close. A held ellipse left open is closed and
    /// stays held, as Core Graphics marks it; every other shape held but an arc is closed already.
    mutating func closeSubpath() {
        if holdsShape {
            if case .ellipse(false, let isClockwise) = heldShape.shape {
                heldShape = DiagramPathPrimitive(shape: .ellipse(closes: true, isClockwise: isClockwise), transform: heldShape.transform)
                hasCachedBounds = false
                return
            }
            guard case .arc = heldShape.shape else { return }
            expandHeldShape()
        }
        closeElements()
    }

    /// A close of a lane of elements: nothing on an empty lane or after a close.
    mutating func closeElements() {
        guard let last = lastVerb, last != .close else { return }
        reserve(verbs: 1, points: 0)
        push(.close)
    }

    /// A move through `transform`, as Core Graphics' shapes add their first point: it replaces a move the lane ends with.
    mutating func appendMove(to point: CGPoint, transform: CGAffineTransform?) {
        move(to: DiagramPathArithmetic.point(point, transformedBy: transform))
    }

    /// A line through `transform`, which Core Graphics' shapes add without asking for a current point.
    mutating func appendLine(to point: CGPoint, transform: CGAffineTransform?) {
        expandHeldShape()
        reserve(verbs: 1, points: 1)
        push(.line)
        push(DiagramPathArithmetic.point(point, transformedBy: transform))
    }

    /// A cubic curve through `transform`.
    mutating func appendCurve(_ control1: CGPoint, _ control2: CGPoint, _ end: CGPoint, transform: CGAffineTransform?) {
        expandHeldShape()
        reserve(verbs: 1, points: 3)
        push(.cubicCurve)
        push(DiagramPathArithmetic.point(control1, transformedBy: transform))
        push(DiagramPathArithmetic.point(control2, transformedBy: transform))
        push(DiagramPathArithmetic.point(end, transformedBy: transform))
    }

    /// Makes the lane hold `shape` whole; the lane is empty.
    mutating func hold(_ shape: DiagramPathPrimitive) {
        heldShape = shape
        holdsShape = true
        hasCachedBounds = false
    }

    /// The elements of the shape held whole, made when the lane is to grow: Core Graphics turns a held shape into its
    /// elements before it adds any other.
    @inline(__always)
    mutating func expandHeldShape() {
        guard holdsShape else { return }
        holdsShape = false
        let shape = heldShape
        shape.appendElements(to: &self)
    }

    /// Calls `body` with the lane's held shape made into elements in blocks lent for the moment; the lane is unchanged.
    func withHeldShapeExpanded<Result>(_ body: (inout DiagramPathLaneState) -> Result) -> Result {
        withUnsafeTemporaryAllocation(of: DiagramPathVerb.self, capacity: DiagramPathPrimitive.largestElementCount) { verbBlock in
            withUnsafeTemporaryAllocation(of: CGPoint.self, capacity: DiagramPathPrimitive.largestPointCount) { pointBlock in
                var expanded = DiagramPathLaneState(borrowingVerbs: verbBlock, points: pointBlock)
                if holdsShape { heldShape.appendElements(to: &expanded) }
                return body(&expanded)
            }
        }
    }

    // MARK: Paths added

    /// `other`'s elements after this lane's. Into an empty lane, `other` is copied as it is, a held shape still held; a
    /// held shape is added again as its shape, its first move replacing a move this lane ends with; any other lane's
    /// elements are copied as they are. `other` is not this lane (`DiagramPathLane.addPath` copies a lane added to itself
    /// first).
    mutating func addPath(_ other: borrowing DiagramPathLaneState) {
        guard !other.isEmpty else { return }
        guard !isEmpty else { return copyContents(of: other) }
        expandHeldShape()
        if other.holdsShape { return other.heldShape.appendElements(to: &self) }
        appendElements(of: other)
    }

    /// Copies `other`'s elements and held shape into this empty lane.
    mutating func copyContents(of other: borrowing DiagramPathLaneState) {
        appendElements(of: other)
        holdsShape = other.holdsShape
        heldShape = other.heldShape
        subpathStart = other.subpathStart
        cachedBounds = other.cachedBounds
    }

    /// `other`'s elements, copied as they are, after this lane's.
    mutating func appendElements(of other: borrowing DiagramPathLaneState) {
        guard other.verbCount > 0 else { return }
        reserve(verbs: other.verbCount, points: other.pointCount)
        (verbs + verbCount).initialize(from: other.verbs, count: other.verbCount)
        (points + pointCount).initialize(from: other.points, count: other.pointCount)
        verbCount &+= other.verbCount
        pointCount &+= other.pointCount
        subpathStart = other.subpathStart
    }

    /// `other`'s elements from its verb `verbStart` and its point `pointStart` on, copied as they are after this lane's,
    /// its subpath starting where `other`'s does.
    mutating func appendElements(of other: borrowing DiagramPathLaneState, fromVerb verbStart: Int, point pointStart: Int) {
        let addedVerbCount = other.verbCount - verbStart
        let addedPointCount = other.pointCount - pointStart
        guard addedVerbCount > 0 else { return }
        reserve(verbs: addedVerbCount, points: addedPointCount)
        (verbs + verbCount).initialize(from: other.verbs + verbStart, count: addedVerbCount)
        (points + pointCount).initialize(from: other.points + pointStart, count: addedPointCount)
        verbCount &+= addedVerbCount
        pointCount &+= addedPointCount
        subpathStart = other.subpathStart
    }

    /// One element copied as Core Graphics gives it out, for a lane read from a Core Graphics path: a move starts a
    /// subpath even after a move, as a path's own elements are copied.
    mutating func appendCopied(_ verb: DiagramPathVerb, _ elementPoints: UnsafePointer<CGPoint>) {
        expandHeldShape()
        let count = verb.pointCount
        reserve(verbs: 1, points: count)
        push(verb)
        for index in 0..<count { push(elementPoints[index]) }
        if verb == .move { subpathStart = elementPoints[0] }
    }

    // MARK: Reading

    /// Calls `body` with each element and its points as the lane holds them, which Core Graphics bounds and adds to other
    /// paths: a held shape made into its elements.
    func forEachStoredElement(_ body: (DiagramPathVerb, UnsafePointer<CGPoint>) -> Void) {
        guard !holdsShape else { return withHeldShapeExpanded { expanded in expanded.forEachStoredElement(body) } }
        var point = UnsafePointer(points)
        for index in 0..<verbCount {
            let verb = verbs[index]
            body(verb, point)
            point += verb.pointCount
        }
    }

    /// Calls `body` with each element as Core Graphics gives a path's elements out (`CGPathApply`): a held arc's last
    /// curve as it works that out from the arc's stored sine, cosine and tangent.
    func forEachElement(_ body: (DiagramPathVerb, UnsafePointer<CGPoint>) -> Void) {
        guard holdsShape else { return forEachStoredElement(body) }
        let shape = heldShape
        withHeldShapeExpanded { expanded in
            if let lastCurve = shape.writtenLastCurve, expanded.lastVerb == .cubicCurve {
                expanded.points[expanded.pointCount - 3] = lastCurve.control1
                expanded.points[expanded.pointCount - 2] = lastCurve.control2
                expanded.points[expanded.pointCount - 1] = lastCurve.end
            }
            expanded.forEachStoredElement(body)
        }
    }
}
