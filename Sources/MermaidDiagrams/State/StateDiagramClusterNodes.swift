/**
 * File: StateDiagramClusterNodes.swift
 * ------------------------------------
 * Layer: Core
 * Description: The concurrent regions of a state diagram's composites that get boxes of their own, and the nodes of
 *              its states and anchors in its graph of nested boxes, each list a span of the calling thread's arena.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics

/// The regions states are named in, each once, sorted by composite then region; a composite whose states sit in
/// several regions has a box for each, numbered from `firstClusterIndex` in that order.
struct StateDiagramRegionClusters {
    /// By composite, its regions' boxes, a run of consecutive boxes (empty for a composite with one region).
    let boxesByComposite: ScratchSpan<StateDiagramRegionBoxes>
    private let regions: ScratchSpan<RegionKey>
    /// The box of each region in `regions`, -1 for a region of a composite that has one.
    private let clusterOfRegion: ScratchSpan<Int32>
    /// How many regions have boxes.
    let boxCount: Int

    private struct RegionKey: Comparable {
        let compositeIndex: Int
        let regionIndex: Int

        static func < (first: RegionKey, second: RegionKey) -> Bool {
            (first.compositeIndex, first.regionIndex) < (second.compositeIndex, second.regionIndex)
        }
    }

    init(of diagram: StateDiagram, startingAt firstClusterIndex: Int, arena: DiagramScratchArena) {
        var named = arena.list(capacity: diagram.stateCount, of: RegionKey.self)
        for state in diagram.model.states {
            guard let compositeIndex = state.compositeIndex, compositeIndex < diagram.composites.count else { continue }
            named.append(RegionKey(compositeIndex: compositeIndex, regionIndex: state.regionIndex))
        }
        var sorted = named.elements.buffer
        sorted.sort { first, second in first < second }
        var uniqueCount = 0
        for index in 0..<sorted.count where uniqueCount == 0 || sorted[uniqueCount - 1] != sorted[index] {
            sorted[uniqueCount] = sorted[index]
            uniqueCount += 1
        }
        regions = named.elements.part(0..<uniqueCount)
        let clusterOfRegion = arena.span(count: uniqueCount, repeating: Int32(-1))
        let boxesByComposite = arena.span(count: diagram.composites.count, repeating: StateDiagramRegionBoxes(first: 0, count: 0))
        var nextClusterIndex = firstClusterIndex
        var first = 0
        while first < uniqueCount {
            var end = first + 1
            while end < uniqueCount, regions[end].compositeIndex == regions[first].compositeIndex { end += 1 }
            if end - first > 1 {
                boxesByComposite[regions[first].compositeIndex] = StateDiagramRegionBoxes(first: Int32(nextClusterIndex), count: Int32(end - first))
                for region in first..<end {
                    clusterOfRegion[region] = Int32(nextClusterIndex)
                    nextClusterIndex += 1
                }
            }
            first = end
        }
        self.clusterOfRegion = clusterOfRegion
        self.boxesByComposite = boxesByComposite
        boxCount = nextClusterIndex - firstClusterIndex
    }

    /// The box `state` sits in: its region's, its composite's when that has one region, or nil at the top level.
    func container(of state: Int, in model: StateDiagramModel) -> Int? {
        guard let compositeIndex = model.states[state].compositeIndex else { return nil }
        let key = RegionKey(compositeIndex: compositeIndex, regionIndex: model.states[state].regionIndex)
        var low = 0
        var high = regions.count
        while low < high {
            let middle = (low + high) / 2
            if regions[middle] < key { low = middle + 1 } else { high = middle }
        }
        guard low < regions.count, regions[low] == key else { return compositeIndex }
        let cluster = clusterOfRegion[low]
        return cluster < 0 ? compositeIndex : Int(cluster)
    }
}

/// The nodes of the states that are not composites, in the layout's order, with the anchors of transitions into
/// composites before the first state that is not a start and those out of composites after the last.
struct StateDiagramClusterNodes {
    /// For each state, its node, or -1 for a composite state.
    let layoutNodeIndices: ScratchSpan<Int32>
    /// Each node's size on the page and the box it sits in (-1 for none); the notes' nodes are appended later.
    var sizes: ScratchList<CGSize>
    var clusters: ScratchList<Int32>
    /// By transition index, its anchor and its point's node (-1 for none), or empty when no transition has one.
    let anchors: ScratchSpan<StateDiagramClusterGraph.PlacedAnchor>

    init(diagram: StateDiagram, compositeIndices: ScratchSpan<Int32>, surroundings: StateDiagramSurroundings, flowIsVertical: Bool,
         regions: StateDiagramRegionClusters, anchors anchorList: ScratchSpan<StateDiagramCompositeAnchor>, arena: DiagramScratchArena) {
        let model = diagram.model
        let layoutNodeIndices = arena.span(count: model.states.count, repeating: Int32(-1))
        let capacity = model.states.count + anchorList.count + model.notes.count
        var sizes = arena.list(capacity: capacity, of: CGSize.self)
        var clusters = arena.list(capacity: capacity, of: Int32.self)
        let none = StateDiagramClusterGraph.PlacedAnchor(anchor: StateDiagramCompositeAnchor(transitionIndex: 0, compositeIndex: 0, isInward: false),
                                                         layoutNodeIndex: -1)
        let anchors = arena.span(count: anchorList.isEmpty ? 0 : model.transitions.count, repeating: none)
        func place(inward: Bool) {
            for anchor in anchorList where anchor.isInward == inward {
                anchors[anchor.transitionIndex] = StateDiagramClusterGraph.PlacedAnchor(anchor: anchor, layoutNodeIndex: sizes.count)
                sizes.append(.zero)
                clusters.append(Int32(anchor.compositeIndex))
            }
        }
        var inwardPlaced = false
        let order = StateDiagramFlowOrder.order(of: diagram, arena: arena)
        for position in 0..<order.count where compositeIndices[order[position]] < 0 {
            let state = order[position]
            if !inwardPlaced, !model.states[state].kind.isStart {
                place(inward: true)
                inwardPlaced = true
            }
            layoutNodeIndices[state] = Int32(sizes.count)
            let place = surroundings.placeSizes[state]
            sizes.append(flowIsVertical ? CGSize(width: place.across, height: place.along) : CGSize(width: place.along, height: place.across))
            clusters.append(Int32(regions.container(of: state, in: model) ?? -1))
        }
        if !inwardPlaced { place(inward: true) }
        place(inward: false)
        self.layoutNodeIndices = layoutNodeIndices
        self.sizes = sizes
        self.clusters = clusters
        self.anchors = anchors
    }
}
