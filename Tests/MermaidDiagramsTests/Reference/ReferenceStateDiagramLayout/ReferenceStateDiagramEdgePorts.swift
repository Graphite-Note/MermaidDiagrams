/**
 * File: ReferenceStateDiagramEdgePorts.swift
 * ------------------------------------------
 * Layer: Tests
 * Description: The 0.7.0 StateDiagramEdgePorts kept as the reference the 0.8.0 layout is checked against:
 *              where the lines to a state's notes meet the state, and the points of a state's box on its sides.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// Where the lines to a state's notes meet the state, and the points of a state's box on its sides. Transitions meet
/// their states where Pele's layout spread and settled their ends (`ReferenceStateDiagramRouteEnds`).
struct ReferenceStateDiagramEdgePorts {
    /// The gap between neighbouring lines on a side of a box, where it has room.
    static let portSeparation: CGFloat = 20
    /// Kept clear at each end of a box's side, for its corner.
    static let cornerClearance: CGFloat = 12

    /// Where `count` lines meeting one side of a state meet it, from the side's middle: spread along a box's side,
    /// at the middle of anything else.
    static func offsets(count: Int, placement: StateDiagramPortPlacement, sideLength: CGFloat) -> [CGFloat] {
        guard placement == .spread, count > 1 else { return Array(repeating: 0, count: count) }
        let step = min(portSeparation, max(0, sideLength - 2 * cornerClearance) / CGFloat(count - 1))
        return (0..<count).map { position in (CGFloat(position) - CGFloat(count - 1) / 2) * step }
    }

    /// The point of a state's bounding box on `side`, `offset` from the side's middle (rightward or downward). Every
    /// state's outline touches its box's sides at their middles, and a box's sides are straight away from its corners.
    static func sidePoint(center: CGPoint, size: CGSize, side: DiagramSide, offset: CGFloat) -> CGPoint {
        switch side {
        case .top: CGPoint(x: center.x + offset, y: center.y - size.height / 2)
        case .bottom: CGPoint(x: center.x + offset, y: center.y + size.height / 2)
        case .left: CGPoint(x: center.x - size.width / 2, y: center.y + offset)
        case .right: CGPoint(x: center.x + size.width / 2, y: center.y + offset)
        }
    }
}
