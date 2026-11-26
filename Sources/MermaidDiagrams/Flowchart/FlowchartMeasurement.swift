/**
 * File: FlowchartMeasurement.swift
 * --------------------------------
 * Layer: Core
 * Description: A flowchart's text measured, its markup decoded from the bytes it was written in, and its shapes sized,
 *              before the layout places anything: a flat record a node and a placed text an edge.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.9
 * Date: 26/11/2026
 */

import CoreGraphics

/// A flowchart's text measured and its shapes sized: what the layout needs before it places anything. Each node's text,
/// shape's size and text's offset are one flat record, each edge's text another, the texts kept without a reference to
/// their storage (`DiagramPlacedText`), so that the measurement is two lists that free without reference counting. Lists
/// that most flowcharts leave empty (loops, icons and pictures) are made only for those that have them.
struct FlowchartMeasurement {
    private let nodeRecords: [FlowchartMeasuredNode]
    /// Each edge's text, or nil.
    private let edgeRecords: [DiagramPlacedText?]
    /// The storages the texts were written in; a layout's records start from them, so that its texts keep their places.
    let textStorages: DiagramPlacedTextStorages
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
        var storages = DiagramPlacedTextStorages()
        let nodeCount = diagram.nodeCount
        var nodeRecords: [FlowchartMeasuredNode] = []
        nodeRecords.reserveCapacity(nodeCount)
        var edgeRecords: [DiagramPlacedText?] = []
        edgeRecords.reserveCapacity(diagram.edgeCount)
        var assetNodeFlags: [Bool] = []
        diagram.model.text.withBytes { source in
            let model = diagram.model
            let nodeMeasuring = FlowchartTextMeasuring(model: model, measurer: nodeText, maximumWidth: wrappingWidth)
            for index in 0..<nodeCount {
                let node = model.nodes[index]
                let asset = diagram.nodeAsset(at: index)
                // A shape drawn without text (a start, a fork, a junction) and not as an icon or a picture measures none, as
                // Pele lays out no label for it.
                let measuresText = node.shape.holdsText || asset != nil
                let text = storages.place(nodeMeasuring.block(of: measuresText ? node.label : .none, source: source))
                if asset != nil {
                    if assetNodeFlags.isEmpty { assetNodeFlags = [Bool](repeating: false, count: nodeCount) }
                    assetNodeFlags[index] = true
                }
                let (size, textOffset) = asset?.size(textSize: text.size) ?? FlowchartShapeGeometry.size(of: node.shape, textSize: text.size)
                nodeRecords.append(FlowchartMeasuredNode(text: text, shapeSize: size, textOffset: textOffset))
            }
            let edgeMeasuring = FlowchartTextMeasuring(model: model, measurer: edgeText, maximumWidth: wrappingWidth)
            for edge in model.edges {
                // An edge's text of no line is none.
                guard edge.label.kind != .none else {
                    edgeRecords.append(nil)
                    continue
                }
                let text = edgeMeasuring.block(of: edge.label, source: source)
                edgeRecords.append(text.lineCount == 0 ? nil : storages.place(text))
            }
        }
        self.nodeRecords = nodeRecords
        self.edgeRecords = edgeRecords
        self.assetNodeFlags = assetNodeFlags
        textStorages = storages
        selfLoopEdgeIndices = FlowchartSelfLoopIndex(diagram: diagram)
    }

    /// A flowchart measured by a diagram drawn as one, which sizes its nodes its own way.
    init(nodeTexts: [DiagramTextBlock], shapeSizes: [CGSize], textOffsets: [CGFloat], edgeTexts: [DiagramTextBlock?],
         selfLoopEdgeIndices: FlowchartSelfLoopIndex) {
        precondition(shapeSizes.count == nodeTexts.count && textOffsets.count == nodeTexts.count, "a size and an offset for each node's text")
        var storages = DiagramPlacedTextStorages()
        var nodeRecords: [FlowchartMeasuredNode] = []
        nodeRecords.reserveCapacity(nodeTexts.count)
        for index in nodeTexts.indices {
            nodeRecords.append(FlowchartMeasuredNode(text: storages.place(nodeTexts[index]), shapeSize: shapeSizes[index], textOffset: textOffsets[index]))
        }
        self.nodeRecords = nodeRecords
        edgeRecords = edgeTexts.map { text in text.map { text in storages.place(text) } }
        textStorages = storages
        self.selfLoopEdgeIndices = selfLoopEdgeIndices
    }

    // MARK: Reading

    /// The text of `node`, placed in `textStorages`, at its measured center (none).
    @inline(__always)
    func nodeText(of node: Int) -> DiagramPlacedText { nodeRecords[node].text }

    @inline(__always)
    func shapeSize(of node: Int) -> CGSize { nodeRecords[node].shapeSize }

    /// How far below the shape's center of `node` its text's center is.
    @inline(__always)
    func textOffset(of node: Int) -> CGFloat { nodeRecords[node].textOffset }

    /// The text of edge `edgeIndex`, placed in `textStorages`, or nil.
    @inline(__always)
    func edgeText(of edgeIndex: Int) -> DiagramPlacedText? { edgeRecords[edgeIndex] }

    /// The size of the text of edge `edgeIndex`, or nil for an edge without text.
    @inline(__always)
    func edgeTextSize(of edgeIndex: Int) -> CGSize? { edgeRecords[edgeIndex]?.size }

    /// Each node's text as a block, for a reader that wants blocks (a swimlane).
    var nodeTexts: FlowchartMeasuredNodeTexts { FlowchartMeasuredNodeTexts(records: nodeRecords, storages: textStorages) }

    /// Each node's shape's size.
    var shapeSizes: FlowchartMeasuredShapeSizes { FlowchartMeasuredShapeSizes(records: nodeRecords) }

    /// How far below each shape's center its text's center is.
    var textOffsets: FlowchartMeasuredTextOffsets { FlowchartMeasuredTextOffsets(records: nodeRecords) }

    /// Each edge's text as a block, or nil, for a reader that wants blocks (a swimlane).
    var edgeTexts: FlowchartMeasuredEdgeTexts { FlowchartMeasuredEdgeTexts(records: edgeRecords, storages: textStorages) }

    /// Whether `node` is drawn as an icon or a picture.
    @inline(__always)
    func isAssetNode(_ node: Int) -> Bool { !assetNodeFlags.isEmpty && assetNodeFlags[node] }

    /// Whether the edges meeting `node` spread along its sides.
    @inline(__always)
    func spreadsEdgeEnds(of node: Int) -> Bool { spreadsEdgeEnds && !isAssetNode(node) }

    /// How much of the side of `node` facing `side` its edges share out between them (Pele's `shapeSpan`), or 0 where
    /// they all meet its middle.
    func sideSpan(of node: Int, shape: FlowchartNodeShape, side: DiagramSide) -> CGFloat {
        spreadsEdgeEnds(of: node) ? FlowchartShapeGeometry.span(of: shape, size: shapeSize(of: node), side: side) : 0
    }

    /// The shape of `node` as the layout meets it: its own, or a rectangle for a node drawn as an icon or a picture.
    @inline(__always)
    func layoutShape(of node: Int, in diagram: FlowchartDiagram) -> FlowchartNodeShape {
        isAssetNode(node) ? .rectangle : diagram.nodeShape(at: node)
    }

    /// One node's size in its rank: its shape, widened on both sides across the flow by the room its loops take, its loops
    /// going out of `loopSide`.
    func layoutSize(of node: Int, loopSide: DiagramSide) -> CGSize {
        let size = shapeSize(of: node)
        let loopEdgeIndices = selfLoopEdgeIndices[node]
        guard !loopEdgeIndices.isEmpty else { return size }
        let flowRunsAcross = loopSide == .bottom
        var room: CGFloat = 0
        for edgeIndex in loopEdgeIndices { room = room + FlowchartSelfLoops.room(textSize: edgeTextSize(of: edgeIndex), flowRunsAcross: flowRunsAcross) }
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
