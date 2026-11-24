/**
 * File: ReferenceFlowchartEdgePorts.swift
 * ---------------------------------------
 * Layer: Tests
 * Description: The 0.7.0 FlowchartEdgePorts kept as the reference the 0.8.0 flowchart layout is checked against: where
 *              a flowchart's edges meet their nodes: the ends on one side spread along it, then moved onto the shape's
 *              outline.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// Where edges meet their nodes. The edges that meet one side of a node spread along it, in the order of where they
/// come from, a port gap apart or closer when the side is short, so that they do not all meet in one point; each end
/// is then moved from the bounding box onto the shape's outline.
struct ReferenceFlowchartEdgePorts {
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

    /// The page points of each edge's ends, by edge index; nil for an edge with no end placed.
    private(set) var sourcePoints: [CGPoint?]
    private(set) var targetPoints: [CGPoint?]

    /// - Parameter keptClear: By `sideKey`, points of a side, as offsets from its middle, that the ends there keep half
    ///   a port gap from: where other edges cross a box's border on that side.
    /// - Parameter spreadsEnds: Whether the ends on a side spread along it; when not, they all meet its middle.
    /// - Parameter endsAtMiddle: Nodes whose ends all meet a side's middle whatever `spreadsEnds` says: icons and pictures.
    init(ends: [End], edgeCount: Int, nodeCenters: [CGPoint], shapes: [FlowchartNodeShape], shapeSizes: [CGSize], keptClear: [Int: [CGFloat]] = [:],
         spreadsEnds: Bool = true, endsAtMiddle: Set<Int> = []) {
        sourcePoints = Array(repeating: nil, count: edgeCount)
        targetPoints = Array(repeating: nil, count: edgeCount)
        // The ends grouped by side, side after side, each side's in the order they come: one list instead of a list per
        // side. Each side's ends are then sorted in place as its own list would have been.
        let sideCount = nodeCenters.count * DiagramSide.allCases.count
        var sideStart = [Int](repeating: 0, count: sideCount + 1)
        for end in ends { sideStart[Self.sideKey(node: end.node, side: end.side) + 1] += 1 }
        for side in 0..<sideCount { sideStart[side + 1] += sideStart[side] }
        var grouped = ends
        var fill = Array(sideStart[0..<sideCount])
        for end in ends {
            let key = Self.sideKey(node: end.node, side: end.side)
            grouped[fill[key]] = end
            fill[key] += 1
        }
        for key in 0..<sideCount where sideStart[key + 1] > sideStart[key] {
            grouped[sideStart[key]..<sideStart[key + 1]].sort { first, second in
                (first.neighborAcross, first.edgeIndex) < (second.neighborAcross, second.edgeIndex)
            }
            placeSide(grouped[sideStart[key]..<sideStart[key + 1]], nodeCenters: nodeCenters, shapes: shapes, shapeSizes: shapeSizes,
                      keptClear: keptClear, spreadsEnds: spreadsEnds, endsAtMiddle: endsAtMiddle)
        }
    }

    /// The ends of one side, in their order along it, spread around its middle and moved onto the shape's outline.
    private mutating func placeSide(_ ordered: ArraySlice<End>, nodeCenters: [CGPoint], shapes: [FlowchartNodeShape], shapeSizes: [CGSize],
                                    keptClear: [Int: [CGFloat]], spreadsEnds: Bool, endsAtMiddle: Set<Int>) {
        guard let side = ordered.first?.side, let node = ordered.first?.node else { return }
        let span = spreadsEnds && !endsAtMiddle.contains(node) ? FlowchartShapeGeometry.span(of: shapes[node], size: shapeSizes[node], side: side) : 0
        let step = ordered.count > 1 ? min(Self.portSeparation, span / CGFloat(ordered.count - 1)) : 0
        func spread(_ position: Int) -> CGFloat { (CGFloat(position) - CGFloat(ordered.count - 1) / 2) * step }
        // Only a side with points to keep clear of makes its offsets as an array first.
        let kept = keptClear.isEmpty ? [] : keptClear[Self.sideKey(node: node, side: side)] ?? []
        let clearOffsets = kept.isEmpty ? nil : Self.clear((0..<ordered.count).map(spread), of: kept, reach: span / 2)
        for (position, end) in ordered.enumerated() {
            let offset = clearOffsets?[position] ?? spread(position)
            let point = Self.outlinePoint(center: nodeCenters[node], shape: shapes[node], size: shapeSizes[node], side: side, offset: offset)
            if end.isSourceEnd { sourcePoints[end.edgeIndex] = point } else { targetPoints[end.edgeIndex] = point }
        }
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
        guard !kept.isEmpty else { return offsets }
        let clearance = portSeparation / 2
        func fits(_ shift: CGFloat) -> Bool {
            offsets.allSatisfy { offset in
                abs(offset + shift) <= max(reach, abs(offset)) && kept.allSatisfy { keptOffset in abs(offset + shift - keptOffset) >= clearance }
            }
        }
        for distance in 0...Int(2 * max(reach, 0)) {
            for shift in [CGFloat(distance), -CGFloat(distance)] where fits(shift) { return offsets.map { offset in offset + shift } }
        }
        return offsets
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
