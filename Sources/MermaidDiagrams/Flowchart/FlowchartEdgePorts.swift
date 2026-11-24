/**
 * File: FlowchartEdgePorts.swift
 * ------------------------------
 * Layer: Core
 * Description: Where a flowchart's edges meet their nodes: the ends on one side spread along it, then moved onto the
 *              shape's outline, in the scratch arena.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.5
 * Date: 24/11/2026
 */

import CoreGraphics

/// Where edges meet their nodes. The edges that meet one side of a node spread along it, in the order of where they
/// come from, a port gap apart or closer when the side is short, so that they do not all meet in one point; each end
/// is then moved from the bounding box onto the shape's outline. Every list is a span of the calling thread's arena.
enum FlowchartEdgePorts {
    /// The gap between neighbouring edges on a side, where it has room: Pele's.
    static let portSeparation: CGFloat = 20

    /// One end of an edge on a side of a node.
    struct End {
        let edgeIndex: Int
        let isSourceEnd: Bool
        let node: Int
        let side: DiagramSide
        /// Where, across the flow, the route's next point is: the order the ends take along the side.
        let neighborAcross: CGFloat
    }

    /// What the ends meet, by item (a node, or a box numbered after the nodes): its center on the page, its size, and
    /// whether the ends on one of its sides spread along it (when not, they all meet the side's middle). A node's shape
    /// is the one the layout meets (`FlowchartMeasurement.layoutShape`), a box's a rectangle.
    struct Items {
        let centers: ScratchSpan<CGPoint>
        let sizes: ScratchSpan<CGSize>
        let spreadsEnds: ScratchSpan<Bool>

        init(count: Int, arena: DiagramScratchArena) {
            centers = arena.uninitializedSpan(count: count)
            sizes = arena.uninitializedSpan(count: count)
            spreadsEnds = arena.uninitializedSpan(count: count)
        }
    }

    /// Where each edge's ends were placed on the page, by edge index, and whether they were.
    struct Points {
        let source: ScratchSpan<CGPoint>
        let target: ScratchSpan<CGPoint>
        let isSourcePlaced: ScratchSpan<Bool>
        let isTargetPlaced: ScratchSpan<Bool>

        init(edgeCount: Int, arena: DiagramScratchArena) {
            source = arena.uninitializedSpan(count: edgeCount)
            target = arena.uninitializedSpan(count: edgeCount)
            isSourcePlaced = arena.span(count: edgeCount, repeating: false)
            isTargetPlaced = arena.span(count: edgeCount, repeating: false)
        }

        /// The source end of `edgeIndex`, or nil when it was not placed.
        @inline(__always)
        func sourcePoint(of edgeIndex: Int) -> CGPoint? { isSourcePlaced[edgeIndex] ? source[edgeIndex] : nil }

        @inline(__always)
        func targetPoint(of edgeIndex: Int) -> CGPoint? { isTargetPlaced[edgeIndex] ? target[edgeIndex] : nil }
    }

    /// A point a side's ends keep half a port gap from, as an offset from the side's middle: where another edge crosses a
    /// box's border there. `sideKey` is the side's.
    struct KeptPoint {
        let sideKey: Int
        let offset: CGFloat
    }

    /// Places `ends` into `points`. `keptClear` is sorted by side, each side's points in the order they were found.
    static func place(_ ends: ScratchSpan<End>, items: Items, of diagram: FlowchartDiagram, measured: FlowchartMeasurement,
                      keptClear: ScratchSpan<KeptPoint>, into points: Points, arena: DiagramScratchArena) {
        let mark = arena.mark()
        defer { arena.release(to: mark) }
        // The ends grouped by side, side after side, each side's in the order they come: one list instead of a list per
        // side. Each side's ends are then sorted in place as its own list would have been.
        let sideCount = items.centers.count * DiagramSide.allCases.count
        let sideStart = arena.span(count: sideCount + 1, repeating: 0)
        for end in ends { sideStart[sideKey(node: end.node, side: end.side) + 1] += 1 }
        for side in 0..<sideCount { sideStart[side + 1] += sideStart[side] }
        let grouped: ScratchSpan<End> = arena.uninitializedSpan(count: ends.count)
        let fill = arena.copy(of: sideStart.part(0..<sideCount))
        for end in ends {
            let key = sideKey(node: end.node, side: end.side)
            grouped[fill[key]] = end
            fill[key] += 1
        }
        for key in 0..<sideCount where sideStart[key + 1] > sideStart[key] {
            var side = grouped.part(sideStart[key]..<sideStart[key + 1]).buffer
            side.sort { first, second in (first.neighborAcross, first.edgeIndex) < (second.neighborAcross, second.edgeIndex) }
            let ordered = grouped.part(sideStart[key]..<sideStart[key + 1])
            let item = ordered[0].node
            let shape = item < diagram.nodeCount ? measured.layoutShape(of: item, in: diagram) : .rectangle
            placeSide(ordered, shape: shape, items: items, keptClear: keptClear, into: points, arena: arena)
        }
    }

    /// The ends of one side, in their order along it, spread around its middle and moved onto the shape's outline.
    private static func placeSide(_ ordered: ScratchSpan<End>, shape: FlowchartNodeShape, items: Items, keptClear: ScratchSpan<KeptPoint>,
                                  into points: Points, arena: DiagramScratchArena) {
        let side = ordered[0].side
        let node = ordered[0].node
        let span = items.spreadsEnds[node] ? FlowchartShapeGeometry.span(of: shape, size: items.sizes[node], side: side) : 0
        let step = ordered.count > 1 ? min(portSeparation, span / CGFloat(ordered.count - 1)) : 0
        func spread(_ position: Int) -> CGFloat { (CGFloat(position) - CGFloat(ordered.count - 1) / 2) * step }
        // Only a side with points to keep clear of makes its offsets as a list first.
        let kept = keptClear.isEmpty ? keptClear : keptPoints(of: sideKey(node: node, side: side), in: keptClear)
        var offsets = ScratchSpan<CGFloat>.empty
        if !kept.isEmpty {
            offsets = arena.uninitializedSpan(count: ordered.count)
            for position in 0..<ordered.count { offsets[position] = spread(position) }
            let keptOffsets: ScratchSpan<CGFloat> = arena.uninitializedSpan(count: kept.count)
            for index in 0..<kept.count { keptOffsets[index] = kept[index].offset }
            clear(offsets, of: keptOffsets, reach: span / 2)
        }
        for position in 0..<ordered.count {
            let end = ordered[position]
            let offset = offsets.isEmpty ? spread(position) : offsets[position]
            let point = outlinePoint(center: items.centers[node], shape: shape, size: items.sizes[node], side: side, offset: offset)
            if end.isSourceEnd {
                points.source[end.edgeIndex] = point
                points.isSourcePlaced[end.edgeIndex] = true
            } else {
                points.target[end.edgeIndex] = point
                points.isTargetPlaced[end.edgeIndex] = true
            }
        }
    }

    /// The kept points of the side `key`, found by halving the sorted list.
    private static func keptPoints(of key: Int, in keptClear: ScratchSpan<KeptPoint>) -> ScratchSpan<KeptPoint> {
        var low = 0
        var high = keptClear.count
        while low < high {
            let middle = (low + high) / 2
            if keptClear[middle].sideKey < key { low = middle + 1 } else { high = middle }
        }
        var end = low
        while end < keptClear.count && keptClear[end].sideKey == key { end += 1 }
        return keptClear.part(low..<end)
    }

    /// The point of a shape's outline on `side`, `offset` from the side's middle (rightward or downward).
    static func outlinePoint(center: CGPoint, shape: FlowchartNodeShape, size: CGSize, side: DiagramSide, offset: CGFloat) -> CGPoint {
        let inset = FlowchartShapeGeometry.inset(of: shape, size: size, side: side, offset: offset)
        switch side {
        case .top: return CGPoint(x: center.x + offset, y: center.y - size.height / 2 + inset)
        case .bottom: return CGPoint(x: center.x + offset, y: center.y + size.height / 2 - inset)
        case .left: return CGPoint(x: center.x - size.width / 2 + inset, y: center.y + offset)
        case .right: return CGPoint(x: center.x + size.width / 2 - inset, y: center.y + offset)
        }
    }

    /// The ends spread along a side, moved together by the fewest whole points that keep each half a port gap from
    /// every kept point and within `reach` of the side's middle; unmoved when no such move exists.
    static func clear(_ offsets: [CGFloat], of kept: [CGFloat], reach: CGFloat) -> [CGFloat] {
        DiagramScratchArena.withCurrentThread { arena in
            let offsetSpan: ScratchSpan<CGFloat> = arena.uninitializedSpan(count: offsets.count)
            for (index, offset) in offsets.enumerated() { offsetSpan[index] = offset }
            let keptSpan: ScratchSpan<CGFloat> = arena.uninitializedSpan(count: kept.count)
            for (index, offset) in kept.enumerated() { keptSpan[index] = offset }
            clear(offsetSpan, of: keptSpan, reach: reach)
            return Array(offsetSpan)
        }
    }

    /// `clear` in place.
    static func clear(_ offsets: ScratchSpan<CGFloat>, of kept: ScratchSpan<CGFloat>, reach: CGFloat) {
        guard !kept.isEmpty else { return }
        let clearance = portSeparation / 2
        func fits(_ shift: CGFloat) -> Bool {
            offsets.allSatisfy { offset in
                abs(offset + shift) <= max(reach, abs(offset)) && kept.allSatisfy { keptOffset in abs(offset + shift - keptOffset) >= clearance }
            }
        }
        for distance in 0...Int(2 * max(reach, 0)) {
            // The move forward first, then back.
            for isBack in [false, true] {
                let shift = isBack ? -CGFloat(distance) : CGFloat(distance)
                guard fits(shift) else { continue }
                for index in 0..<offsets.count { offsets[index] = offsets[index] + shift }
                return
            }
        }
    }

    /// A side of a node (or of a box numbered after the nodes) as one number.
    static func sideKey(node: Int, side: DiagramSide) -> Int {
        node * DiagramSide.allCases.count + sideNumber(side)
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
