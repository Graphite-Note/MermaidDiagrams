/**
 * File: DiagramPathTangentArcs.swift
 * ----------------------------------
 * Layer: Core
 * Description: The arc Core Graphics puts in a corner between two lines (`add_arc_to_point`), which rounds a rounded
 *              rectangle's corners, worked out in the corner's own frame as Core Graphics does.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics

extension DiagramPathLaneState {
    /// The arc of `radius` tangent to the line from the current point to `corner` and to the line from `corner` to
    /// `next`, joined to the current point by a line, in the space `transform` takes to the page.
    mutating func appendTangentArc(corner: CGPoint, next: CGPoint, radius: CGFloat, transform: CGAffineTransform?) {
        var current = currentPoint
        if let transform { current = DiagramPathArithmetic.point(current, inverselyTransformedBy: transform) }
        let towardCorner = CGPoint(x: corner.x - current.x, y: corner.y - current.y)
        let towardNext = CGPoint(x: next.x - current.x, y: next.y - current.y)
        let isAtCorner = towardCorner.x == 0 && towardCorner.y == 0
        let rawAngle = DiagramPathArithmetic.angle(across: towardCorner.x, down: towardCorner.y)
        let angle = isAtCorner ? 0 : rawAngle
        let turn = DiagramPathArithmetic.sineAndCosine(of: angle)
        // The corner and the next point in the frame of the first line: along it, and across it.
        let frame = DiagramPathTangentArcFrame(
            cornerAlong: (towardCorner.y * turn.sine).addingProduct(turn.cosine, towardCorner.x),
            cornerAcross: (towardCorner.y * turn.cosine).addingProduct(-turn.sine, towardCorner.x),
            nextAlong: (towardNext.y * turn.sine).addingProduct(turn.cosine, towardNext.x),
            nextAcross: (towardNext.y * turn.cosine).addingProduct(-turn.sine, towardNext.x))
        let placement = frame.placement(radius: isAtCorner ? 0 : radius)
        let center = CGPoint(x: current.x + ((placement.across * -turn.sine).addingProduct(turn.cosine, placement.distance) + 0),
                             y: current.y + ((placement.across * turn.cosine).addingProduct(turn.sine, placement.distance) + 0))
        appendArcBetweenAngles(center: center, radius: placement.radius, startAngle: angle + placement.startOffset, endAngle: angle + placement.endOffset,
                               isClockwise: frame.turnsClockwise, transform: transform)
    }
}

/// A tangent arc's corner and next point in the frame of its first line, as Core Graphics works them out (each a fused
/// sum, not yet rounded through `+ 0`).
private struct DiagramPathTangentArcFrame {
    let cornerAlong: CGFloat
    let cornerAcross: CGFloat
    let nextAlong: CGFloat
    let nextAcross: CGFloat

    /// Whether the second line turns clockwise from the first, on a page whose y runs up.
    var turnsClockwise: Bool {
        nextAcross <= cornerAcross
    }

    /// Where the arc's center lies along and across the first line, its radius, and its angles from the first line's.
    func placement(radius: CGFloat) -> (distance: CGFloat, across: CGFloat, radius: CGFloat, startOffset: CGFloat, endOffset: CGFloat) {
        let along = cornerAlong + 0
        let acrossCorner = cornerAcross + 0
        var cornerAngle: CGFloat = 0
        if !(cornerAlong == nextAlong && cornerAcross == nextAcross) {
            let secondLine = DiagramPathArithmetic.angle(across: (nextAlong + 0) - along, down: (nextAcross + 0) - acrossCorner)
            cornerAngle = CGFloat.pi - abs(secondLine)
        }
        let halfSine = DiagramPathArithmetic.sine(of: cornerAngle * 0.5)
        guard halfSine != 0 else { return (along, acrossCorner, 0, 0, 0) }
        let cotangent = abs(DiagramPathArithmetic.cosine(of: cornerAngle * 0.5) / halfSine)
        let distance = along.addingProduct(-radius, cotangent)
        guard turnsClockwise else { return (distance, radius, radius, -DiagramPathArithmetic.halfPi, DiagramPathArithmetic.halfPi - cornerAngle) }
        return (distance, -radius, radius, DiagramPathArithmetic.halfPi, cornerAngle + -DiagramPathArithmetic.halfPi)
    }
}
