/**
 * File: FlowchartMeasurement.swift
 * --------------------------------
 * Layer: Core
 * Description: A flowchart's text measured and its shapes sized, before the layout places anything.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.4
 * Date: 23/11/2026
 */

import CoreGraphics

/// A flowchart's text measured and its shapes sized: what the layout needs before it places anything.
struct FlowchartMeasurement {
    let nodeTexts: [DiagramTextBlock]
    let shapeSizes: [CGSize]
    /// How far below each shape's center its text's center is.
    let textOffsets: [CGFloat]
    /// Each edge's text, or nil.
    let edgeTexts: [DiagramTextBlock?]
    /// For each node, the indexes of its edges to itself, in their written order.
    let selfLoopEdgeIndices: [[Int]]
    /// Whether the edges meeting one side of a node spread along it, as a flowchart's do; an agent flow's meet in the
    /// side's middle, as Pele gives its nodes no span.
    var spreadsEdgeEnds = true
    /// The nodes drawn as an icon or a picture: laid out as a box whose edges all meet a side's middle and end on the box,
    /// as Pele gives such a node no span and no outline of its own (flowchart/render.ts).
    var assetNodes: Set<Int> = []

    init<Measurer: DiagramTextMeasuring>(diagram: FlowchartDiagram, nodeText: Measurer, edgeText: Measurer, wrappingWidth: CGFloat) {
        var nodeTexts: [DiagramTextBlock] = []
        var shapeSizes: [CGSize] = []
        var textOffsets: [CGFloat] = []
        nodeTexts.reserveCapacity(diagram.nodes.count)
        for (index, node) in diagram.nodes.enumerated() {
            let asset = node.asset
            if asset != nil { assetNodes.insert(index) }
            // A shape drawn without text (a start, a fork, a junction) measures none, as Pele lays out no label for it.
            let label = node.shape.holdsText || asset != nil ? node.label : DiagramLabel(lines: [])
            let text = DiagramTextBlock(label: label, measurer: nodeText, maximumWidth: wrappingWidth)
            let (size, textOffset) = asset?.size(textSize: text.size) ?? FlowchartShapeGeometry.size(of: node.shape, textSize: text.size)
            nodeTexts.append(text)
            shapeSizes.append(size)
            textOffsets.append(textOffset)
        }
        self.nodeTexts = nodeTexts
        self.shapeSizes = shapeSizes
        self.textOffsets = textOffsets
        edgeTexts = diagram.edges.map { edge in
            edge.label.map { label in DiagramTextBlock(label: label, measurer: edgeText, maximumWidth: wrappingWidth) }
                .flatMap { text in text.lines.isEmpty ? nil : text }
        }
        var selfLoopEdgeIndices = [[Int]](repeating: [], count: diagram.nodes.count)
        for (edgeIndex, edge) in diagram.edges.enumerated() where edge.sourceIndex == edge.targetIndex {
            selfLoopEdgeIndices[edge.sourceIndex].append(edgeIndex)
        }
        self.selfLoopEdgeIndices = selfLoopEdgeIndices
    }

    /// How much of the side of `node` facing `side` its edges share out between them (Pele's `shapeSpan`), or 0 where
    /// they all meet its middle.
    func sideSpan(of node: Int, shape: FlowchartNodeShape, side: DiagramSide) -> CGFloat {
        spreadsEdgeEnds && !assetNodes.contains(node) ? FlowchartShapeGeometry.span(of: shape, size: shapeSizes[node], side: side) : 0
    }

    /// Each node's shape as the layout meets it: its own, or a rectangle for a node drawn as an icon or a picture.
    func layoutShapes(of diagram: FlowchartDiagram) -> [FlowchartNodeShape] {
        diagram.nodes.indices.map { node in assetNodes.contains(node) ? .rectangle : diagram.nodes[node].shape }
    }

    /// Each node's size in its rank: its shape, widened on both sides across the flow by the room its loops take.
    func layoutSizes(loopSide: DiagramSide) -> [CGSize] {
        shapeSizes.indices.map { node in layoutSize(of: node, loopSide: loopSide) }
    }

    /// One node's size in its rank, its loops going out of `loopSide`.
    func layoutSize(of node: Int, loopSide: DiagramSide) -> CGSize {
        let size = shapeSizes[node]
        let loopEdgeIndices = selfLoopEdgeIndices[node]
        guard !loopEdgeIndices.isEmpty else { return size }
        let room = FlowchartSelfLoops.room(textSizes: loopEdgeIndices.map { edgeIndex in edgeTexts[edgeIndex]?.size }, loopSide: loopSide)
        return loopSide == .right ? CGSize(width: size.width + 2 * room, height: size.height)
                                  : CGSize(width: size.width, height: size.height + 2 * room)
    }
}
