/**
 * File: MindmapOutlinePlacement.swift
 * -----------------------------------
 * Layer: Core
 * Description: A mindmap laid out as an outline running down, as Pele lays it out for a column too narrow for a map
 *              spread to both sides.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// Where each node of a mindmap goes when the map runs down (Pele's `draw(down)`): the root heads a column and every node
/// follows it in the order the nodes are written, one row each, each level set in 28 points further than its parent,
/// with 10 points between rows and 10 more before each first-level branch. A link leaves its parent from under the
/// parent's left end, runs down a trunk that the parent's children share, and turns in to its child's left side.
struct MindmapOutlinePlacement {
    /// The center of each node across, and its top.
    private(set) var centersAcross: [CGFloat]
    private(set) var tops: [CGFloat]
    /// How deep each node is: 0 for the root.
    let depths: [Int]

    /// How far each level is set in from its parent's.
    static let indent: CGFloat = 28
    /// How far under its parent's left end a link leaves it (the root's is as far as the root's rounded end has come down,
    /// at most the indent less the bend), and the radius of the turn into a child.
    static let stem: CGFloat = 12
    static let bend: CGFloat = 8
    /// Between two rows, and between the root's rows and each first-level branch.
    static let rowGap: CGFloat = 10

    init(diagram: MindmapDiagram, sizes: [CGSize]) {
        let count = diagram.nodes.count
        var depths = Array(repeating: 0, count: count)
        for (index, node) in diagram.nodes.enumerated() {
            if let parent = node.parentIndex { depths[index] = depths[parent] + 1 }
        }
        self.depths = depths
        centersAcross = Array(repeating: 0, count: count)
        tops = Array(repeating: 0, count: count)
        var row: CGFloat = 0
        for (index, node) in diagram.nodes.enumerated() {
            if index > 0, node.parentIndex == 0 { row += Self.rowGap }
            centersAcross[index] = CGFloat(depths[index]) * Self.indent + sizes[index].width / 2
            tops[index] = row
            row += sizes[index].height + Self.rowGap
        }
    }

    /// The width a node's text may take in an outline `room` points wide: what is left of the room after its level's
    /// indent and the padding of a node drawn as text, but not under 72 points, and not over `wrappingWidth`.
    static func textWidth(depth: Int, room: CGFloat, wrappingWidth: CGFloat, padding: CGFloat) -> CGFloat {
        min(wrappingWidth, max(smallestTextWidth, room - CGFloat(depth) * indent - 2 * padding))
    }

    static let smallestTextWidth: CGFloat = 72

    /// The links of the outline in the order of the nodes they lead to, each as the path from under its parent's left end
    /// down the trunk and in to the node's left side. A trunk starts under the parent and carries on from where the link
    /// before it turned in, so that each stretch of it has one color.
    static func links(diagram: MindmapDiagram, nodes: [MindmapLayoutNode]) -> [(branchIndex: Int, path: DiagramPath)] {
        var trunks: [Int: CGFloat] = [:]
        var links: [(branchIndex: Int, path: DiagramPath)] = []
        for (index, node) in diagram.nodes.enumerated().dropFirst() {
            guard let parentIndex = node.parentIndex, let branchIndex = node.branchIndex else { continue }
            let parent = nodes[parentIndex].frame
            let child = nodes[index]
            let stem = parentIndex == 0 ? min(max(Self.stem, parent.height / 2), indent - bend) : Self.stem
            let startX = parent.minX + min(stem, parent.width / 2)
            let startY = trunks[parentIndex] ?? parent.maxY
            let endX = child.frame.minX + child.outline.sideInset(size: child.frame.size)
            let endY = child.frame.midY
            let bend = max(0, min(Self.bend, endX - startX, endY - startY))
            trunks[parentIndex] = endY - bend
            // The turn is Pele's quadratic curve, written as the cubic with the same shape.
            let turnStart = CGPoint(x: startX, y: endY - bend)
            let turnEnd = CGPoint(x: startX + bend, y: endY)
            let control = CGPoint(x: startX, y: endY)
            let path = DiagramPath(start: CGPoint(x: startX, y: startY), segments: [
                .line(to: turnStart),
                .curve(to: turnEnd, control1: CGPoint(x: turnStart.x + 2 / 3 * (control.x - turnStart.x), y: turnStart.y + 2 / 3 * (control.y - turnStart.y)),
                       control2: CGPoint(x: turnEnd.x + 2 / 3 * (control.x - turnEnd.x), y: turnEnd.y + 2 / 3 * (control.y - turnEnd.y))),
                .line(to: CGPoint(x: endX, y: endY)),
            ])
            links.append((branchIndex, path))
        }
        return links
    }
}
