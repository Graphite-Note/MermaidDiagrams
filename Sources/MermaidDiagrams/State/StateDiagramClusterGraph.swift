/**
 * File: StateDiagramClusterGraph.swift
 * ------------------------------------
 * Layer: Core
 * Description: A state diagram with composite states as a graph of nested boxes, each composite a box and each
 *              concurrent region a box inside it, written straight into the calling thread's scratch arena with every
 *              list the layout reads of it a span there.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.8
 * Date: 26/11/2026
 */

import CoreGraphics

/// A state diagram with composite states as a graph of nested boxes to lay out (`LayeredCompoundGraph`), as a flowchart's
/// subgraphs are: each composite state a box with Pele's 16 points of room inside it and its name in a band along its
/// top, running in its own direction or in that of the box around it; each concurrent region of a body that has several
/// a box of its own inside it, without a title; every other state in the box of the composite or region it was last
/// named in; and each transition between two different states or boxes, a transition to or from a composite state
/// meeting its box. The nodes, boxes and edges, and every list read of them, are spans of the calling thread's arena.
struct StateDiagramClusterGraph {
    /// The room inside a region's box around its states: less than a composite's, as the region's box is not drawn
    /// (Pele's `REGION_PAD`).
    static let regionPadding: CGFloat = 10
    /// The room inside a composite's box on its sides and below, and above below its title (Pele's `GROUP_PAD`).
    static let compositePadding: CGFloat = 16
    /// The room a composite's title takes beyond its line, half above it and half below (Pele's `titleH`).
    static let titleRoom: CGFloat = 12

    /// The states that are not composites and the anchors' and notes' points, then the boxes: composites first, then
    /// regions, then the unseen boxes around composites; and the transitions and notes' ties laid out.
    let graph: LayeredCompoundGraph
    /// Each node's size on the page, by its index in `graph`.
    let layoutSizes: ScratchSpan<CGSize>
    /// For each state, its node in `graph`, or -1 for a composite state, which is its box.
    let layoutNodeIndices: ScratchSpan<Int32>
    /// For each state, the composite it is (its index in `StateDiagram.composites`, which is its box's among `graph`'s
    /// boxes), or -1.
    let compositeIndices: ScratchSpan<Int32>
    /// The transitions laid out, in the order of `graph.edges`; a transition from a state to itself loops beside it.
    let layoutTransitionIndices: ScratchSpan<Int32>
    /// Each composite's name, measured, or nil for an empty one.
    let titles: [DiagramTextBlock?]
    /// How many composite boxes each composite's box is inside.
    let depths: ScratchSpan<Int32>
    /// For each composite whose states sit in several regions, its regions' boxes among `graph`'s boxes, in region order:
    /// a run of consecutive boxes, empty for the others.
    let regionBoxes: ScratchSpan<StateDiagramRegionBoxes>
    /// By transition index, for a transition between a composite and a state inside it, its anchor with the node in
    /// `graph` of the point inside the composite it runs from or to; empty for a diagram with no such transition.
    let anchors: ScratchSpan<PlacedAnchor>
    /// The direction each composite's box runs in.
    let compositeDirections: [FlowchartDirection]
    /// The notes beside composites and the unseen boxes around composites with notes or loops.
    let compositeSurroundings: StateDiagramCompositeSurroundings

    /// A transition's anchor and the node of its point inside the composite; -1 as the node for a transition with none.
    struct PlacedAnchor {
        let anchor: StateDiagramCompositeAnchor
        let layoutNodeIndex: Int
    }

    /// The composite `state` is, or nil.
    @inline(__always) func composite(of state: Int) -> Int? {
        let composite = compositeIndices[state]
        return composite < 0 ? nil : Int(composite)
    }

    /// The node of `state` in `graph`, or nil for a composite state.
    @inline(__always) func layoutNode(of state: Int) -> Int? {
        let node = layoutNodeIndices[state]
        return node < 0 ? nil : Int(node)
    }

    /// The anchor of the transition at `transitionIndex`, or nil.
    func anchor(of transitionIndex: Int) -> PlacedAnchor? {
        guard transitionIndex < anchors.count, anchors[transitionIndex].layoutNodeIndex >= 0 else { return nil }
        return anchors[transitionIndex]
    }

    /// Fails with `StateDiagramLayoutError.compositeStatesNotLaidOut` for a composite inside itself through its states.
    /// A composite with notes or loops sits in an unseen box with its notes (`StateDiagramCompositeSurroundings`).
    init<Measurer: DiagramTextMeasuring>(diagram: StateDiagram, measured: StateDiagramMeasurement, surroundings: StateDiagramSurroundings,
                                         flowIsVertical: Bool, titleText: Measurer, arena: DiagramScratchArena) throws(StateDiagramLayoutError) {
        let model = diagram.model
        let compositeIndices = arena.span(count: model.states.count, repeating: Int32(-1))
        for (compositeIndex, composite) in diagram.composites.enumerated() { compositeIndices[composite.stateIndex] = Int32(compositeIndex) }
        self.compositeIndices = compositeIndices
        titles = StateDiagramClusterParts.titles(of: diagram, titleText: titleText)
        depths = try StateDiagramClusterParts.depths(of: diagram, arena: arena)
        compositeDirections = StateDiagramCompositeAnchors.compositeDirections(of: diagram)
        let regions = StateDiagramRegionClusters(of: diagram, startingAt: diagram.composites.count, arena: arena)
        regionBoxes = regions.boxesByComposite
        let anchorList = StateDiagramCompositeAnchors.anchors(of: diagram, compositeIndices: compositeIndices, arena: arena)
        var nodes = StateDiagramClusterNodes(diagram: diagram, compositeIndices: compositeIndices, surroundings: surroundings, flowIsVertical: flowIsVertical,
                                             regions: regions, anchors: anchorList, arena: arena)
        layoutNodeIndices = nodes.layoutNodeIndices
        anchors = nodes.anchors
        // The notes beside composites are nodes too, after the states and anchors; the boxes' group nodes follow them all.
        let stateNodeCount = nodes.sizes.count
        let nodeCount = stateNodeCount + StateDiagramCompositeSurroundings.noteNodeCount(of: diagram, compositeIndices: compositeIndices)
        let containers: ScratchSpan<Int32> = arena.uninitializedSpan(count: diagram.composites.count)
        for (index, composite) in diagram.composites.enumerated() { containers[index] = Int32(regions.container(of: composite.stateIndex, in: model) ?? -1) }
        var boxes = StateDiagramClusterParts.boxes(of: diagram, titles: titles, containers: containers, regions: regions, nodeCount: nodeCount, arena: arena)
        compositeSurroundings = StateDiagramClusterParts.wrapComposites(of: diagram, measured: measured, compositeIndices: compositeIndices, containers: containers,
                                                                        directions: compositeDirections, boxes: &boxes, firstNode: stateNodeCount,
                                                                        nodeCount: nodeCount, arena: arena)
        var edges = arena.list(capacity: model.transitions.count + compositeSurroundings.edges.count, of: LayeredCompoundSpanEdge.self)
        layoutTransitionIndices = StateDiagramClusterParts.edges(of: diagram, measured: measured, layoutNodeIndices: layoutNodeIndices,
                                                                 compositeIndices: compositeIndices, anchors: anchors, nodeCount: nodeCount, into: &edges,
                                                                 arena: arena)
        edges.append(contentsOf: compositeSurroundings.edges.elements)
        for note in 0..<compositeSurroundings.nodeSizes.count {
            nodes.sizes.append(compositeSurroundings.nodeSizes[note])
            nodes.clusters.append(compositeSurroundings.nodeClusters[note])
        }
        layoutSizes = nodes.sizes.elements
        let sideSpans = StateDiagramClusterParts.sideSpans(of: diagram, measured: measured, layoutNodeIndices: layoutNodeIndices,
                                                           directions: compositeDirections, nodeCount: nodeCount, arena: arena)
        graph = Self.compoundGraph(nodes: nodes, sideSpans: sideSpans, boxes: boxes.elements, edges: edges.elements, direction: diagram.direction, arena: arena)
    }

    /// The nodes, each in its box with how far its ends spread, then the boxes, as the compound layout's graph.
    private static func compoundGraph(nodes: StateDiagramClusterNodes, sideSpans: ScratchSpan<CGFloat>, boxes: ScratchSpan<LayeredCompoundNode>,
                                      edges: ScratchSpan<LayeredCompoundSpanEdge>, direction: FlowchartDirection,
                                      arena: DiagramScratchArena) -> LayeredCompoundGraph {
        let nodeCount = nodes.sizes.count
        let compoundNodes: ScratchSpan<LayeredCompoundNode> = arena.uninitializedSpan(count: nodeCount + boxes.count)
        for node in 0..<nodeCount {
            let box = nodes.clusters[node]
            compoundNodes[node] = .member(size: nodes.sizes[node], box: box < 0 ? nil : Int(box), nodeCount: nodeCount, sequence: node,
                                          sideSpan: sideSpans[node])
        }
        for index in 0..<boxes.count { compoundNodes[nodeCount + index] = boxes[index] }
        return LayeredCompoundGraph(nodes: compoundNodes, edges: edges, nodeCount: nodeCount, direction: direction.layeredDirection)
    }
}

/// The boxes of a composite's concurrent regions: a run of consecutive boxes among the graph's, by their index there.
struct StateDiagramRegionBoxes {
    let first: Int32
    let count: Int32

    var indices: Range<Int> { Int(first)..<Int(first + count) }
}
