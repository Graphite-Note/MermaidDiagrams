/**
 * File: DiagramCurvedPathRecording.swift
 * --------------------------------------
 * Layer: Core
 * Description: The rounded rectangles and arcs a drawing adds to a path it records, for the drawings of the sequence,
 *              railroad, event modeling and user journey diagrams, which add them to Core Graphics paths and to lanes.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics

/// A path being recorded that also takes `CGMutablePath`'s rounded rectangles and arcs: a lane of the thread's scene
/// workspace or a Core Graphics path, which record the same elements for the same calls, bit for bit.
protocol DiagramCurvedPathRecording: DiagramPathRecording {
    /// `CGMutablePath.addRoundedRect(in:cornerWidth:cornerHeight:transform:)`, nil standing for the identity.
    func addRoundedRect(in rect: CGRect, cornerWidth: CGFloat, cornerHeight: CGFloat, transform: CGAffineTransform?)
    /// `CGMutablePath.addArc(center:radius:startAngle:endAngle:clockwise:transform:)`, nil standing for the identity.
    func addArc(center: CGPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, clockwise: Bool, transform: CGAffineTransform?)
}

extension DiagramCurvedPathRecording {
    func addRoundedRect(in rect: CGRect, cornerWidth: CGFloat, cornerHeight: CGFloat) {
        addRoundedRect(in: rect, cornerWidth: cornerWidth, cornerHeight: cornerHeight, transform: nil)
    }

    func addArc(center: CGPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, clockwise: Bool) {
        addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: clockwise, transform: nil)
    }
}

extension DiagramPathLane: DiagramCurvedPathRecording {}

extension DiagramCoreGraphicsPath: DiagramCurvedPathRecording {}

extension DiagramPathMaking {
    /// Adds `CGPath(roundedRect:cornerWidth:cornerHeight:transform: nil)` to `path`, as `addPath(_:)` adds it, through a
    /// path made for a moment and given back.
    func addMadeRoundedRectangle(_ rect: CGRect, cornerWidth: CGFloat, cornerHeight: CGFloat, to path: Path) {
        let madeCount = madePathCount
        path.addPath(roundedRectangle(rect, cornerWidth: cornerWidth, cornerHeight: cornerHeight))
        givePathsBack(downTo: madeCount)
    }

    /// Adds an edge's line (`DiagramEdgeDrawing.path(_:)`) to `path`, as `addPath(_:)` adds it, through a path made for
    /// a moment and given back.
    func addEdgeLine(_ line: DiagramPath, to path: Path) {
        let madeCount = madePathCount
        let drawn = makePath()
        DiagramEdgeDrawing.record(line, into: drawn)
        path.addPath(drawn)
        givePathsBack(downTo: madeCount)
    }
}
