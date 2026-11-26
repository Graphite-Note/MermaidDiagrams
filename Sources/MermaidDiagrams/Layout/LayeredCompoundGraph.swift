/**
 * File: LayeredCompoundGraph.swift
 * --------------------------------
 * Layer: Core
 * Description: A graph whose nodes sit in nested boxes written straight into the compound layout's spans, the nodes
 *              and boxes a diagram's layout makes there, and what it reads back from the layout.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.6
 * Date: 25/11/2026
 */

import CoreGraphics

/// A graph whose nodes may sit in nested boxes, as Pele lays out a flowchart's subgraphs: its nodes first, then a group
/// node for each box after them, and its edges between two different nodes or boxes, every one written by the diagram's
/// layout straight into spans of the calling thread's scratch arena that `LayeredCompoundLayout` lays out in place.
/// Boxes inside each other through their parents are lifted to the top level, as Pele does.
struct LayeredCompoundGraph {
    /// The nodes, then the boxes' group nodes in box order.
    let nodes: ScratchSpan<LayeredCompoundNode>
    let edges: ScratchSpan<LayeredCompoundSpanEdge>
    /// How many of `nodes` are not boxes.
    let nodeCount: Int
    /// The direction of the top level.
    let direction: LayeredDirection

    /// How many boxes follow the nodes.
    @inline(__always)
    var boxCount: Int { nodes.count - nodeCount }

    /// Laid out in place in `arena`, within `maximumPointCount` nodes and passing points in all its boxes together; nil
    /// past it.
    func laidOut(spacing: LayeredSpacing, maximumPointCount: Int, arena: DiagramScratchArena) -> LayeredCompoundLayout? {
        var layout = LayeredCompoundLayout(nodes: nodes, edges: edges, rootDirection: direction, options: LayeredFlatOptions(spacing),
                                           maximumVertexCount: maximumPointCount, arena: arena)
        return LayeredCompoundLayout.layout(&layout) == nil ? nil : layout
    }
}

extension LayeredCompoundNode {
    /// A node of `size` on the page directly in box `box` (nil for the top level) of a graph of `nodeCount` nodes, its
    /// place in the declaration order `sequence`, sharing out `sideSpan` of its sides between its edges.
    @inline(__always)
    static func member(size: CGSize, box: Int?, nodeCount: Int, sequence: Int, sideSpan: CGFloat = 0) -> LayeredCompoundNode {
        var node = LayeredCompoundNode(width: Double(size.width), height: Double(size.height), parent: box.map { box in nodeCount + box } ?? -1)
        node.sequence = Double(sequence)
        node.sideSpan = Double(sideSpan)
        return node
    }

    /// A box directly in box `parent` (nil for the top level) of a graph of `nodeCount` nodes, running in `direction` (nil
    /// for that of the box around it), `padding` inside it, at least `minimumWidth` wide, its place in the declaration
    /// order `sequence`, sharing out `sideSpan` of its sides beyond its padding between its edges.
    @inline(__always)
    static func box(parent: Int?, nodeCount: Int, direction: LayeredDirection?, padding: LayeredClusterPadding, minimumWidth: CGFloat,
                    sequence: CGFloat, sideSpan: CGFloat = 0) -> LayeredCompoundNode {
        var group = LayeredCompoundNode(width: 0, height: 0, parent: parent.map { parent in nodeCount + parent } ?? -1)
        group.isGroup = true
        group.direction = direction
        group.paddingSide = Double(padding.side)
        group.paddingTop = Double(padding.top)
        group.paddingBottom = Double(padding.bottom)
        group.minimumWidth = Double(minimumWidth)
        group.sequence = Double(sequence)
        group.sideSpan = Double(sideSpan)
        return group
    }

    /// The node's frame on the page once laid out.
    @inline(__always)
    var frame: CGRect { CGRect(x: x - width / 2, y: y - height / 2, width: width, height: height) }
}

extension LayeredCompoundSpanEdge {
    /// An edge from node `source` to node `target` of the compound graph, at least `minimumRankSpan` ranks long, its text's
    /// place `labelSize` on the page (nil for none).
    @inline(__always)
    init(source: Int, target: Int, minimumRankSpan: Int, labelSize: CGSize?) {
        self.init(source: source, target: target, minimumLength: minimumRankSpan, labelWidth: Double(labelSize?.width ?? 0),
                  labelHeight: Double(labelSize?.height ?? 0))
    }
}

extension LayeredCompoundLayout {
    /// Whether edge `edgeIndex` runs between a group and something inside it, which Pele draws from one center to the
    /// other.
    func isStray(_ edgeIndex: Int) -> Bool {
        let edge = edges[edgeIndex]
        guard edge.source != edge.target else { return false }
        func contains(_ group: Int, _ node: Int) -> Bool {
            var parent = nodes[node].parent
            var hops = 0
            while parent >= 0 && hops < nodes.count {
                if parent == group { return true }
                parent = nodes[parent].parent
                hops += 1
            }
            return false
        }
        return contains(edge.source, edge.target) || contains(edge.target, edge.source)
    }

    /// The center of laid-out edge `edgeIndex`'s text, or nil for an edge without text (but one between a box and what it
    /// holds, which has its middle).
    @inline(__always)
    func labelCenter(of edgeIndex: Int) -> CGPoint? {
        edges[edgeIndex].labelWidth > 0 || isStray(edgeIndex) ? edges[edgeIndex].labelCenter : nil
    }
}
