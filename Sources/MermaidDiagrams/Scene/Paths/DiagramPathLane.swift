/**
 * File: DiagramPathLane.swift
 * ---------------------------
 * Layer: Core
 * Description: A handle to a path lane recording in the thread's scene workspace, with a Core Graphics mutable path's
 *              methods and reference semantics, and the same elements and bounds to the bit, without a Core Graphics
 *              object, an allocation per path or a retain.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

import CoreGraphics

/// A path a drawing records, as `CGMutablePath` records one: its methods change the lane it points at, so drawing code
/// written for a mutable path changes only where its paths are made (`DiagramSceneWorkspace.makeLane()`). The elements
/// and `boundsOfPath` are Core Graphics' own for the same calls, bit for bit (`DiagramPathLaneEquivalenceTests`). A lane
/// is a pointer into its thread's workspace and is valid only while the recording that made it lasts, which debug builds
/// check.
struct DiagramPathLane {
    let state: UnsafeMutablePointer<DiagramPathLaneState>
    /// The recording the lane was made in.
    private let generation: UInt32

    init(state: UnsafeMutablePointer<DiagramPathLaneState>) {
        self.state = state
        generation = state.pointee.generation
    }

    /// The lane's state, checked in debug builds to belong to the recording the lane was made in.
    @inline(__always)
    private var checked: UnsafeMutablePointer<DiagramPathLaneState> {
        assert(state.pointee.generation == generation, "a path lane used after the recording that made it")
        return state
    }

    var isEmpty: Bool { checked.pointee.isEmpty }
    var currentPoint: CGPoint { checked.pointee.currentPoint }
    /// Whether the lane went past its element limit and was emptied; its scene is refused.
    var hasOverflowed: Bool { checked.pointee.hasOverflowed }

    func move(to point: CGPoint) { checked.pointee.move(to: point) }
    func addLine(to point: CGPoint) { checked.pointee.addLine(to: point) }
    func addQuadCurve(to end: CGPoint, control: CGPoint) { checked.pointee.addQuadCurve(to: end, control: control) }
    func addCurve(to end: CGPoint, control1: CGPoint, control2: CGPoint) { checked.pointee.addCurve(to: end, control1: control1, control2: control2) }
    func closeSubpath() { checked.pointee.closeSubpath() }

    /// A move to the first point and lines to the others, as `CGPathAddLines` adds them.
    func addLines(between linePoints: [CGPoint]) {
        guard let first = linePoints.first else { return }
        let lane = checked
        lane.pointee.move(to: first)
        for index in 1..<linePoints.count { lane.pointee.addLine(to: linePoints[index]) }
    }

    func addRect(_ rect: CGRect) { checked.pointee.addRect(rect) }
    func addEllipse(in rect: CGRect) { checked.pointee.addEllipse(in: rect) }

    func addRoundedRect(in rect: CGRect, cornerWidth: CGFloat, cornerHeight: CGFloat, transform: CGAffineTransform? = nil) {
        checked.pointee.addRoundedRect(in: rect, cornerWidth: cornerWidth, cornerHeight: cornerHeight, transform: transform)
    }

    func addArc(center: CGPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, clockwise: Bool, transform: CGAffineTransform? = nil) {
        checked.pointee.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: clockwise, transform: transform)
    }

    /// `addPath(CGPath(roundedRect: rect, cornerWidth:, cornerHeight:, transform: nil))` with the radii clamped to half
    /// the sides, without making that path.
    func addPathOfRoundedRect(_ rect: CGRect, cornerWidth: CGFloat, cornerHeight: CGFloat) {
        checked.pointee.addPathOfRoundedRect(rect, cornerWidth: cornerWidth, cornerHeight: cornerHeight)
    }

    /// `other`'s elements after this lane's, as `CGMutablePath.addPath(_:)` adds them.
    func addPath(_ other: DiagramPathLane) {
        let lane = checked
        guard other.state != lane else {
            let copy = DiagramPathLaneCopy(of: other)
            return withExtendedLifetime(copy) { lane.pointee.addPath(copy.state.pointee) }
        }
        lane.pointee.addPath(other.checked.pointee)
    }

    /// `other`'s elements after this lane's and after `second`'s, as two calls of `addPath(_:)` add them, a shape `other`
    /// holds whole worked out once: when both lanes hold elements and end otherwise than with a move, Core Graphics adds
    /// the same elements to each, which are copied from this lane to `second`.
    func addPath(_ other: DiagramPathLane, alsoTo second: DiagramPathLane) {
        let lane = checked
        let secondLane = second.checked
        guard other.state.pointee.held != nil, other.state != lane, other.state != secondLane, lane != secondLane,
              Self.endsWithElementsOtherThanAMove(lane), Self.endsWithElementsOtherThanAMove(secondLane) else {
            addPath(other)
            second.addPath(other)
            return
        }
        let verbStart = lane.pointee.verbCount
        let pointStart = lane.pointee.pointCount
        lane.pointee.addPath(other.checked.pointee)
        secondLane.pointee.appendElements(of: lane.pointee, fromVerb: verbStart, point: pointStart)
    }

    /// Whether a lane has elements, holds no shape whole and does not end with a move, which a shape's first move
    /// would take the place of.
    private static func endsWithElementsOtherThanAMove(_ state: UnsafeMutablePointer<DiagramPathLaneState>) -> Bool {
        guard state.pointee.held == nil, let last = state.pointee.lastVerb else { return false }
        return last != .move
    }

    /// `other`'s elements through `transform` after this lane's, as `CGMutablePath.addPath(_:transform:)` adds them.
    func addPath(_ other: DiagramPathLane, transform: CGAffineTransform) {
        let lane = checked
        guard other.state != lane else {
            let copy = DiagramPathLaneCopy(of: other)
            return withExtendedLifetime(copy) { lane.pointee.addPath(copy.state.pointee, transform: transform) }
        }
        lane.pointee.addPath(other.checked.pointee, transform: transform)
    }

    /// The smallest rectangle holding the lane (`boundingBoxOfPath`), worked out when first asked.
    var boundsOfPath: CGRect { checked.pointee.boundsOfPath() }

    /// Calls `body` with each element and its points, as `CGPathApply` gives a path's elements out.
    func forEachElement(_ body: (DiagramPathVerb, UnsafePointer<CGPoint>) -> Void) {
        checked.pointee.forEachElement(body)
    }

    /// A Core Graphics path with the lane's elements, for a reader that needs one.
    func makePath() -> CGPath {
        let path = CGMutablePath()
        forEachElement { verb, elementPoints in
            switch verb {
            case .move: path.move(to: elementPoints[0])
            case .line: path.addLine(to: elementPoints[0])
            case .quadraticCurve: path.addQuadCurve(to: elementPoints[1], control: elementPoints[0])
            case .cubicCurve: path.addCurve(to: elementPoints[2], control1: elementPoints[0], control2: elementPoints[1])
            case .close: path.closeSubpath()
            }
        }
        return path
    }

    /// Appends a Core Graphics path's elements as it gives them out (`applyWithBlock`), each move starting a subpath.
    func appendElements(of path: CGPath) {
        let lane = checked
        path.applyWithBlock { element in
            let points = UnsafePointer(element.pointee.points)
            switch element.pointee.type {
            case .moveToPoint: lane.pointee.appendCopied(.move, points)
            case .addLineToPoint: lane.pointee.appendCopied(.line, points)
            case .addQuadCurveToPoint: lane.pointee.appendCopied(.quadraticCurve, points)
            case .addCurveToPoint: lane.pointee.appendCopied(.cubicCurve, points)
            case .closeSubpath: lane.pointee.appendCopied(.close, points)
            @unknown default: break
            }
        }
    }
}

/// A lane's elements copied into a state of their own for a moment, so that a lane can be added to itself as Core
/// Graphics adds a path to itself.
private final class DiagramPathLaneCopy {
    let state: UnsafeMutablePointer<DiagramPathLaneState>

    init(of lane: DiagramPathLane) {
        state = .allocate(capacity: 1)
        state.initialize(to: DiagramPathLaneState(verbCapacity: lane.state.pointee.verbCount, elementLimit: lane.state.pointee.elementLimit))
        state.pointee.copyContents(of: lane.state.pointee)
    }

    deinit {
        state.pointee.deallocate()
        state.deallocate()
    }
}

extension DiagramPathLaneState {
    /// `other`'s elements, each point through `transform`, after this lane's, as Core Graphics adds them: a held shape
    /// into an empty lane stays held, its transform followed by `transform`; any other lane's elements are copied with
    /// their points moved; a held shape's first move, after a move this lane ends with, replaces it unmoved.
    mutating func addPath(_ other: borrowing DiagramPathLaneState, transform: CGAffineTransform) {
        guard !other.isEmpty else { return }
        if isEmpty, let shape = other.held {
            var moved = shape
            moved.transform = DiagramPathArithmetic.concatenation(shape.transform, then: transform)
            moved.wholeTurnArc = shape.wholeTurnArc.map { arc in
                DiagramPathWholeTurnArc(center: arc.center, radius: arc.radius, startAngle: arc.startAngle, sweep: arc.sweep,
                                        transform: DiagramPathArithmetic.concatenation(arc.transform ?? .identity, then: transform))
            }
            return hold(moved)
        }
        expandHeldShape()
        // After a move this lane ends with, a held shape's first move takes its place as Core Graphics puts it there:
        // the element's point not moved through `transform`, unlike the rest, while the subpath starts at the moved one.
        var replacesTrailingMove = other.held != nil && lastVerb == .move
        other.forEachStoredElement { verb, elementPoints in
            if replacesTrailingMove, verb == .move {
                replacesTrailingMove = false
                return replaceTrailingMove(writing: elementPoints[0], startingAt: DiagramPathArithmetic.point(elementPoints[0], transformedBy: transform))
            }
            replacesTrailingMove = false
            appendMoved(verb, elementPoints, transform: transform)
        }
    }

    /// One element with its points through `transform`, copied as it is.
    private mutating func appendMoved(_ verb: DiagramPathVerb, _ elementPoints: UnsafePointer<CGPoint>, transform: CGAffineTransform) {
        var moved = (CGPoint.zero, CGPoint.zero, CGPoint.zero)
        withUnsafeMutableBytes(of: &moved) { bytes in
            let movedPoints = bytes.baseAddress.unsafelyUnwrapped.assumingMemoryBound(to: CGPoint.self)
            for index in 0..<verb.pointCount { movedPoints[index] = DiagramPathArithmetic.point(elementPoints[index], transformedBy: transform) }
            appendCopied(verb, UnsafePointer(movedPoints))
        }
    }
}
