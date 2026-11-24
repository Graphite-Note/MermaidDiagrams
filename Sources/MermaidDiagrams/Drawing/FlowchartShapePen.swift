/**
 * File: FlowchartShapePen.swift
 * -----------------------------
 * Layer: Core
 * Description: Draws a node shape's path as Pele's SVG path data draws it, in coordinates from the shape's center, into a
 *              Core Graphics path or a lane.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

import CoreGraphics

/// Draws a path (a Core Graphics path or a lane) the way Pele writes a shape's SVG path data (`M`, `H`, `V`, `L`, `l`, `A`, `q`, `t`, `Z`),
/// each point given from the shape's center, so that a shape reads as Pele's `svg/shapes.ts` writes it.
struct FlowchartShapePen<Path: DiagramPathRecording> {
    let path: Path
    private let center: CGPoint
    /// Where the pen is, from the center.
    private var current = CGPoint.zero
    /// The control point of the last quadratic curve, from the center, which a smooth one reflects.
    private var lastQuadraticControl: CGPoint?

    /// A pen drawing into `path`, an empty path.
    init(center: CGPoint, path: Path) {
        self.center = center
        self.path = path
    }

    /// `M x,y`.
    mutating func move(toX x: CGFloat, y: CGFloat) {
        current = CGPoint(x: x, y: y)
        lastQuadraticControl = nil
        path.move(to: page(current))
    }

    /// `L x,y`.
    mutating func line(toX x: CGFloat, y: CGFloat) {
        current = CGPoint(x: x, y: y)
        lastQuadraticControl = nil
        path.addLine(to: page(current))
    }

    /// `l dx,dy`.
    mutating func line(byX across: CGFloat, y down: CGFloat) {
        line(toX: current.x + across, y: current.y + down)
    }

    /// `H x`.
    mutating func horizontal(toX x: CGFloat) {
        line(toX: x, y: current.y)
    }

    /// `V y`.
    mutating func vertical(toY y: CGFloat) {
        line(toX: current.x, y: y)
    }

    /// `A rx,ry 0 0 sweep x,y`: the small arc of an unturned ellipse, clockwise on the page when `clockwise` (SVG's
    /// sweep flag 1).
    mutating func arc(toX x: CGFloat, y: CGFloat, radiusAcross: CGFloat, radiusDown: CGFloat, clockwise: Bool) {
        let start = page(current)
        current = CGPoint(x: x, y: y)
        lastQuadraticControl = nil
        DiagramEllipticalArc.addArc(to: path, from: start, to: page(current), radii: CGSize(width: radiusAcross, height: radiusDown),
                                    sweepsWithIncreasingAngle: clockwise)
    }

    /// `q cx,cy x,y`: a quadratic curve, its control and end given from where the pen is.
    mutating func quadratic(controlByX controlAcross: CGFloat, y controlDown: CGFloat, endByX endAcross: CGFloat, y endDown: CGFloat) {
        let control = CGPoint(x: current.x + controlAcross, y: current.y + controlDown)
        current = CGPoint(x: current.x + endAcross, y: current.y + endDown)
        path.addQuadCurve(to: page(current), control: page(control))
        lastQuadraticControl = control
    }

    /// `t x,y`: a quadratic curve whose control reflects the last one's through where the pen is.
    mutating func smoothQuadratic(endByX endAcross: CGFloat, y endDown: CGFloat) {
        let control = lastQuadraticControl.map { last in CGPoint(x: 2 * current.x - last.x, y: 2 * current.y - last.y) } ?? current
        current = CGPoint(x: current.x + endAcross, y: current.y + endDown)
        path.addQuadCurve(to: page(current), control: page(control))
        lastQuadraticControl = control
    }

    /// `Z`.
    mutating func close() {
        lastQuadraticControl = nil
        path.closeSubpath()
    }

    /// A closed polygon through `corners`, from the center.
    mutating func polygon(_ corners: [CGPoint]) {
        guard let first = corners.first else { return }
        move(toX: first.x, y: first.y)
        for corner in corners.dropFirst() { line(toX: corner.x, y: corner.y) }
        close()
    }

    private func page(_ point: CGPoint) -> CGPoint {
        CGPoint(x: center.x + point.x, y: center.y + point.y)
    }
}
