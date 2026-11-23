/**
 * File: FlowchartRouteEnds.swift
 * ------------------------------
 * Layer: Core
 * Description: Moves the end of a route from a node's layout box onto the outline of its shape, as Pele does.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import CoreGraphics

/// Pele's `endSide` and `insetRoute` (svg/shapes.ts): the layout leaves each end of an edge on a side of its node's
/// layout box, where its end was spread and settled; the drawing moves it straight in onto the outline of the shape
/// drawn in the box, keeping its place along the side. A group's box is its outline.
enum FlowchartRouteEnds {
    /// How near a side of the box an end must be to lie on it.
    static let sideTolerance: CGFloat = 0.5

    /// The end on the shape's outline, or nil for an end on no side of the box.
    static func outlinePoint(of end: CGPoint, center: CGPoint, boxSize: CGSize, shape: FlowchartNodeShape, shapeSize: CGSize) -> CGPoint? {
        let distanceX = end.x - center.x
        let distanceY = end.y - center.y
        let side: DiagramSide
        if abs(abs(distanceY) - boxSize.height / 2) < sideTolerance {
            side = distanceY < 0 ? .top : .bottom
        } else if abs(abs(distanceX) - boxSize.width / 2) < sideTolerance {
            side = distanceX < 0 ? .left : .right
        } else {
            return nil
        }
        return FlowchartEdgePorts.outlinePoint(center: center, shape: shape, size: shapeSize, side: side, offset: side.isHorizontal ? distanceX : distanceY)
    }
}
