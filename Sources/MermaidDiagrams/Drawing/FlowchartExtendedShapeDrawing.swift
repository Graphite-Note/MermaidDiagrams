/**
 * File: FlowchartExtendedShapeDrawing.swift
 * -----------------------------------------
 * Layer: Core
 * Description: The outlines and inner lines of the flowchart node shapes written by name only, as Pele draws them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// The outline (filled in the surface color and stroked in the border color) and the lines over it of each shape beyond
/// Mermaid's classic ones, as Pele's `svg/shapes.ts` draws them. The shapes painted piece by piece (a person, stacked
/// documents, a fork's bar) are `FlowchartLayeredShapeDrawing`'s, and braces have no outline, only their lines.
enum FlowchartExtendedShapeDrawing {
    /// The corner radius Pele's `rounded` gives a box: `--pele-radius`.
    private static let boxCornerRadius = FlowchartShapeDrawing.rectangleCornerRadius

    /// The filled and stroked outline, or nil for a shape without one.
    static func outline(of shape: FlowchartNodeShape, in frame: CGRect) -> CGPath? {
        if let corners = polygonCorners(of: shape, width: frame.width, height: frame.height) {
            var pen = FlowchartShapePen(center: CGPoint(x: frame.midX, y: frame.midY))
            pen.polygon(corners)
            return pen.path
        }
        switch shape {
        case .ellipse, .smallCircle, .crossedCircle: return CGPath(ellipseIn: frame, transform: nil)
        case .linedRectangle, .dividedRectangle, .windowPane, .console, .browser, .taggedRectangle:
            return roundedRectangle(frame, radius: boxCornerRadius)
        case .linedCylinder: return FlowchartShapeDrawing.cylinderBody(in: frame)
        case .document, .taggedDocument, .linedDocument: return wave(width: frame.width, height: frame.height, center: CGPoint(x: frame.midX, y: frame.midY))
        default: return FlowchartCurvedShapeDrawing.outline(of: shape, in: frame)
        }
    }

    /// The corners of a shape drawn as a polygon, from its center, clockwise from its top; nil for another shape.
    private static func polygonCorners(of shape: FlowchartNodeShape, width: CGFloat, height: CGFloat) -> [CGPoint]? {
        let left = -width / 2
        let right = width / 2
        let top = -height / 2
        let bottom = height / 2
        let notch: CGFloat = 10
        func corner(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
        switch shape {
        case .card: return [corner(left + notch, top), corner(right, top), corner(right, bottom), corner(left, bottom), corner(left, top + notch)]
        case .triangle: return [corner(0, top), corner(right, bottom), corner(left, bottom)]
        case .flippedTriangle: return [corner(left, top), corner(right, top), corner(0, bottom)]
        case .slopedRectangle: return [corner(left, top + 10), corner(right, top), corner(right, bottom), corner(left, bottom)]
        case .notchedPentagon:
            return [corner(left + notch, top), corner(right - notch, top), corner(right, top + notch), corner(right, bottom), corner(left, bottom),
                    corner(left, top + notch)]
        case .hourglass: return [corner(left, top), corner(right, top), corner(left, bottom), corner(right, bottom)]
        case .lightningBolt:
            return [corner(width * 0.15, top), corner(left, height * 0.08), corner(-width * 0.05, height * 0.08), corner(-width * 0.15, bottom),
                    corner(right, -height * 0.08), corner(width * 0.05, -height * 0.08)]
        case .bang: return bangCorners(width: width, height: height)
        default: return nil
        }
    }

    /// A burst of fourteen spikes, each point on the ellipse of the box and each notch at 0.82 of it.
    private static func bangCorners(width: CGFloat, height: CGFloat) -> [CGPoint] {
        let spikeCount = 14
        let notchDepth: CGFloat = 0.82
        return (0..<(2 * spikeCount)).map { index in
            let angle = CGFloat.pi * CGFloat(index) / CGFloat(spikeCount) - CGFloat.pi / 2
            let scale = index.isMultiple(of: 2) ? 1 : notchDepth
            return CGPoint(x: cos(angle) * width / 2 * scale, y: sin(angle) * height / 2 * scale)
        }
    }

    /// The lines drawn over the filled outline, or nil.
    static func innerLines(of shape: FlowchartNodeShape, in frame: CGRect) -> CGPath? {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let halfWidth = frame.width / 2
        let halfHeight = frame.height / 2
        var pen = FlowchartShapePen(center: center)
        switch shape {
        case .linedRectangle: pen.move(toX: -halfWidth + 8, y: -halfHeight); pen.vertical(toY: halfHeight)
        case .dividedRectangle: pen.move(toX: -halfWidth, y: -halfHeight + 8); pen.horizontal(toX: halfWidth)
        case .windowPane:
            pen.move(toX: -halfWidth + 8, y: -halfHeight); pen.vertical(toY: halfHeight)
            pen.move(toX: -halfWidth, y: -halfHeight + 8); pen.horizontal(toX: halfWidth)
        case .taggedRectangle: pen.move(toX: halfWidth - 12, y: halfHeight); pen.line(toX: halfWidth, y: halfHeight - 12)
        case .taggedDocument: pen.move(toX: halfWidth - 12, y: halfHeight - 14); pen.line(toX: halfWidth, y: halfHeight - 26)
        case .linedDocument: pen.move(toX: -halfWidth + 8, y: -halfHeight); pen.vertical(toY: halfHeight - 6)
        case .crossedCircle:
            let diagonal = halfWidth * CGFloat(0.5).squareRoot()
            pen.move(toX: -diagonal, y: -diagonal); pen.line(toX: diagonal, y: diagonal)
            pen.move(toX: diagonal, y: -diagonal); pen.line(toX: -diagonal, y: diagonal)
        case .console:
            pen.move(toX: -halfWidth, y: -halfHeight + 12); pen.horizontal(toX: halfWidth)
            pen.move(toX: -halfWidth + 7, y: -halfHeight + 4); pen.line(byX: 3, y: 2.5); pen.line(byX: -3, y: 2.5)
            pen.move(toX: -halfWidth + 13, y: -halfHeight + 9); pen.line(byX: 4, y: 0)
        case .browser: return browserLines(in: frame)
        default: return FlowchartCurvedShapeDrawing.innerLines(of: shape, in: frame)
        }
        return pen.path
    }

    /// A browser's title bar: its lower line and three dots.
    private static func browserLines(in frame: CGRect) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: frame.minX, y: frame.minY + 12))
        path.addLine(to: CGPoint(x: frame.maxX, y: frame.minY + 12))
        let dotRadius: CGFloat = 1.5
        for index in 0..<3 {
            let dotCenter = CGPoint(x: frame.minX + 8 + CGFloat(index) * 7, y: frame.minY + 6)
            path.addEllipse(in: CGRect(x: dotCenter.x - dotRadius, y: dotCenter.y - dotRadius, width: 2 * dotRadius, height: 2 * dotRadius))
        }
        return path
    }

    /// A document's sheet, `width` by `height` around `center`: straight on three sides, its bottom a wave 10 points up
    /// from the box's bottom, Pele's `wave`.
    static func wave(width: CGFloat, height: CGFloat, center: CGPoint) -> CGPath {
        let halfWidth = width / 2
        let quarter = width / 4
        var pen = FlowchartShapePen(center: center)
        pen.move(toX: -halfWidth, y: -height / 2)
        pen.horizontal(toX: halfWidth)
        pen.vertical(toY: height / 2 - 10)
        pen.quadratic(controlByX: -quarter, y: -12, endByX: -2 * quarter, y: 0)
        pen.smoothQuadratic(endByX: -2 * quarter, y: 0)
        pen.close()
        return pen.path
    }

    /// A rectangle with its corners rounded, the radius kept within half its sides as SVG keeps it.
    static func roundedRectangle(_ frame: CGRect, radius: CGFloat) -> CGPath {
        let fitted = max(0, min(radius, frame.width / 2, frame.height / 2))
        return CGPath(roundedRect: frame, cornerWidth: fitted, cornerHeight: fitted, transform: nil)
    }
}
