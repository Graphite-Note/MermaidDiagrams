/**
 * File: FlowchartCurvedShapeDrawing.swift
 * ---------------------------------------
 * Layer: Core
 * Description: The flowchart node shapes Pele draws with arcs and curves: a delay, a lying cylinder, a paper tape, a
 *              folder, a bucket, a cloud, a display, stored data and braces.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

import CoreGraphics

/// The outlines and lines of the shapes Pele draws with arcs and quadratic curves, each as its SVG path data in
/// `svg/shapes.ts` reads, from the shape's center.
enum FlowchartCurvedShapeDrawing {
    /// The filled and stroked outline, or nil for a shape drawn otherwise.
    static func outline<Maker: DiagramPathMaking>(of shape: FlowchartNodeShape, in frame: CGRect, making maker: Maker) -> Maker.Path? {
        let halfWidth = frame.width / 2
        let halfHeight = frame.height / 2
        var pen = FlowchartShapePen(center: CGPoint(x: frame.midX, y: frame.midY), path: maker.makePath())
        switch shape {
        case .delay: drawDelay(with: &pen, halfWidth: halfWidth, halfHeight: halfHeight)
        case .horizontalCylinder: drawHorizontalCylinder(with: &pen, halfWidth: halfWidth, halfHeight: halfHeight)
        case .paperTape: drawPaperTape(with: &pen, halfWidth: halfWidth, halfHeight: halfHeight)
        case .folder: drawFolder(with: &pen, halfWidth: halfWidth, halfHeight: halfHeight)
        case .bucket: drawBucket(with: &pen, halfWidth: halfWidth, halfHeight: halfHeight)
        case .cloud: drawCloud(with: &pen, halfWidth: halfWidth, halfHeight: halfHeight)
        case .curvedTrapezoid: drawCurvedTrapezoid(with: &pen, halfWidth: halfWidth, halfHeight: halfHeight)
        case .bowTieRectangle: drawBowTieRectangle(with: &pen, halfWidth: halfWidth, halfHeight: halfHeight)
        default: return nil
        }
        pen.close()
        return pen.path
    }

    /// A rectangle whose right end is a half circle.
    private static func drawDelay<Path: DiagramPathRecording>(with pen: inout FlowchartShapePen<Path>, halfWidth: CGFloat, halfHeight: CGFloat) {
        pen.move(toX: -halfWidth, y: -halfHeight)
        pen.horizontal(toX: halfWidth - halfHeight)
        pen.arc(toX: halfWidth - halfHeight, y: halfHeight, radiusAcross: halfHeight, radiusDown: halfHeight, clockwise: true)
        pen.horizontal(toX: -halfWidth)
    }

    /// A cylinder lying on its side: the far half of each end's ellipse.
    private static func drawHorizontalCylinder<Path: DiagramPathRecording>(with pen: inout FlowchartShapePen<Path>, halfWidth: CGFloat, halfHeight: CGFloat) {
        let capDepth = FlowchartExtendedShapeGeometry.horizontalCylinderCapDepth(height: 2 * halfHeight)
        let left = -halfWidth + capDepth
        let right = halfWidth - capDepth
        pen.move(toX: left, y: -halfHeight)
        pen.horizontal(toX: right)
        pen.arc(toX: right, y: halfHeight, radiusAcross: capDepth, radiusDown: halfHeight, clockwise: true)
        pen.horizontal(toX: left)
        pen.arc(toX: left, y: -halfHeight, radiusAcross: capDepth, radiusDown: halfHeight, clockwise: true)
    }

    /// A box with a tab along the left of its top, at most 48 points long.
    private static func drawFolder<Path: DiagramPathRecording>(with pen: inout FlowchartShapePen<Path>, halfWidth: CGFloat, halfHeight: CGFloat) {
        let tab = min(2 * halfWidth * 0.4, 48)
        pen.move(toX: -halfWidth, y: -halfHeight)
        pen.horizontal(toX: -halfWidth + tab)
        pen.line(toX: -halfWidth + tab + 8, y: -halfHeight + 8)
        pen.horizontal(toX: halfWidth)
        pen.vertical(toY: halfHeight)
        pen.horizontal(toX: -halfWidth)
    }

    /// A display: pointed on the left, an arc on the right, 0.3 of its height deep.
    private static func drawCurvedTrapezoid<Path: DiagramPathRecording>(with pen: inout FlowchartShapePen<Path>, halfWidth: CGFloat, halfHeight: CGFloat) {
        let curve = 2 * halfHeight * 0.3
        pen.move(toX: -halfWidth + curve, y: -halfHeight)
        pen.horizontal(toX: halfWidth - curve)
        pen.arc(toX: halfWidth - curve, y: halfHeight, radiusAcross: curve, radiusDown: halfHeight, clockwise: true)
        pen.horizontal(toX: -halfWidth + curve)
        pen.line(toX: -halfWidth, y: 0)
    }

    /// Stored data: its right end curved in and its left end curved out, 0.2 of its height deep.
    private static func drawBowTieRectangle<Path: DiagramPathRecording>(with pen: inout FlowchartShapePen<Path>, halfWidth: CGFloat, halfHeight: CGFloat) {
        let curve = 2 * halfHeight * 0.2
        pen.move(toX: -halfWidth + curve, y: -halfHeight)
        pen.horizontal(toX: halfWidth)
        pen.arc(toX: halfWidth, y: halfHeight, radiusAcross: curve, radiusDown: halfHeight, clockwise: false)
        pen.horizontal(toX: -halfWidth + curve)
        pen.arc(toX: -halfWidth + curve, y: -halfHeight, radiusAcross: curve, radiusDown: halfHeight, clockwise: true)
    }

    /// A band whose top and bottom wave, 8 points in from the box's: Pele's `flag`.
    private static func drawPaperTape<Path: DiagramPathRecording>(with pen: inout FlowchartShapePen<Path>, halfWidth: CGFloat, halfHeight: CGFloat) {
        let bandHalfHeight = halfHeight - 8
        let quarter = halfWidth / 2
        pen.move(toX: -halfWidth, y: -bandHalfHeight)
        pen.quadratic(controlByX: quarter, y: -10, endByX: 2 * quarter, y: 0)
        pen.smoothQuadratic(endByX: 2 * quarter, y: 0)
        pen.vertical(toY: bandHalfHeight)
        pen.quadratic(controlByX: -quarter, y: 10, endByX: -2 * quarter, y: 0)
        pen.smoothQuadratic(endByX: -2 * quarter, y: 0)
    }

    /// The depth of a bucket's rim and bottom ellipses.
    private static let bucketRimDepth: CGFloat = 5

    /// A pail: the far half of its rim, its sides narrowing by a sixth of its height, the near half of its bottom.
    private static func drawBucket<Path: DiagramPathRecording>(with pen: inout FlowchartShapePen<Path>, halfWidth: CGFloat, halfHeight: CGFloat) {
        let taper = 2 * halfHeight / 6
        pen.move(toX: -halfWidth, y: -halfHeight + bucketRimDepth)
        pen.arc(toX: halfWidth, y: -halfHeight + bucketRimDepth, radiusAcross: halfWidth, radiusDown: bucketRimDepth, clockwise: true)
        pen.line(toX: halfWidth - taper, y: halfHeight - bucketRimDepth)
        pen.arc(toX: -halfWidth + taper, y: halfHeight - bucketRimDepth, radiusAcross: halfWidth - taper, radiusDown: bucketRimDepth, clockwise: true)
    }

    /// A cloud: four arcs over a flat bottom.
    private static func drawCloud<Path: DiagramPathRecording>(with pen: inout FlowchartShapePen<Path>, halfWidth: CGFloat, halfHeight: CGFloat) {
        let radius = halfHeight * 0.55
        pen.move(toX: -halfWidth + radius, y: halfHeight)
        pen.arc(toX: -halfWidth + radius * 0.6, y: -halfHeight * 0.1, radiusAcross: radius, radiusDown: radius, clockwise: true)
        pen.arc(toX: -halfWidth * 0.1, y: -halfHeight * 0.72, radiusAcross: halfWidth * 0.42, radiusDown: halfHeight * 0.7, clockwise: true)
        pen.arc(toX: halfWidth * 0.62, y: -halfHeight * 0.42, radiusAcross: halfWidth * 0.4, radiusDown: halfHeight * 0.62, clockwise: true)
        pen.arc(toX: halfWidth - radius, y: halfHeight, radiusAcross: radius * 1.05, radiusDown: radius * 1.05, clockwise: true)
    }

    /// The lines drawn over the outline (or alone, for braces), or nil.
    static func innerLines<Maker: DiagramPathMaking>(of shape: FlowchartNodeShape, in frame: CGRect, making maker: Maker) -> Maker.Path? {
        let halfWidth = frame.width / 2
        let halfHeight = frame.height / 2
        var pen = FlowchartShapePen(center: CGPoint(x: frame.midX, y: frame.midY), path: maker.makePath())
        switch shape {
        case .horizontalCylinder:
            let capDepth = FlowchartExtendedShapeGeometry.horizontalCylinderCapDepth(height: frame.height)
            pen.move(toX: halfWidth - capDepth, y: -halfHeight)
            pen.arc(toX: halfWidth - capDepth, y: halfHeight, radiusAcross: capDepth, radiusDown: halfHeight, clockwise: false)
        case .bucket:
            pen.move(toX: -halfWidth, y: -halfHeight + bucketRimDepth)
            pen.arc(toX: halfWidth, y: -halfHeight + bucketRimDepth, radiusAcross: halfWidth, radiusDown: bucketRimDepth, clockwise: false)
        case .linedCylinder:
            let capDepth = FlowchartShapeGeometry.cylinderCapDepth(width: frame.width)
            for rimY in [-halfHeight + capDepth, -halfHeight + capDepth + 8] {
                pen.move(toX: -halfWidth, y: rimY)
                pen.arc(toX: halfWidth, y: rimY, radiusAcross: halfWidth, radiusDown: capDepth, clockwise: false)
            }
        case .leftBrace: drawBrace(with: &pen, atX: -halfWidth + 12, halfHeight: halfHeight, opensLeft: true)
        case .rightBrace: drawBrace(with: &pen, atX: halfWidth - 12, halfHeight: halfHeight, opensLeft: false)
        case .braces:
            drawBrace(with: &pen, atX: -halfWidth + 12, halfHeight: halfHeight, opensLeft: true)
            drawBrace(with: &pen, atX: halfWidth - 12, halfHeight: halfHeight, opensLeft: false)
        default: return nil
        }
        return pen.path
    }

    /// A curly brace the height of the box, its ends at `x` and its point 12 points out, to the left or to the right.
    private static func drawBrace<Path: DiagramPathRecording>(with pen: inout FlowchartShapePen<Path>, atX x: CGFloat, halfHeight: CGFloat, opensLeft: Bool) {
        let step: CGFloat = opensLeft ? -6 : 6
        pen.move(toX: x, y: -halfHeight)
        pen.quadratic(controlByX: step, y: 0, endByX: step, y: 6)
        pen.vertical(toY: -6)
        pen.quadratic(controlByX: 0, y: 6, endByX: step, y: 6)
        pen.quadratic(controlByX: -step, y: 0, endByX: -step, y: 6)
        pen.vertical(toY: halfHeight - 6)
        pen.quadratic(controlByX: 0, y: 6, endByX: -step, y: 6)
    }
}
