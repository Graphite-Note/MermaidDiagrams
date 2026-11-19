/**
 * File: RequirementEdgePorts.swift
 * --------------------------------
 * Layer: Core
 * Description: Where relations meet their boxes, as Pele's requirement renderer spreads them: at the middle of a side,
 *              or spread along it in the order of where they head when several share it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// Where relations meet their boxes, as Pele's `spreadEnds` sets them: the layout attaches every end to the middle of a
/// box's side; ends that share a side are spread along it, 28 points apart or closer where the side, less 14 points at
/// each end, is too short, in the order of where they head, so that their marks do not sit on each other.
struct RequirementEdgePorts {
    static let endStep: CGFloat = 28
    static let endMargin: CGFloat = 14

    /// One end of a relation on a side of a box.
    struct End {
        let edgeIndex: Int
        let isSourceEnd: Bool
        let box: Int
        let side: DiagramSide
        /// Where, along the side, the route's next point is.
        let toward: CGFloat
    }

    /// The page points of each edge's ends, by edge index; nil for an edge with no end placed.
    private(set) var sourcePoints: [CGPoint?]
    private(set) var targetPoints: [CGPoint?]

    init(ends: [End], edgeCount: Int, centers: [CGPoint], sizes: [CGSize]) {
        sourcePoints = Array(repeating: nil, count: edgeCount)
        targetPoints = Array(repeating: nil, count: edgeCount)
        var endsBySide: [Int: [(order: Int, end: End)]] = [:]
        for (order, end) in ends.enumerated() { endsBySide[end.box * 4 + Self.sideNumber(end.side), default: []].append((order, end)) }
        for sideEnds in endsBySide.values {
            // JavaScript's sort is stable: ends heading to one place keep the order they were listed in.
            let ordered = sideEnds.sorted { first, second in (first.end.toward, first.order) < (second.end.toward, second.order) }.map(\.end)
            let box = ordered[0].box
            let side = ordered[0].side
            let span = (side.isHorizontal ? sizes[box].width : sizes[box].height) - 2 * Self.endMargin
            let step = ordered.count > 1 ? max(0, min(Self.endStep, span / CGFloat(ordered.count - 1))) : 0
            for (position, end) in ordered.enumerated() {
                let offset = (CGFloat(position) - CGFloat(ordered.count - 1) / 2) * step
                let point = ClassDiagramEdgePorts.sidePoint(center: centers[box], size: sizes[box], side: side, offset: offset)
                if end.isSourceEnd { sourcePoints[end.edgeIndex] = point } else { targetPoints[end.edgeIndex] = point }
            }
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
