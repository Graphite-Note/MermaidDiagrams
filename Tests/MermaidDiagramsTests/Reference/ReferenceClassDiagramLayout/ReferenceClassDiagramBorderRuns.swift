/**
 * File: ReferenceClassDiagramBorderRuns.swift
 * -------------------------------------------
 * Layer: Tests
 * Description: The 0.7.0 ClassDiagramBorderRuns kept as the reference the 0.8.0 layout is checked against:
 *              relations that leave a class close to its namespace's border run straight to it, as Pele's class renderer draws them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// Pele's class renderer (`class/render.ts`, where it spreads the ends along a side): when the ends of several relations
/// share a side of a class, each is moved along the side, and a relation whose route then crosses the border of a
/// namespace around the class close by, its route running in line from the end to that border, has the points of that
/// run moved into line with its moved end, so that it runs straight from the class to the border.
struct ReferenceClassDiagramBorderRuns {
    /// How far from its moved end a route's crossing may be and still be moved into line with it: Pele's 24 points.
    static let reach: CGFloat = 24
    /// How close two coordinates are to be in line, or a point to be on a border: Pele's half point.
    static let tolerance: CGFloat = 0.5

    let graph: LayeredClusterGraph
    let clusterFrames: [CGRect]
    /// How many relation ends share each side of each node, keyed by `key(node:side:)`.
    let endCounts: [Int: Int]

    init(graph: LayeredClusterGraph, clusterFrames: [CGRect], ends: [ReferenceClassDiagramEdgePorts.End]) {
        self.graph = graph
        self.clusterFrames = clusterFrames
        var endCounts: [Int: Int] = [:]
        for end in ends { endCounts[Self.key(node: end.node, side: end.side), default: 0] += 1 }
        self.endCounts = endCounts
    }

    /// `points` from the source's port to the target's, the route's points between them moved into line with the ports
    /// where Pele moves them.
    func straightened(_ points: [CGPoint], source: ReferenceClassDiagramEdgePorts.End, target: ReferenceClassDiagramEdgePorts.End) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var moved = points
        moveRun(of: &moved, end: source, interior: Array(1..<(points.count - 1)))
        moveRun(of: &moved, end: target, interior: Array((1..<(points.count - 1)).reversed()))
        return moved
    }

    /// Moves the run of `interior` points (from the end outward) in line with the first of them into line with the end,
    /// when the run reaches a border of a namespace around the end's class within `reach` of the end.
    private func moveRun(of points: inout [CGPoint], end: ReferenceClassDiagramEdgePorts.End, interior: [Int]) {
        guard (endCounts[Self.key(node: end.node, side: end.side)] ?? 0) >= 2, let first = interior.first else { return }
        let endPoint = end.isSourceEnd ? points[0] : points[points.count - 1]
        let alongSide: (CGPoint) -> CGFloat = end.side.isHorizontal ? { point in point.x } : { point in point.y }
        let line = alongSide(points[first])
        guard abs(line - alongSide(endPoint)) <= Self.reach else { return }
        var run: [Int] = []
        for index in interior {
            guard abs(alongSide(points[index]) - line) < Self.tolerance else { return }
            run.append(index)
            if isOnBorder(points[index], aroundNode: end.node) {
                for moved in run {
                    if end.side.isHorizontal { points[moved].x = endPoint.x } else { points[moved].y = endPoint.y }
                }
                return
            }
        }
    }

    /// Whether `point` lies on the border of one of the namespaces' boxes around `node`.
    private func isOnBorder(_ point: CGPoint, aroundNode node: Int) -> Bool {
        var current = node < graph.nodeClusters.count ? graph.nodeClusters[node] : nil
        var steps = 0
        while let cluster = current, cluster < clusterFrames.count, steps <= graph.clusters.count {
            let frame = clusterFrames[cluster]
            let across = abs(point.x - frame.midX)
            let down = abs(point.y - frame.midY)
            let onTopOrBottom = abs(down - frame.height / 2) < Self.tolerance && across <= frame.width / 2 + Self.tolerance
            let onLeftOrRight = abs(across - frame.width / 2) < Self.tolerance && down <= frame.height / 2 + Self.tolerance
            if onTopOrBottom || onLeftOrRight { return true }
            current = graph.clusters[cluster].parent
            steps += 1
        }
        return false
    }

    private static func key(node: Int, side: DiagramSide) -> Int {
        let sideNumber = switch side {
        case .top: 0
        case .right: 1
        case .bottom: 2
        case .left: 3
        }
        return node * 4 + sideNumber
    }
}
