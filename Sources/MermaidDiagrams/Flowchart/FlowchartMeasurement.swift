/**
 * File: FlowchartMeasurement.swift
 * --------------------------------
 * Layer: Core
 * Description: A flowchart's text measured, its markup decoded from the bytes it was written in, and its shapes sized,
 *              before the layout places anything.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.8
 * Date: 25/11/2026
 */

import CoreGraphics

/// A flowchart's text measured and its shapes sized: what the layout needs before it places anything. Lists that most
/// flowcharts leave empty (loops, icons and pictures) are made only for those that have them.
struct FlowchartMeasurement {
    let nodeTexts: [DiagramTextBlock]
    let shapeSizes: [CGSize]
    /// How far below each shape's center its text's center is.
    let textOffsets: [CGFloat]
    /// Each edge's text, or nil.
    let edgeTexts: [DiagramTextBlock?]
    /// For each node, the indexes of its edges to itself, in their written order.
    let selfLoopEdgeIndices: FlowchartSelfLoopIndex
    /// Whether the edges meeting one side of a node spread along it, as a flowchart's do; an agent flow's meet in the
    /// side's middle, as Pele gives its nodes no span.
    var spreadsEdgeEnds = true
    /// By node, whether it is drawn as an icon or a picture: laid out as a box whose edges all meet a side's middle and
    /// end on the box, as Pele gives such a node no span and no outline of its own (flowchart/render.ts). Empty when no
    /// node is.
    private(set) var assetNodeFlags: [Bool] = []

    /// A text written with markup is decoded from the bytes it was written in (`FlowchartTextMeasuring`).
    init<Measurer: DiagramTextMeasuring>(diagram: FlowchartDiagram, nodeText: Measurer, edgeText: Measurer, wrappingWidth: CGFloat) {
        var shapeSizes: [CGSize] = []
        var textOffsets: [CGFloat] = []
        let nodeCount = diagram.nodeCount
        shapeSizes.reserveCapacity(nodeCount)
        textOffsets.reserveCapacity(nodeCount)
        let (nodeTexts, edgeTexts) = diagram.model.text.withBytes { source in
            Self.texts(of: diagram, source: source, nodeText: nodeText, edgeText: edgeText, wrappingWidth: wrappingWidth)
        }
        for index in 0..<nodeCount {
            let asset = diagram.nodeAsset(at: index)
            if asset != nil {
                if assetNodeFlags.isEmpty { assetNodeFlags = [Bool](repeating: false, count: nodeCount) }
                assetNodeFlags[index] = true
            }
            let textSize = nodeTexts[index].size
            let (size, textOffset) = asset?.size(textSize: textSize) ?? FlowchartShapeGeometry.size(of: diagram.nodeShape(at: index), textSize: textSize)
            shapeSizes.append(size)
            textOffsets.append(textOffset)
        }
        self.nodeTexts = nodeTexts
        self.shapeSizes = shapeSizes
        self.textOffsets = textOffsets
        self.edgeTexts = edgeTexts
        selfLoopEdgeIndices = FlowchartSelfLoopIndex(diagram: diagram)
    }

    /// The nodes' texts and the edges' texts of `diagram`, whose text's bytes are `source`. A shape drawn without text (a
    /// start, a fork, a junction) and not as an icon or a picture measures none, as Pele lays out no label for it; an
    /// edge's text of no line is none.
    private static func texts<Measurer: DiagramTextMeasuring>(of diagram: FlowchartDiagram, source: UnsafeBufferPointer<UInt8>, nodeText: Measurer,
                                                              edgeText: Measurer, wrappingWidth: CGFloat) -> ([DiagramTextBlock], [DiagramTextBlock?]) {
        let model = diagram.model
        let nodeMeasuring = FlowchartTextMeasuring(model: model, measurer: nodeText, maximumWidth: wrappingWidth)
        var nodeTexts: [DiagramTextBlock] = []
        nodeTexts.reserveCapacity(model.nodes.count)
        for (index, node) in model.nodes.enumerated() {
            let measuresText = node.shape.holdsText || diagram.nodeAsset(at: index) != nil
            nodeTexts.append(nodeMeasuring.block(of: measuresText ? node.label : .none, source: source))
        }
        let edgeMeasuring = FlowchartTextMeasuring(model: model, measurer: edgeText, maximumWidth: wrappingWidth)
        var edgeTexts: [DiagramTextBlock?] = []
        edgeTexts.reserveCapacity(model.edges.count)
        for edge in model.edges {
            guard edge.label.kind != .none else {
                edgeTexts.append(nil)
                continue
            }
            let text = edgeMeasuring.block(of: edge.label, source: source)
            edgeTexts.append(text.lineCount == 0 ? nil : text)
        }
        return (nodeTexts, edgeTexts)
    }

    /// A flowchart measured by a diagram drawn as one, which sizes its nodes its own way.
    init(nodeTexts: [DiagramTextBlock], shapeSizes: [CGSize], textOffsets: [CGFloat], edgeTexts: [DiagramTextBlock?],
         selfLoopEdgeIndices: FlowchartSelfLoopIndex) {
        self.nodeTexts = nodeTexts
        self.shapeSizes = shapeSizes
        self.textOffsets = textOffsets
        self.edgeTexts = edgeTexts
        self.selfLoopEdgeIndices = selfLoopEdgeIndices
    }

    /// Whether `node` is drawn as an icon or a picture.
    @inline(__always)
    func isAssetNode(_ node: Int) -> Bool { !assetNodeFlags.isEmpty && assetNodeFlags[node] }

    /// Whether the edges meeting `node` spread along its sides.
    @inline(__always)
    func spreadsEdgeEnds(of node: Int) -> Bool { spreadsEdgeEnds && !isAssetNode(node) }

    /// How much of the side of `node` facing `side` its edges share out between them (Pele's `shapeSpan`), or 0 where
    /// they all meet its middle.
    func sideSpan(of node: Int, shape: FlowchartNodeShape, side: DiagramSide) -> CGFloat {
        spreadsEdgeEnds(of: node) ? FlowchartShapeGeometry.span(of: shape, size: shapeSizes[node], side: side) : 0
    }

    /// The shape of `node` as the layout meets it: its own, or a rectangle for a node drawn as an icon or a picture.
    @inline(__always)
    func layoutShape(of node: Int, in diagram: FlowchartDiagram) -> FlowchartNodeShape {
        isAssetNode(node) ? .rectangle : diagram.nodeShape(at: node)
    }

    /// One node's size in its rank: its shape, widened on both sides across the flow by the room its loops take, its loops
    /// going out of `loopSide`.
    func layoutSize(of node: Int, loopSide: DiagramSide) -> CGSize {
        let size = shapeSizes[node]
        let loopEdgeIndices = selfLoopEdgeIndices[node]
        guard !loopEdgeIndices.isEmpty else { return size }
        let flowRunsAcross = loopSide == .bottom
        var room: CGFloat = 0
        for edgeIndex in loopEdgeIndices { room = room + FlowchartSelfLoops.room(textSize: edgeTexts[edgeIndex]?.size, flowRunsAcross: flowRunsAcross) }
        return loopSide == .right ? CGSize(width: size.width + 2 * room, height: size.height)
                                  : CGSize(width: size.width, height: size.height + 2 * room)
    }
}

/// For each node of a flowchart, the edges from it to itself in their written order: one list, node after node, and
/// where each node's start, made only for a flowchart that has such an edge.
struct FlowchartSelfLoopIndex {
    private let edgeIndices: [Int]
    /// `nodeCount + 1` starts into `edgeIndices`; empty when no edge loops.
    private let starts: [Int]

    static let none = FlowchartSelfLoopIndex(edgeIndices: [], starts: [])

    private init(edgeIndices: [Int], starts: [Int]) {
        self.edgeIndices = edgeIndices
        self.starts = starts
    }

    /// The loops of a flowchart's edges.
    init(diagram: FlowchartDiagram) {
        self.init(nodeCount: diagram.nodeCount, edges: diagram.model.edges)
    }

    /// The loops of the edges of a flowchart's model of `nodeCount` nodes.
    init(nodeCount: Int, edges: [FlowchartEdgeRecord]) {
        var loopCount = 0
        for edge in edges where edge.sourceIndex == edge.targetIndex { loopCount += 1 }
        guard loopCount > 0 else {
            self = .none
            return
        }
        var starts = [Int](repeating: 0, count: nodeCount + 1)
        for edge in edges where edge.sourceIndex == edge.targetIndex { starts[Int(edge.sourceIndex) + 1] += 1 }
        for node in 0..<nodeCount { starts[node + 1] += starts[node] }
        var filled = starts
        var edgeIndices = [Int](repeating: 0, count: loopCount)
        for (edgeIndex, edge) in edges.enumerated() where edge.sourceIndex == edge.targetIndex {
            let node = Int(edge.sourceIndex)
            edgeIndices[filled[node]] = edgeIndex
            filled[node] += 1
        }
        self.init(edgeIndices: edgeIndices, starts: starts)
    }

    /// Whether no edge loops.
    var isEmpty: Bool { starts.isEmpty }

    /// The loops of `node`, in their written order.
    subscript(node: Int) -> ArraySlice<Int> {
        starts.isEmpty ? edgeIndices[0..<0] : edgeIndices[starts[node]..<starts[node + 1]]
    }
}
