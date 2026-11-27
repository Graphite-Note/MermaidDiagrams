/**
 * File: RequirementEdgePorts.swift
 * --------------------------------
 * Layer: Core
 * Description: Where relations meet their boxes, as Pele's requirement renderer spreads them: at the middle of a side,
 *              or spread along it in the order of where they head when several share it.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 26/11/2026
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
        let edgeIndex: Int32
        let isSourceEnd: Bool
        let box: Int32
        let side: DiagramSide
        /// Where, along the side, the route's next point is.
        let toward: CGFloat
    }

    /// The page points of each edge's ends, by edge index, set where `isSourcePlaced` and `isTargetPlaced` say: spans of
    /// the thread's arena.
    let sourcePoints: ScratchSpan<CGPoint>
    let targetPoints: ScratchSpan<CGPoint>
    let isSourcePlaced: ScratchSpan<Bool>
    let isTargetPlaced: ScratchSpan<Bool>

    init(ends: ScratchSpan<End>, edgeCount: Int, centers: ScratchSpan<CGPoint>, sizes: ScratchSpan<CGSize>, arena: DiagramScratchArena) {
        sourcePoints = arena.uninitializedSpan(count: edgeCount)
        targetPoints = arena.uninitializedSpan(count: edgeCount)
        isSourcePlaced = arena.span(count: edgeCount, repeating: false)
        isTargetPlaced = arena.span(count: edgeCount, repeating: false)
        // The ends sorted by their side, then by where they head and the order they were listed in, as JavaScript's
        // stable sort orders them: each side's ends together, in the order they take along it. Sorted as an array of
        // them sorts, by the same sort on the same order.
        let ordered: ScratchSpan<Int> = arena.uninitializedSpan(count: ends.count)
        for index in 0..<ends.count { ordered[index] = index }
        var orderedBuffer = ordered.buffer
        orderedBuffer.sort { first, second in
            (Self.slot(of: ends[first]), ends[first].toward, first) < (Self.slot(of: ends[second]), ends[second].toward, second)
        }
        var first = 0
        while first < ordered.count {
            var last = first + 1
            while last < ordered.count, Self.slot(of: ends[ordered[last]]) == Self.slot(of: ends[ordered[first]]) { last += 1 }
            let box = Int(ends[ordered[first]].box)
            let side = ends[ordered[first]].side
            let count = last - first
            let span = (side.isHorizontal ? sizes[box].width : sizes[box].height) - 2 * Self.endMargin
            let step = count > 1 ? max(0, min(Self.endStep, span / CGFloat(count - 1))) : 0
            for position in 0..<count {
                let end = ends[ordered[first + position]]
                let offset = (CGFloat(position) - CGFloat(count - 1) / 2) * step
                let point = ClassDiagramEdgePorts.sidePoint(center: centers[box], size: sizes[box], side: side, offset: offset)
                if end.isSourceEnd {
                    sourcePoints[Int(end.edgeIndex)] = point
                    isSourcePlaced[Int(end.edgeIndex)] = true
                } else {
                    targetPoints[Int(end.edgeIndex)] = point
                    isTargetPlaced[Int(end.edgeIndex)] = true
                }
            }
            first = last
        }
    }

    /// The side an end is on, numbered by box and side.
    private static func slot(of end: End) -> Int { Int(end.box) * 4 + sideNumber(end.side) }

    private static func sideNumber(_ side: DiagramSide) -> Int {
        switch side {
        case .top: 0
        case .right: 1
        case .bottom: 2
        case .left: 3
        }
    }
}
