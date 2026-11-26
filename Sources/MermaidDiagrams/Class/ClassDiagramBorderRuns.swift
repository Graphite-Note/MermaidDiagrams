/**
 * File: ClassDiagramBorderRuns.swift
 * ----------------------------------
 * Layer: Core
 * Description: Relations that leave a class close to its namespace's border run straight to it, as Pele's class renderer draws them.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 26/11/2026
 */

import CoreGraphics

/// Pele's class renderer (`class/render.ts`, where it spreads the ends along a side): when the ends of several relations
/// share a side of a class, each is moved along the side, and a relation whose route then crosses the border of a
/// namespace around the class close by, its route running in line from the end to that border, has the points of that
/// run moved into line with its moved end, so that it runs straight from the class to the border.
struct ClassDiagramBorderRuns {
    /// How far from its moved end a route's crossing may be and still be moved into line with it: Pele's 24 points.
    static let reach: CGFloat = 24
    /// How close two coordinates are to be in line, or a point to be on a border: Pele's half point.
    static let tolerance: CGFloat = 0.5

    /// The namespace each node sits in, and the one each namespace is in, or nil.
    let nodeNamespaces: [Int?]
    let namespaceParents: [Int?]
    let clusterFrames: [CGRect]
    /// How many relation ends share each side of each node, at `slot(node:side:)`: four sides for each node from the
    /// first to the last an end is at.
    let endCounts: [Int32]

    init(nodeNamespaces: [Int?], namespaceParents: [Int?], clusterFrames: [CGRect], ends: [ClassDiagramEdgePorts.End]) {
        self.nodeNamespaces = nodeNamespaces
        self.namespaceParents = namespaceParents
        self.clusterFrames = clusterFrames
        var nodeCount = 0
        for end in ends { nodeCount = max(nodeCount, end.node + 1) }
        var endCounts = [Int32](repeating: 0, count: 4 * nodeCount)
        for end in ends { endCounts[Self.slot(node: end.node, side: end.side)] += 1 }
        self.endCounts = endCounts
    }

    /// `points` from the source's port to the target's, the route's points between them moved into line with the ports
    /// where Pele moves them.
    func straightened(_ points: [CGPoint], source: ClassDiagramEdgePorts.End, target: ClassDiagramEdgePorts.End) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var moved = points
        moveRun(of: &moved, end: source, first: 1, step: 1, count: points.count - 2)
        moveRun(of: &moved, end: target, first: points.count - 2, step: -1, count: points.count - 2)
        return moved
    }

    /// Moves the run of the `count` interior points from `first` by `step` (from the end outward) in line with the first
    /// of them into line with the end, when the run reaches a border of a namespace around the end's class within `reach`
    /// of the end.
    private func moveRun(of points: inout [CGPoint], end: ClassDiagramEdgePorts.End, first: Int, step: Int, count: Int) {
        let slot = Self.slot(node: end.node, side: end.side)
        guard slot < endCounts.count, endCounts[slot] >= 2, count > 0 else { return }
        let endPoint = end.isSourceEnd ? points[0] : points[points.count - 1]
        let isHorizontal = end.side.isHorizontal
        let line = Self.alongSide(points[first], isHorizontal: isHorizontal)
        guard abs(line - Self.alongSide(endPoint, isHorizontal: isHorizontal)) <= Self.reach else { return }
        var index = first
        for _ in 0..<count {
            guard abs(Self.alongSide(points[index], isHorizontal: isHorizontal) - line) < Self.tolerance else { return }
            if isOnBorder(points[index], aroundNode: end.node) {
                // The run is every point from the first to this one.
                var moved = first
                while true {
                    if isHorizontal { points[moved].x = endPoint.x } else { points[moved].y = endPoint.y }
                    if moved == index { break }
                    moved += step
                }
                return
            }
            index += step
        }
    }

    /// A point's coordinate along a side: x along the top or bottom, y along the left or right.
    private static func alongSide(_ point: CGPoint, isHorizontal: Bool) -> CGFloat {
        isHorizontal ? point.x : point.y
    }

    /// Whether `point` lies on the border of one of the namespaces' boxes around `node`.
    private func isOnBorder(_ point: CGPoint, aroundNode node: Int) -> Bool {
        var current = node < nodeNamespaces.count ? nodeNamespaces[node] : nil
        var steps = 0
        while let cluster = current, cluster < clusterFrames.count, steps <= namespaceParents.count {
            let frame = clusterFrames[cluster]
            let across = abs(point.x - frame.midX)
            let down = abs(point.y - frame.midY)
            let onTopOrBottom = abs(down - frame.height / 2) < Self.tolerance && across <= frame.width / 2 + Self.tolerance
            let onLeftOrRight = abs(across - frame.width / 2) < Self.tolerance && down <= frame.height / 2 + Self.tolerance
            if onTopOrBottom || onLeftOrRight { return true }
            current = namespaceParents[cluster]
            steps += 1
        }
        return false
    }

    private static func slot(node: Int, side: DiagramSide) -> Int {
        let sideNumber = switch side {
        case .top: 0
        case .right: 1
        case .bottom: 2
        case .left: 3
        }
        return node * 4 + sideNumber
    }
}
