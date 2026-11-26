/**
 * File: StateDiagramClusterGraph.swift
 * ------------------------------------
 * Layer: Core
 * Description: A state diagram with composite states as nested boxes to lay out, as a flowchart's subgraphs are, written
 *              into the compound layout's spans.
 *
 * Authors: Bahey Shalash
 * Version: 0.6
 * Date: 25/11/2026
 */

import CoreGraphics

/// A state diagram with composite states as a graph of nested boxes to lay out (`LayeredCompoundGraph`), as a flowchart's
/// subgraphs are: each composite state a box with Pele's 16 points of room inside it and its name in a band along its
/// top, running in its own direction or in that of the box around it; each concurrent region of a body that has several
/// a box of its own inside it, without a title; every other state in the box of the composite or region it was last
/// named in; and each transition between two different states or boxes, a transition to or from a composite state
/// meeting its box. The nodes, boxes and edges are written once, straight into the calling thread's arena.
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
    /// For each state, its node in `graph`, or nil for a composite state, which is its box.
    let layoutNodeIndices: [Int?]
    /// For each state, the composite it is (its index in `StateDiagram.composites`, which is its box's among `graph`'s
    /// boxes), or nil.
    let compositeOfState: [Int?]
    /// The transitions laid out, in the order of `graph.edges`; a transition from a state to itself loops beside it.
    let layoutTransitionIndices: [Int]
    /// Each composite's name, measured, or nil for an empty one.
    let titles: [DiagramTextBlock?]
    /// How many composite boxes each composite's box is inside.
    let depths: [Int]
    /// For each composite whose states sit in several regions, its regions' boxes among `graph`'s boxes, in region order.
    let regionClusterIndices: [[Int]]
    /// By transition index, for a transition between a composite and a state inside it, its anchor with the node in
    /// `graph` of the point inside the composite it runs from or to; nil for the other transitions.
    let anchors: [PlacedAnchor?]

    /// A transition's anchor and the node of its point inside the composite.
    struct PlacedAnchor {
        let anchor: StateDiagramCompositeAnchor
        let layoutNodeIndex: Int
    }
    /// The direction each composite's box runs in.
    let compositeDirections: [FlowchartDirection]
    /// The notes beside composites and the unseen boxes around composites with notes or loops.
    let compositeSurroundings: StateDiagramCompositeSurroundings

    /// Fails with `StateDiagramLayoutError.compositeStatesNotLaidOut` for a composite inside itself through its states.
    /// A composite with notes or loops sits in an unseen box with its notes (`StateDiagramCompositeSurroundings`).
    init<Measurer: DiagramTextMeasuring>(diagram: StateDiagram, measured: StateDiagramMeasurement, surroundings: StateDiagramSurroundings,
                                         flowIsVertical: Bool, titleText: Measurer, arena: DiagramScratchArena) throws(StateDiagramLayoutError) {
        var compositeOfState = [Int?](repeating: nil, count: diagram.states.count)
        for (compositeIndex, composite) in diagram.composites.enumerated() { compositeOfState[composite.stateIndex] = compositeIndex }
        self.compositeOfState = compositeOfState
        let measuredTitles = Self.titles(of: diagram, titleText: titleText)
        titles = measuredTitles
        depths = try Self.depths(of: diagram)
        compositeDirections = StateDiagramCompositeAnchors.compositeDirections(of: diagram)
        let regions = Self.regionClusters(of: diagram, startingAt: diagram.composites.count)
        regionClusterIndices = regions.indicesByComposite
        let anchors = StateDiagramCompositeAnchors.anchors(of: diagram, compositeOfState: compositeOfState)
        let nodes = Self.nodes(of: diagram, compositeOfState: compositeOfState, surroundings: surroundings, flowIsVertical: flowIsVertical, regions: regions,
                               anchors: anchors)
        layoutNodeIndices = nodes.layoutNodeIndices
        self.anchors = nodes.anchors
        // The notes beside composites are nodes too, after the states and anchors; the boxes' group nodes follow them all.
        let nodeCount = nodes.sizes.count + StateDiagramCompositeSurroundings.noteNodeCount(of: diagram, compositeOfState: compositeOfState)
        let containers = diagram.composites.map { composite in regions.container(of: composite.stateIndex, in: diagram) }
        var boxes = Self.boxes(of: diagram, titles: measuredTitles, containers: containers, regions: regions, nodeCount: nodeCount)
        let compositeSurroundings = Self.wrapComposites(of: diagram, measured: measured, compositeOfState: compositeOfState, containers: containers,
                                                        directions: compositeDirections, boxes: &boxes, firstNode: nodes.sizes.count, nodeCount: nodeCount)
        self.compositeSurroundings = compositeSurroundings
        var edges = arena.list(capacity: diagram.transitions.count + compositeSurroundings.edges.count, of: LayeredCompoundSpanEdge.self)
        layoutTransitionIndices = Self.edges(of: diagram, measured: measured, layoutNodeIndices: nodes.layoutNodeIndices, compositeOfState: compositeOfState,
                                             anchors: nodes.anchors, nodeCount: nodeCount, into: &edges)
        for edge in compositeSurroundings.edges { edges.append(edge) }
        let sideSpans = Self.sideSpans(of: diagram, measured: measured, layoutNodeIndices: nodes.layoutNodeIndices, directions: compositeDirections,
                                       nodeCount: nodeCount)
        layoutSizes = arena.uninitializedSpan(count: nodeCount)
        for node in 0..<nodeCount {
            layoutSizes[node] = node < nodes.sizes.count ? nodes.sizes[node] : compositeSurroundings.nodeSizes[node - nodes.sizes.count]
        }
        let compoundNodes: ScratchSpan<LayeredCompoundNode> = arena.uninitializedSpan(count: nodeCount + boxes.count)
        for node in 0..<nodeCount {
            let box = node < nodes.sizes.count ? nodes.clusters[node] : compositeSurroundings.nodeClusters[node - nodes.sizes.count]
            compoundNodes[node] = .member(size: layoutSizes[node], box: box, nodeCount: nodeCount, sequence: node, sideSpan: sideSpans[node])
        }
        for (index, box) in boxes.enumerated() { compoundNodes[nodeCount + index] = box }
        graph = LayeredCompoundGraph(nodes: compoundNodes, edges: edges.elements, nodeCount: nodeCount, direction: diagram.direction.layeredDirection)
    }

    /// Each composite's name, measured, or nil for an empty one.
    private static func titles<Measurer: DiagramTextMeasuring>(of diagram: StateDiagram, titleText: Measurer) -> [DiagramTextBlock?] {
        diagram.composites.map { composite in
            let title = DiagramTextBlock(label: diagram.states[composite.stateIndex].name, measurer: titleText, maximumWidth: .greatestFiniteMagnitude)
            return title.lineCount == 0 ? nil : title
        }
    }

    /// How much of its box's sides each state shares out between its transitions, across the flow of the box it sits in;
    /// 0 for the other nodes.
    private static func sideSpans(of diagram: StateDiagram, measured: StateDiagramMeasurement, layoutNodeIndices: [Int?],
                                  directions: [FlowchartDirection], nodeCount: Int) -> [CGFloat] {
        var spans = [CGFloat](repeating: 0, count: nodeCount)
        for (state, node) in layoutNodeIndices.enumerated() {
            guard let node else { continue }
            let direction = diagram.states[state].compositeIndex.map { composite in directions[composite] } ?? diagram.direction
            spans[node] = measured.sideSpan(of: state, in: diagram, flowIsVertical: !direction.runsAcross)
        }
        return spans
    }

    /// The composites' boxes, each directly in its container, then for each composite whose states sit in several regions
    /// its regions' boxes, in region order, every one's place in the declaration order after the `nodeCount` nodes.
    private static func boxes(of diagram: StateDiagram, titles: [DiagramTextBlock?], containers: [Int?], regions: RegionClusters,
                              nodeCount: Int) -> [LayeredCompoundNode] {
        var boxes = diagram.composites.indices.map { compositeIndex in
            compositeBox(direction: diagram.composites[compositeIndex].direction, title: titles[compositeIndex], container: containers[compositeIndex],
                         nodeCount: nodeCount, sequence: nodeCount + compositeIndex)
        }
        let padding = LayeredClusterPadding(side: regionPadding, top: regionPadding, bottom: regionPadding)
        for (compositeIndex, regionIndices) in regions.indicesByComposite.enumerated() {
            for _ in regionIndices {
                boxes.append(.box(parent: compositeIndex, nodeCount: nodeCount, direction: nil, padding: padding, minimumWidth: 0,
                                  sequence: CGFloat(nodeCount + boxes.count)))
            }
        }
        return boxes
    }

    /// Puts each composite with notes or loops in an unseen box of its own, which runs across while the composite keeps
    /// running as the box it was in did, and appends those boxes to `boxes`.
    private static func wrapComposites(of diagram: StateDiagram, measured: StateDiagramMeasurement, compositeOfState: [Int?], containers: [Int?],
                                       directions: [FlowchartDirection], boxes: inout [LayeredCompoundNode], firstNode: Int,
                                       nodeCount: Int) -> StateDiagramCompositeSurroundings {
        let surroundings = StateDiagramCompositeSurroundings(
            diagram: diagram, measured: measured, compositeOfState: compositeOfState, containers: containers,
            containerRunsVertically: diagram.composites.map { composite in
                !(diagram.states[composite.stateIndex].compositeIndex.map { directions[$0] } ?? diagram.direction).runsAcross
            }, firstCluster: boxes.count, firstNode: firstNode, nodeCount: nodeCount)
        for (compositeIndex, wrapper) in surroundings.wrapperClusters {
            boxes[compositeIndex].parent = nodeCount + wrapper
            boxes[compositeIndex].direction = directions[compositeIndex].layeredDirection
        }
        boxes += surroundings.clusters
        return surroundings
    }

    /// The states that are not composites as nodes, in the layout's order: each one's place with its notes and loops on
    /// the page, and the box it sits directly in; with the points of no size the anchored transitions run from or to,
    /// those leaving a composite after the starts and before the other states, those arriving after them all.
    private static func nodes(of diagram: StateDiagram, compositeOfState: [Int?], surroundings: StateDiagramSurroundings, flowIsVertical: Bool,
                              regions: RegionClusters, anchors: [StateDiagramCompositeAnchor])
        -> (layoutNodeIndices: [Int?], sizes: [CGSize], clusters: [Int?], anchors: [PlacedAnchor?]) {
        var layoutNodeIndices = [Int?](repeating: nil, count: diagram.states.count)
        var sizes: [CGSize] = []
        var clusters: [Int?] = []
        sizes.reserveCapacity(diagram.states.count + anchors.count)
        clusters.reserveCapacity(diagram.states.count + anchors.count)
        var placedAnchors = [PlacedAnchor?](repeating: nil, count: anchors.isEmpty ? 0 : diagram.transitions.count)
        func place(inward: Bool) {
            for anchor in anchors where anchor.isInward == inward {
                placedAnchors[anchor.transitionIndex] = PlacedAnchor(anchor: anchor, layoutNodeIndex: sizes.count)
                sizes.append(.zero)
                clusters.append(anchor.compositeIndex)
            }
        }
        var inwardPlaced = false
        for state in StateDiagramLayoutEngine.flowOrder(of: diagram) where compositeOfState[state] == nil {
            if !inwardPlaced, !diagram.states[state].kind.isStart {
                place(inward: true)
                inwardPlaced = true
            }
            layoutNodeIndices[state] = sizes.count
            let place = surroundings.placeSizes[state]
            sizes.append(flowIsVertical ? CGSize(width: place.across, height: place.along) : CGSize(width: place.along, height: place.across))
            clusters.append(regions.container(of: state, in: diagram))
        }
        if !inwardPlaced { place(inward: true) }
        place(inward: false)
        return (layoutNodeIndices, sizes, clusters, placedAnchors)
    }

    /// A composite's box, as Pele's state diagrams have it: 16 points of room, its name's band along the top (the name
    /// and 12 points), at least as wide as its name and the room on both sides; directly in box `container`, or at the
    /// top level.
    private static func compositeBox(direction: FlowchartDirection?, title: DiagramTextBlock?, container: Int?, nodeCount: Int,
                                     sequence: Int) -> LayeredCompoundNode {
        let padding = compositePadding
        let titleSize = title?.size ?? .zero
        let top = (title == nil ? 0 : titleSize.height + titleRoom) + padding
        return .box(parent: container, nodeCount: nodeCount, direction: direction?.layeredDirection,
                    padding: LayeredClusterPadding(side: padding, top: top, bottom: padding), minimumWidth: titleSize.width + 2 * padding,
                    sequence: CGFloat(sequence))
    }

    /// The regions' boxes: for each composite whose states (composite ones included) sit in more than one region, one box per
    /// region that holds a state, numbered from `firstClusterIndex` in region order. A body with one region has none.
    private static func regionClusters(of diagram: StateDiagram, startingAt firstClusterIndex: Int) -> RegionClusters {
        // Each region named, once, in the order of its composite then its index.
        var regions: [RegionKey] = []
        for state in diagram.states {
            guard let compositeIndex = state.compositeIndex, compositeIndex < diagram.composites.count else { continue }
            regions.append(RegionKey(compositeIndex: compositeIndex, regionIndex: state.regionIndex))
        }
        regions.sort()
        var uniqueCount = 0
        for region in regions where uniqueCount == 0 || regions[uniqueCount - 1] != region {
            regions[uniqueCount] = region
            uniqueCount += 1
        }
        regions.removeLast(regions.count - uniqueCount)
        var nextClusterIndex = firstClusterIndex
        var clusterOfRegion = [Int?](repeating: nil, count: regions.count)
        var indicesByComposite = [[Int]](repeating: [], count: diagram.composites.count)
        var first = 0
        while first < regions.count {
            var end = first + 1
            while end < regions.count, regions[end].compositeIndex == regions[first].compositeIndex { end += 1 }
            if end - first > 1 {
                var indices: [Int] = []
                indices.reserveCapacity(end - first)
                for region in first..<end {
                    clusterOfRegion[region] = nextClusterIndex
                    indices.append(nextClusterIndex)
                    nextClusterIndex += 1
                }
                indicesByComposite[regions[first].compositeIndex] = indices
            }
            first = end
        }
        return RegionClusters(indicesByComposite: indicesByComposite, regions: regions, clusterOfRegion: clusterOfRegion)
    }

    private struct RegionKey: Comparable {
        let compositeIndex: Int
        let regionIndex: Int

        static func < (first: RegionKey, second: RegionKey) -> Bool {
            (first.compositeIndex, first.regionIndex) < (second.compositeIndex, second.regionIndex)
        }
    }

    private struct RegionClusters {
        let indicesByComposite: [[Int]]
        /// Every region a state is named in, sorted, each once.
        let regions: [RegionKey]
        /// For each of `regions`, its box, or nil when its composite's body has one region.
        let clusterOfRegion: [Int?]

        /// The box a state sits directly in: its region's, when its composite's body has several, else its composite's;
        /// nil at the top level.
        func container(of state: Int, in diagram: StateDiagram) -> Int? {
            guard let compositeIndex = diagram.states[state].compositeIndex else { return nil }
            let key = RegionKey(compositeIndex: compositeIndex, regionIndex: diagram.states[state].regionIndex)
            var low = 0
            var high = regions.count
            while low < high {
                let middle = (low + high) / 2
                if regions[middle] < key { low = middle + 1 } else { high = middle }
            }
            guard low < regions.count, regions[low] == key else { return compositeIndex }
            return clusterOfRegion[low] ?? compositeIndex
        }
    }

    /// How many composites each composite is inside, through the composites its state was last named in. A composite
    /// found inside itself fails: the chain of its parents never reaches the top level.
    private static func depths(of diagram: StateDiagram) throws(StateDiagramLayoutError) -> [Int] {
        try diagram.composites.map { composite throws(StateDiagramLayoutError) in
            var depth = 0
            var parent = diagram.states[composite.stateIndex].compositeIndex
            while let parentIndex = parent {
                depth += 1
                guard depth <= diagram.composites.count else { throw .compositeStatesNotLaidOut }
                parent = diagram.states[diagram.composites[parentIndex].stateIndex].compositeIndex
            }
            return depth
        }
    }

    /// The transitions between two different ends, with their texts' room, appended to `edges`, a composite's end at its
    /// box's node after the `nodeCount` nodes; a transition from a state or a composite to itself loops beside it and is
    /// not laid out. Returns the index of each transition appended.
    private static func edges(of diagram: StateDiagram, measured: StateDiagramMeasurement, layoutNodeIndices: [Int?], compositeOfState: [Int?],
                              anchors: [PlacedAnchor?], nodeCount: Int, into edges: inout ScratchList<LayeredCompoundSpanEdge>) -> [Int] {
        func end(of state: Int) -> Int {
            if let compositeIndex = compositeOfState[state] { return nodeCount + compositeIndex }
            return layoutNodeIndices[state] ?? 0
        }
        let room = StateDiagramLayoutEngine.transitionTextRoom
        var transitionIndices: [Int] = []
        transitionIndices.reserveCapacity(diagram.transitions.count)
        for (transitionIndex, transition) in diagram.transitions.enumerated() {
            var source = end(of: transition.sourceIndex)
            var target = end(of: transition.targetIndex)
            if transitionIndex < anchors.count, let anchored = anchors[transitionIndex] {
                if anchored.anchor.isInward { source = anchored.layoutNodeIndex } else { target = anchored.layoutNodeIndex }
            }
            // A loop on a state or a composite hangs beside it and is not laid out.
            guard source != target else { continue }
            let labelSize = measured.transitionTexts[transitionIndex].map { text in
                CGSize(width: text.size.width + room.width, height: text.size.height + room.height)
            }
            edges.append(LayeredCompoundSpanEdge(source: source, target: target, minimumRankSpan: 1, labelSize: labelSize))
            transitionIndices.append(transitionIndex)
        }
        return transitionIndices
    }
}
