/**
 * File: FlowchartBoxedLayout.swift
 * --------------------------------
 * Layer: Core
 * Description: A flowchart with groups laid out in nested boxes and put on the page in the scratch arena: the compound
 *              layout's nodes, boxes and routes read where it left them, and the nodes and edges written once, as flat
 *              records, at their place on the page.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 26/11/2026
 */

import CoreGraphics

/// A flowchart with subgraphs, as Pele lays it out: each group a box laid out on its own and placed in the box around it
/// (`FlowchartClusterGraph`, `LayeredCompoundLayout`); then each node at its center on the page (a node that stands for a
/// group at its box's), each edge from the outline of its node or box to the other's through the points its route
/// passes, the ends on one side spread along it clear of the edges crossing a box's border there, the loops beside
/// their nodes, each box with its title clear of the edges where it can be, and everything moved inside the padding
/// below the title. The compound layout's spans are read in the calling thread's arena; only the layout's records and
/// boxes are allocated.
enum FlowchartBoxedLayout {
    /// The layout, or nil when the boxes would need more than `maximumPointCount` nodes and passing points.
    static func layout<Measurer: DiagramTextMeasuring>(_ diagram: FlowchartDiagram, measured: FlowchartMeasurement, titleText: Measurer, font: DiagramFont,
                                                       spacing: LayeredSpacing, groupPadding: CGFloat, maximumPointCount: Int, title: DiagramTextBlock?,
                                                       arena: DiagramScratchArena) -> FlowchartLayout? {
        let clustered = FlowchartClusterGraph(diagram: diagram, measured: measured, titleText: titleText,
                                              edgeTextRoom: FlowchartLayoutEngine.edgeTextRoom, groupPadding: groupPadding, arena: arena)
        guard let compound = clustered.graph.laidOut(spacing: spacing, maximumPointCount: maximumPointCount, arena: arena) else { return nil }
        let boxes = FlowchartPlacedBoxes(diagram, clustered: clustered, compound: compound, measured: measured, arena: arena)
        let frame = FlowchartPageFrame(extent: CGSize(width: compound.total.width, height: compound.total.height), title: title)
        var edgePoints = arena.list(capacity: 4 * diagram.edgeCount, of: CGPoint.self)
        var recording = FlowchartLayoutRecording(nodeCapacity: diagram.nodeCount, edgeCapacity: diagram.edgeCount, textStorages: measured.textStorages,
                                                  arena: arena)
        boxes.appendPageEdges(diagram, measured: measured, offset: frame.offset, edgePoints: &edgePoints, to: &recording, arena: arena)
        var sortedPoints = edgePoints.elements.buffer
        sortedPoints.sort { first, second in first.y < second.y }
        var clusters: [FlowchartLayoutCluster] = []
        clusters.reserveCapacity(clustered.titles.count)
        for subgraph in 0..<clustered.titles.count {
            let box = boxes.frames[subgraph]
            let title = clustered.titles[subgraph].map { title in FlowchartClusterTitles.placed(title, in: box, sortedPoints: edgePoints.elements) }
            clusters.append(FlowchartLayoutCluster(frame: box, title: title?.title, depth: clustered.depths[subgraph], isTitleCrossed: title?.isCrossed ?? false)
                .translated(by: frame.offset))
        }
        for node in 0..<diagram.nodeCount where clustered.representedSubgraphs[node] == nil {
            FlowchartPagePieces.appendNode(node, of: diagram, center: boxes.nodeCenters[node], measured: measured, offset: frame.offset, to: &recording)
        }
        return FlowchartLayout(size: frame.size, font: font, records: FlowchartLayoutRecords(recorded: recording), title: frame.title, clusters: clusters)
    }
}

/// The compound layout of a flowchart's boxes read on the page: each node's center, each box's frame, and each laid-out
/// edge's route, whether it runs between a box and what it holds, and its text's center.
struct FlowchartPlacedBoxes {
    let clustered: FlowchartClusterGraph
    let compound: LayeredCompoundLayout
    /// Each diagram node's center on the page; a node that stands for a group at the center of its box.
    let nodeCenters: ScratchSpan<CGPoint>
    /// Each group's box.
    let frames: ScratchSpan<CGRect>
    /// By laid-out edge, whether it runs between a box and what it holds.
    let isStray: ScratchSpan<Bool>

    init(_ diagram: FlowchartDiagram, clustered: FlowchartClusterGraph, compound: LayeredCompoundLayout, measured: FlowchartMeasurement,
         arena: DiagramScratchArena) {
        self.clustered = clustered
        self.compound = compound
        let layoutNodeCount = clustered.graph.nodeCount
        frames = arena.uninitializedSpan(count: clustered.graph.boxCount)
        for cluster in 0..<frames.count { frames[cluster] = compound.nodes[layoutNodeCount + cluster].frame }
        nodeCenters = arena.uninitializedSpan(count: diagram.nodeCount)
        for node in 0..<diagram.nodeCount {
            if let subgraph = clustered.representedSubgraphs[node] {
                nodeCenters[node] = CGPoint(x: frames[subgraph].midX, y: frames[subgraph].midY)
            } else {
                let layoutNode = compound.nodes[clustered.layoutNodeIndices[node] ?? 0]
                nodeCenters[node] = CGPoint(x: layoutNode.x, y: layoutNode.y)
            }
        }
        isStray = arena.uninitializedSpan(count: compound.edges.count)
        for edge in 0..<compound.edges.count { isStray[edge] = compound.isStray(edge) }
    }

    /// The route of laid-out edge `edge`'s points.
    @inline(__always)
    func route(of edge: Int) -> ArraySlice<LayeredRoutePoint> { compound.routePoints[compound.routeRange(of: edge)] }

    /// The center of laid-out edge `edge`'s text, or nil for an edge without text (but one between a box and what it
    /// holds, which has its middle).
    func labelCenter(of edge: Int) -> CGPoint? {
        compound.edges[edge].labelWidth > 0 || isStray[edge] ? compound.edges[edge].labelCenter : nil
    }

    /// For each segment of laid-out edge `edge`'s route, whether the flow it follows runs vertically.
    func segmentsRunVertically(of edge: Int, arena: DiagramScratchArena) -> ScratchSpan<Bool> {
        let route = route(of: edge)
        let segments: ScratchSpan<Bool> = arena.uninitializedSpan(count: max(route.count - 1, 0))
        for (index, point) in route.dropFirst().enumerated() { segments[index] = !point.runsHorizontally }
        return segments
    }
}
