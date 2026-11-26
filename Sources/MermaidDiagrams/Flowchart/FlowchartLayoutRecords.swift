/**
 * File: FlowchartLayoutRecords.swift
 * ----------------------------------
 * Layer: Core
 * Description: A laid-out flowchart's nodes and edges as flat records: each a few numbers, every edge's segments in one
 *              list, their texts placed without a storage reference, and the styles and pictures of the few nodes and
 *              edges that have them listed apart, so that the scene reads them once and a layout frees in a few steps.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics

/// A node where the layout keeps it: its shape's kind and bounding box, its text, and where its style and its icon or
/// picture are among the layout's, when it has them.
struct FlowchartPlacedNode: Sendable {
    let shape: FlowchartNodeShape
    let frame: CGRect
    let text: DiagramPlacedText
    /// The node's style among the layout's styles, or -1 for the usual look.
    let styleIndex: Int32
    /// The node's icon or picture among the layout's assets, or -1 for none.
    let assetIndex: Int32

    var hasUsualLook: Bool { styleIndex < 0 }
    var hasAsset: Bool { assetIndex >= 0 }
}

/// An edge where the layout keeps it: its stroke, its line as a start and a run of the layout's segments, its marks,
/// its text and where its style is among the layout's.
struct FlowchartPlacedEdge: Sendable {
    let stroke: FlowchartEdgeStroke
    let start: CGPoint
    /// The line's segments: `segmentCount` of the layout's segments from `firstSegment`.
    let firstSegment: Int32
    let segmentCount: Int32
    let sourceMark: DiagramEdgeMark?
    let targetMark: DiagramEdgeMark?
    let text: DiagramPlacedText?
    /// The edge's style among the layout's styles, or -1 for the usual look.
    let styleIndex: Int32

    var hasUsualLook: Bool { styleIndex < 0 }

    /// Whether the edge is painted apart, in the stroke or colors the diagram gave it, as `FlowchartEdgePaths.isStyled`
    /// tells of a layout edge.
    var isStyled: Bool { styleIndex >= 0 && stroke != .invisible }
}

/// A laid-out flowchart's nodes and edges as flat records, read by its scene and drawing parts where they lie, and made
/// into `FlowchartLayoutNode` and `FlowchartLayoutEdge` values, equal to those the layout once kept, only when asked. The
/// nodes, edges and segments are one block of memory (`FlowchartLayoutRecordBlock`), which also keeps their texts'
/// storages and the styles and assets of the few that have them (lists empty for most flowcharts): records copy as one
/// reference.
struct FlowchartLayoutRecords: Sendable {
    private let recordBlock: FlowchartLayoutRecordBlock

    init() {
        recordBlock = .empty
    }

    /// The records of nodes and edges kept as values (a swimlane's flowchart, a layout a test makes), each written once
    /// into the block.
    init(nodes layoutNodes: [FlowchartLayoutNode], edges layoutEdges: [FlowchartLayoutEdge]) {
        var segmentCount = 0
        for edge in layoutEdges { segmentCount += edge.path.segments.count }
        let counts = FlowchartLayoutRecordCounts(nodeCount: layoutNodes.count, edgeCount: layoutEdges.count, segmentCount: segmentCount)
        recordBlock = FlowchartLayoutRecordBlock.make(counts: counts) { nodeStart, edgeStart, segmentStart in
            var textStorages = DiagramPlacedTextStorages()
            var styles: [DiagramElementStyle] = []
            var assets: [FlowchartNodeAsset] = []
            for (index, node) in layoutNodes.enumerated() {
                (nodeStart + index).initialize(to: FlowchartPlacedNode(shape: node.shape, frame: node.frame, text: textStorages.place(node.text),
                                                                       styleIndex: Self.listed(node.style, in: &styles),
                                                                       assetIndex: Self.listed(node.asset, in: &assets)))
            }
            var segmentIndex = 0
            for (index, edge) in layoutEdges.enumerated() {
                let firstSegment = segmentIndex
                for segment in edge.path.segments {
                    (segmentStart + segmentIndex).initialize(to: segment)
                    segmentIndex += 1
                }
                (edgeStart + index).initialize(to: FlowchartPlacedEdge(stroke: edge.stroke, start: edge.path.start, firstSegment: Int32(firstSegment),
                                                                       segmentCount: Int32(segmentIndex - firstSegment), sourceMark: edge.sourceMark,
                                                                       targetMark: edge.targetMark, text: edge.text.map { text in textStorages.place(text) },
                                                                       styleIndex: Self.listed(edge.style, in: &styles)))
            }
            return (textStorages, styles, assets)
        }
    }

    /// The records a recording made in its arena, copied once into one block.
    init(recorded recording: borrowing FlowchartLayoutRecording) {
        let nodes = recording.nodes.elements
        let edges = recording.edges.elements
        let segments = recording.segments.elements
        let rest = (recording.textStorages, recording.styles, recording.assets)
        let counts = FlowchartLayoutRecordCounts(nodeCount: nodes.count, edgeCount: edges.count, segmentCount: segments.count)
        recordBlock = FlowchartLayoutRecordBlock.make(counts: counts) { nodeStart, edgeStart, segmentStart in
            nodeStart.initialize(from: nodes.start, count: nodes.count)
            edgeStart.initialize(from: edges.start, count: edges.count)
            segmentStart.initialize(from: segments.start, count: segments.count)
            return rest
        }
    }

    /// `value` listed, its index; -1 for none.
    private static func listed<Value>(_ value: Value?, in list: inout [Value]) -> Int32 {
        guard let value else { return -1 }
        list.append(value)
        return Int32(list.count - 1)
    }

    // MARK: Reading

    var nodes: FlowchartLayoutRecordList<FlowchartPlacedNode> {
        FlowchartLayoutRecordList(block: recordBlock, offset: 0, count: recordBlock.counts.nodeCount)
    }

    var edges: FlowchartLayoutRecordList<FlowchartPlacedEdge> {
        let counts = recordBlock.counts
        return FlowchartLayoutRecordList(block: recordBlock, offset: counts.edgeOffset, count: counts.edgeCount)
    }

    private var segments: FlowchartLayoutRecordList<DiagramPathSegment> {
        let counts = recordBlock.counts
        return FlowchartLayoutRecordList(block: recordBlock, offset: counts.segmentOffset, count: counts.segmentCount)
    }

    /// The block of a text placed here.
    @inline(__always)
    func block(_ text: DiagramPlacedText) -> DiagramTextBlock { recordBlock.withHeader { header in header.textStorages.block(text) } }

    func style(at index: Int32) -> DiagramElementStyle? { index < 0 ? nil : recordBlock.withHeader { header in header.styles[Int(index)] } }

    func asset(at index: Int32) -> FlowchartNodeAsset? { index < 0 ? nil : recordBlock.withHeader { header in header.assets[Int(index)] } }

    /// Calls `body` with the edge's segments where the layout keeps them.
    @inline(__always)
    func withSegments<Result>(of edge: FlowchartPlacedEdge, _ body: (UnsafeBufferPointer<DiagramPathSegment>) -> Result) -> Result {
        precondition(edge.firstSegment >= 0 && edge.segmentCount >= 0, "an edge's segments outside the layout's")
        return segments.withRecords(in: Int(edge.firstSegment)..<(Int(edge.firstSegment) + Int(edge.segmentCount)), body)
    }

    /// The edge's line as a path of its own.
    func path(of edge: FlowchartPlacedEdge) -> DiagramPath {
        DiagramPath(start: edge.start, segments: withSegments(of: edge) { segments in Array(segments) })
    }

    /// Node `index` as the layout once kept it.
    func layoutNode(at index: Int) -> FlowchartLayoutNode {
        let node = nodes[index]
        return FlowchartLayoutNode(shape: node.shape, frame: node.frame, text: block(node.text), style: style(at: node.styleIndex),
                                   asset: asset(at: node.assetIndex))
    }

    /// Edge `index` as the layout once kept it.
    func layoutEdge(at index: Int) -> FlowchartLayoutEdge {
        let edge = edges[index]
        return FlowchartLayoutEdge(stroke: edge.stroke, path: path(of: edge), sourceMark: edge.sourceMark, targetMark: edge.targetMark,
                                   text: edge.text.map(block), style: style(at: edge.styleIndex))
    }
}

/// A laid-out flowchart's records as its layout writes them, in lists of the calling thread's arena, each piece once and
/// already where it lies on the page; `FlowchartLayoutRecords(recorded:)` copies each list once into the layout.
struct FlowchartLayoutRecording: ~Copyable {
    fileprivate(set) var nodes: ScratchList<FlowchartPlacedNode>
    fileprivate(set) var edges: ScratchList<FlowchartPlacedEdge>
    /// The segments of the edges placed so far; an edge being placed appends its own after them.
    var segments: ScratchList<DiagramPathSegment>
    fileprivate(set) var textStorages: DiagramPlacedTextStorages
    fileprivate(set) var styles: [DiagramElementStyle] = []
    fileprivate(set) var assets: [FlowchartNodeAsset] = []

    /// A recording whose texts are placed in `textStorages`, the storages of the measurement they come from.
    init(nodeCapacity: Int, edgeCapacity: Int, textStorages: DiagramPlacedTextStorages, arena: DiagramScratchArena) {
        nodes = arena.list(capacity: nodeCapacity, of: FlowchartPlacedNode.self)
        edges = arena.list(capacity: edgeCapacity, of: FlowchartPlacedEdge.self)
        segments = arena.list(capacity: 2 * edgeCapacity, of: DiagramPathSegment.self)
        self.textStorages = textStorages
    }

    /// A node whose shape is `frame`, its text `text`, placed in the recording's storages, already where it lies.
    mutating func appendNode(shape: FlowchartNodeShape, frame: CGRect, text: DiagramPlacedText, style: DiagramElementStyle?, asset: FlowchartNodeAsset?) {
        precondition(text.storageIndex >= 0 && Int(text.storageIndex) < textStorages.count, "a node's text placed in other storages")
        let styleIndex = listed(style)
        let assetIndex: Int32
        if let asset {
            assets.append(asset)
            assetIndex = Int32(assets.count - 1)
        } else {
            assetIndex = -1
        }
        nodes.append(FlowchartPlacedNode(shape: shape, frame: frame, text: text, styleIndex: styleIndex, assetIndex: assetIndex))
    }

    /// An edge whose line starts at `start` and runs through the segments appended since `firstSegment`, its text, if
    /// any, placed in the recording's storages.
    mutating func appendEdge(stroke: FlowchartEdgeStroke, start: CGPoint, firstSegment: Int, sourceMark: DiagramEdgeMark?, targetMark: DiagramEdgeMark?,
                             text: DiagramPlacedText?, style: DiagramElementStyle?) {
        precondition(firstSegment >= 0 && firstSegment <= segments.count, "an edge's first segment past the segments appended")
        precondition(text.map { text in text.storageIndex >= 0 && Int(text.storageIndex) < textStorages.count } ?? true,
                     "an edge's text placed in other storages")
        edges.append(FlowchartPlacedEdge(stroke: stroke, start: start, firstSegment: Int32(firstSegment), segmentCount: Int32(segments.count - firstSegment),
                                         sourceMark: sourceMark, targetMark: targetMark, text: text, styleIndex: listed(style)))
    }

    private mutating func listed(_ style: DiagramElementStyle?) -> Int32 {
        guard let style else { return -1 }
        styles.append(style)
        return Int32(styles.count - 1)
    }
}
