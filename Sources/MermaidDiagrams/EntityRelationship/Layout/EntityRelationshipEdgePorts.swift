/**
 * File: EntityRelationshipEdgePorts.swift
 * ---------------------------------------
 * Layer: Core
 * Description: Where relationships meet their boxes, the ends that share a side spread along it.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

import CoreGraphics

/// Where relationships meet their boxes. Those that meet one side of a box spread along it, in the order of where
/// they go, 18 points apart, or closer when the side is short, keeping 14 points from its ends, so that their marks
/// do not cover each other: Pele's.
struct EntityRelationshipEdgePorts {
    static let portSeparation: CGFloat = 18
    static let sideMargin: CGFloat = 14

    /// One end of a relationship on a side of a box.
    struct End {
        let relationshipIndex: Int
        let isFirstEntityEnd: Bool
        let entity: Int
        let side: DiagramSide
        /// Where, across the flow, the route's next point is: the order the ends take along the side.
        let neighborAcross: CGFloat
    }

    /// The page points of each relationship's ends, by relationship index; nil for an end not placed.
    private(set) var firstEntityPoints: [CGPoint?]
    private(set) var secondEntityPoints: [CGPoint?]

    init(ends: [End], relationshipCount: Int, boxCenters: [CGPoint], boxSizes: [CGSize]) {
        firstEntityPoints = Array(repeating: nil, count: relationshipCount)
        secondEntityPoints = Array(repeating: nil, count: relationshipCount)
        guard !ends.isEmpty else { return }
        // The ends in one list sorted by their side, then by where they go, by relationship and by the order they were
        // listed in: each side's ends together, in the order they take along it, as sorting each side's ends alone
        // ordered them (two ends of one side never share a relationship, a relationship with itself being a loop).
        var ordered = Array(ends.indices)
        ordered.sort { first, second in
            let firstEnd = ends[first]
            let secondEnd = ends[second]
            let firstSlot = Self.slot(of: firstEnd)
            let secondSlot = Self.slot(of: secondEnd)
            if firstSlot != secondSlot { return firstSlot < secondSlot }
            return (firstEnd.neighborAcross, firstEnd.relationshipIndex, first) < (secondEnd.neighborAcross, secondEnd.relationshipIndex, second)
        }
        var first = 0
        while first < ordered.count {
            let slot = Self.slot(of: ends[ordered[first]])
            var last = first + 1
            while last < ordered.count, Self.slot(of: ends[ordered[last]]) == slot { last += 1 }
            let entity = ends[ordered[first]].entity
            let side = ends[ordered[first]].side
            let count = last - first
            let length = side.isHorizontal ? boxSizes[entity].width : boxSizes[entity].height
            let step = count > 1 ? max(min(Self.portSeparation, (length - 2 * Self.sideMargin) / CGFloat(count - 1)), 0) : 0
            for position in 0..<count {
                let end = ends[ordered[first + position]]
                let offset = (CGFloat(position) - CGFloat(count - 1) / 2) * step
                let point = Self.sidePoint(center: boxCenters[entity], size: boxSizes[entity], side: side, offset: offset)
                if end.isFirstEntityEnd { firstEntityPoints[end.relationshipIndex] = point } else { secondEntityPoints[end.relationshipIndex] = point }
            }
            first = last
        }
    }

    /// The side an end is on, numbered by box and side.
    private static func slot(of end: End) -> Int { end.entity * 4 + sideNumber(end.side) }

    /// The point of a box's `side`, `offset` from the side's middle (rightward or downward).
    static func sidePoint(center: CGPoint, size: CGSize, side: DiagramSide, offset: CGFloat) -> CGPoint {
        switch side {
        case .top: CGPoint(x: center.x + offset, y: center.y - size.height / 2)
        case .bottom: CGPoint(x: center.x + offset, y: center.y + size.height / 2)
        case .left: CGPoint(x: center.x - size.width / 2, y: center.y + offset)
        case .right: CGPoint(x: center.x + size.width / 2, y: center.y + offset)
        }
    }

    /// The unit vector out of a box through `side`.
    static func outward(from side: DiagramSide) -> CGVector {
        switch side {
        case .top: CGVector(dx: 0, dy: -1)
        case .bottom: CGVector(dx: 0, dy: 1)
        case .left: CGVector(dx: -1, dy: 0)
        case .right: CGVector(dx: 1, dy: 0)
        }
    }

    private static func sideNumber(_ side: DiagramSide) -> Int {
        switch side {
        case .top: 0
        case .right: 1
        case .bottom: 2
        case .left: 3
        }
    }
}
