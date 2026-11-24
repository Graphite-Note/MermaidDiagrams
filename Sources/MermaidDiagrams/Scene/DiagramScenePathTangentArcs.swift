/**
 * File: DiagramScenePathTangentArcs.swift
 * ---------------------------------------
 * Layer: Core
 * Description: The arc Core Graphics puts in a corner between two lines (`add_arc_to_point`), which rounds a rounded
 *              rectangle's corners, worked out in the corner's own frame as Core Graphics does.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import CoreGraphics

extension DiagramScenePath {
    /// The arc of `radius` tangent to the line from the current point to `corner` and to the line from `corner` to
    /// `next`, joined to the current point by a line, in the space `transform` takes to the page.
    mutating func appendTangentArc(corner: CGPoint, next: CGPoint, radius: CGFloat, transform: CGAffineTransform?) {
        var current = currentPoint
        if let transform { current = DiagramScenePathArithmetic.point(current, inverselyTransformedBy: transform) }
        let towardCorner = CGPoint(x: corner.x - current.x, y: corner.y - current.y)
        let towardNext = CGPoint(x: next.x - current.x, y: next.y - current.y)
        let isAtCorner = towardCorner.x == 0 && towardCorner.y == 0
        let rawAngle = DiagramScenePathArithmetic.angle(across: towardCorner.x, down: towardCorner.y)
        let angle = isAtCorner ? 0 : rawAngle
        let usedRadius = isAtCorner ? 0 : radius
        let turn = DiagramScenePathArithmetic.sineAndCosine(of: angle)
        // The corner and the next point in the frame of the first line: along it, and across it.
        let cornerAlongExact = (towardCorner.y * turn.sine).addingProduct(turn.cosine, towardCorner.x)
        let cornerAcrossExact = (towardCorner.y * turn.cosine).addingProduct(-turn.sine, towardCorner.x)
        let nextAlongExact = (towardNext.y * turn.sine).addingProduct(turn.cosine, towardNext.x)
        let nextAcrossExact = (towardNext.y * turn.cosine).addingProduct(-turn.sine, towardNext.x)
        let cornerAlong = cornerAlongExact + 0
        let cornerAcross = cornerAcrossExact + 0
        var cornerAngle: CGFloat = 0
        if !(cornerAlongExact == nextAlongExact && cornerAcrossExact == nextAcrossExact) {
            let secondLine = DiagramScenePathArithmetic.angle(across: (nextAlongExact + 0) - cornerAlong, down: (nextAcrossExact + 0) - cornerAcross)
            cornerAngle = CGFloat.pi - abs(secondLine)
        }
        var placement = TangentArcPlacement(distance: cornerAlong, across: cornerAcross)
        let halfSine = DiagramScenePathArithmetic.sine(of: cornerAngle * 0.5)
        if halfSine != 0 {
            let cotangent = abs(DiagramScenePathArithmetic.cosine(of: cornerAngle * 0.5) / halfSine)
            placement.radius = usedRadius
            placement.distance = cornerAlong.addingProduct(-usedRadius, cotangent)
            if !(nextAcrossExact <= cornerAcrossExact) {
                placement.endOffset = DiagramScenePathArithmetic.halfPi - cornerAngle
                placement.startOffset = -DiagramScenePathArithmetic.halfPi
                placement.across = usedRadius
            } else {
                placement.across = -usedRadius
                placement.endOffset = cornerAngle + -DiagramScenePathArithmetic.halfPi
                placement.startOffset = DiagramScenePathArithmetic.halfPi
            }
        }
        let center = CGPoint(x: current.x + ((placement.across * -turn.sine).addingProduct(turn.cosine, placement.distance) + 0),
                             y: current.y + ((placement.across * turn.cosine).addingProduct(turn.sine, placement.distance) + 0))
        appendArcBetweenAngles(center: center, radius: placement.radius, startAngle: angle + placement.startOffset, endAngle: angle + placement.endOffset,
                               isClockwise: nextAcrossExact <= cornerAcrossExact, transform: transform)
    }
}

/// Where a tangent arc's center lies in its corner's frame, and how its angles stand from the first line's.
private struct TangentArcPlacement {
    /// Along the first line from the current point to the tangent point.
    var distance: CGFloat
    /// Across the first line, to the center.
    var across: CGFloat
    var radius: CGFloat = 0
    var startOffset: CGFloat = 0
    var endOffset: CGFloat = 0
}
