/**
 * File: ClassDiagramComponentRows.swift
 * -------------------------------------
 * Layer: Core
 * Description: The parts of a class diagram that no relation joins, set in rows that fit a narrow container, as Pele's
 *              wrapComponents sets them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import CoreGraphics

/// Pele's `wrapComponents` (layout/components.ts), which its class renderer runs when the diagram is wider than its
/// container: the diagram's parts that nothing joins (a namespace joins what it holds and the namespace around it, a
/// relation or a note's line its two ends) are set left to right in the order of their first item (the namespaces, then
/// the nodes), a new row started where the next would pass `rowWidth`, `gap` apart across and down; nothing moves when
/// there is one part, or when the rows are not narrower than the diagram was.
enum ClassDiagramComponentRows {
    /// How far each namespace, each node and each edge moves, and the size of the rows, from their top left corner.
    struct Placement {
        let namespaceOffsets: [CGVector]
        let nodeOffsets: [CGVector]
        let edgeOffsets: [CGVector]
        let size: CGSize
    }

    /// An edge between `source` and `target` (node indices) as it is placed.
    struct Edge {
        let source: Int
        let target: Int
        let placed: ClassDiagramLayoutEdge
    }

    static func placement(namespaceFrames: [CGRect], namespaceParents: [Int?], nodeFrames: [CGRect], nodeNamespaces: [Int?], edges: [Edge?],
                          rowWidth: CGFloat, gap: CGFloat) -> Placement? {
        let namespaceCount = namespaceFrames.count
        var roots = LayeredUnionFind(count: namespaceCount + nodeFrames.count)
        for (namespace, parent) in namespaceParents.enumerated() { if let parent { roots.join(namespace, into: parent) } }
        for (node, namespace) in nodeNamespaces.enumerated() { if let namespace { roots.join(namespaceCount + node, into: namespace) } }
        for edge in edges.compactMap({ edge in edge }) { roots.join(namespaceCount + edge.source, into: namespaceCount + edge.target) }
        var partIndexByRoot: [Int: Int] = [:]
        var parts: [CGRect] = []
        var itemParts: [Int] = []
        for (item, frame) in (namespaceFrames + nodeFrames).enumerated() {
            let root = roots.find(item)
            let partIndex = partIndexByRoot[root] ?? parts.count
            if partIndexByRoot[root] == nil {
                partIndexByRoot[root] = partIndex
                parts.append(.null)
            }
            parts[partIndex] = parts[partIndex].union(frame)
            itemParts.append(partIndex)
        }
        guard parts.count >= 2 else { return nil }
        let edgeParts = edges.map { edge in edge.map { edge in itemParts[namespaceCount + edge.source] } }
        for (edge, partIndex) in zip(edges, edgeParts) {
            guard let edge, let partIndex else { continue }
            parts[partIndex] = parts[partIndex].union(covered(by: edge.placed))
        }
        guard let rows = rows(of: parts, width: rowWidth, gap: gap) else { return nil }
        return Placement(namespaceOffsets: itemParts.prefix(namespaceCount).map { part in rows.shifts[part] },
                         nodeOffsets: itemParts.dropFirst(namespaceCount).map { part in rows.shifts[part] },
                         edgeOffsets: edgeParts.map { part in part.map { part in rows.shifts[part] } ?? .zero }, size: rows.size)
    }

    /// Each part moved to its place in the rows, and the rows' size; nil when they are no narrower than the parts were.
    private static func rows(of bounds: [CGRect], width: CGFloat, gap: CGFloat) -> (shifts: [CGVector], size: CGSize)? {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var right: CGFloat = 0
        var from = CGFloat.infinity
        var to = -CGFloat.infinity
        var shifts: [CGVector] = []
        for part in bounds {
            if x > 0, x + part.width > width {
                y += rowHeight + gap
                x = 0
                rowHeight = 0
            }
            shifts.append(CGVector(dx: x - part.minX, dy: y - part.minY))
            from = min(from, part.minX)
            to = max(to, part.maxX)
            right = max(right, x + part.width)
            rowHeight = max(rowHeight, part.height)
            x += part.width + gap
        }
        guard right < to - from else { return nil }
        return (shifts, CGSize(width: right, height: y + rowHeight))
    }

    /// What an edge covers as Pele counts it: the points of its line, its text's patch and its cardinalities.
    private static func covered(by edge: ClassDiagramLayoutEdge) -> CGRect {
        var bounds = CGRect(origin: edge.path.start, size: .zero)
        for segment in edge.path.segments {
            switch segment {
            case .line(let end): bounds = bounds.union(CGRect(origin: end, size: .zero))
            case .curve(let end, let firstControl, let secondControl):
                for point in [end, firstControl, secondControl] { bounds = bounds.union(CGRect(origin: point, size: .zero)) }
            }
        }
        if let text = edge.text {
            let room = ClassDiagramLayoutEngine.edgeTextRoom
            bounds = bounds.union(text.frame.insetBy(dx: -room.width / 2, dy: -room.height / 2))
        }
        for cardinality in [edge.sourceCardinality, edge.targetCardinality].compactMap({ cardinality in cardinality }) {
            bounds = bounds.union(cardinality.frame)
        }
        return bounds
    }
}
