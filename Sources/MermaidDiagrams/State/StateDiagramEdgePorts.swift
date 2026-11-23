/**
 * File: StateDiagramEdgePorts.swift
 * ---------------------------------
 * Layer: Core
 * Description: Where the lines to a state's notes meet the state, and the points of a state's box on its sides.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

import CoreGraphics

/// Where the lines to a state's notes meet the state, and the points of a state's box on its sides. Transitions meet
/// their states where Pele's layout spread and settled their ends (`StateDiagramRouteEnds`).
struct StateDiagramEdgePorts {
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

/// How the lines meeting one side of a state meet it.
enum StateDiagramPortPlacement: Equatable {
    /// Spread along the side, clear of its corners: a box.
    case spread
    /// Each where its line comes from, short of the ends, on the bar's long sides: a fork or a join.
    case facingTheirLines
    /// At the side's middle: a start, an end, a choice.
    case middle
}

extension StateDiagramStateKind {
    var portPlacement: StateDiagramPortPlacement {
        switch self {
        case .state: .spread
        case .fork, .join: .facingTheirLines
        case .start, .end, .choice: .middle
        }
    }
}
