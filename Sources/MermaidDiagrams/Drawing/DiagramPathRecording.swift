/**
 * File: DiagramPathRecording.swift
 * --------------------------------
 * Layer: Core
 * Description: What drawing code records its paths into, so that one drawing serves both kinds of path: Core Graphics'
 *              own, for the public drawing parts, and the lanes of the thread's scene workspace, for the scene.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics

/// A path being recorded, with a Core Graphics mutable path's methods and its reference semantics: a lane of the
/// thread's scene workspace (`DiagramPathLane`), or a Core Graphics path (`DiagramCoreGraphicsPath`). Both record the
/// same elements for the same calls, bit for bit.
protocol DiagramPathRecording {
    var isEmpty: Bool { get }
    func move(to point: CGPoint)
    func addLine(to point: CGPoint)
    func addQuadCurve(to end: CGPoint, control: CGPoint)
    func addCurve(to end: CGPoint, control1: CGPoint, control2: CGPoint)
    func closeSubpath()
    func addLines(between linePoints: [CGPoint])
    func addRect(_ rect: CGRect)
    func addEllipse(in rect: CGRect)
    /// `other`'s elements after this path's, as `CGMutablePath.addPath(_:)` adds them.
    func addPath(_ other: Self)
    /// `other`'s elements after this path's and after `second`'s, as two calls of `addPath(_:)` add them.
    func addPath(_ other: Self, alsoTo second: Self)
}

/// Makes the paths a drawing records into: new empty paths, and the shapes Core Graphics makes whole.
protocol DiagramPathMaking {
    associatedtype Path: DiagramPathRecording
    /// A new empty path (`CGMutablePath()`).
    func makePath() -> Path
    /// `CGPath(rect:transform: nil)`.
    func rectangle(_ rect: CGRect) -> Path
    /// `CGPath(roundedRect:cornerWidth:cornerHeight:transform: nil)`.
    func roundedRectangle(_ rect: CGRect, cornerWidth: CGFloat, cornerHeight: CGFloat) -> Path
    /// `CGPath(ellipseIn:transform: nil)`.
    func ellipse(in rect: CGRect) -> Path
    /// How many paths made for a moment are out: `givePathsBack(downTo:)` takes back those made after.
    var madePathCount: Int { get }
    /// Takes back the paths made after `count` were out, which are not used again: their room serves the next ones.
    func givePathsBack(downTo count: Int)
}

extension DiagramPathLane: DiagramPathRecording {}

extension DiagramSceneWorkspace: DiagramPathMaking {
    func makePath() -> DiagramPathLane { makeLane() }
    var madePathCount: Int { handedOutLaneCount }
    func givePathsBack(downTo count: Int) { giveLanesBack(downTo: count) }
}

/// A Core Graphics path a drawing records: a mutable one it adds to, or a shape Core Graphics made whole, which is only
/// added to others.
struct DiagramCoreGraphicsPath: DiagramPathRecording {
    let path: CGPath
    private let mutablePath: CGMutablePath?

    init(mutable path: CGMutablePath) {
        self.path = path
        mutablePath = path
    }

    init(made path: CGPath) {
        self.path = path
        mutablePath = nil
    }

    private var recorded: CGMutablePath {
        guard let mutablePath else { preconditionFailure("a shape made whole is not added to") }
        return mutablePath
    }

    var isEmpty: Bool { path.isEmpty }
    func move(to point: CGPoint) { recorded.move(to: point) }
    func addLine(to point: CGPoint) { recorded.addLine(to: point) }
    func addQuadCurve(to end: CGPoint, control: CGPoint) { recorded.addQuadCurve(to: end, control: control) }
    func addCurve(to end: CGPoint, control1: CGPoint, control2: CGPoint) { recorded.addCurve(to: end, control1: control1, control2: control2) }
    func closeSubpath() { recorded.closeSubpath() }
    func addLines(between linePoints: [CGPoint]) { recorded.addLines(between: linePoints) }
    func addRect(_ rect: CGRect) { recorded.addRect(rect) }
    func addEllipse(in rect: CGRect) { recorded.addEllipse(in: rect) }
    func addPath(_ other: DiagramCoreGraphicsPath) { recorded.addPath(other.path) }

    func addPath(_ other: DiagramCoreGraphicsPath, alsoTo second: DiagramCoreGraphicsPath) {
        addPath(other)
        second.addPath(other)
    }
}

/// Makes Core Graphics paths, as the public drawing parts have them.
struct DiagramCoreGraphicsPaths: DiagramPathMaking {
    func makePath() -> DiagramCoreGraphicsPath { DiagramCoreGraphicsPath(mutable: CGMutablePath()) }
    func rectangle(_ rect: CGRect) -> DiagramCoreGraphicsPath { DiagramCoreGraphicsPath(made: CGPath(rect: rect, transform: nil)) }

    func roundedRectangle(_ rect: CGRect, cornerWidth: CGFloat, cornerHeight: CGFloat) -> DiagramCoreGraphicsPath {
        DiagramCoreGraphicsPath(made: CGPath(roundedRect: rect, cornerWidth: cornerWidth, cornerHeight: cornerHeight, transform: nil))
    }

    func ellipse(in rect: CGRect) -> DiagramCoreGraphicsPath { DiagramCoreGraphicsPath(made: CGPath(ellipseIn: rect, transform: nil)) }
    var madePathCount: Int { 0 }
    func givePathsBack(downTo count: Int) {}
}
