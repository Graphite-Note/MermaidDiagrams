/**
 * File: StateDiagramCompositeSurroundings.swift
 * ---------------------------------------------
 * Layer: Core
 * Description: The notes beside a composite state and the room for its loops, laid out in an unseen box around it, as
 *              Pele's state renderer lays them out.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// A composite state with notes or transitions to itself sits in an unseen box of its own, as in Pele's state renderer
/// (`state/render.ts`, "a state with notes, or a composite with self-transitions"): the box runs across the flow around
/// it, so that its notes are laid out beside the composite, each tied to it by an edge from the left note to it or from
/// it to the right note, and it has room on both sides across the flow for the loops, which hang off the composite's
/// own box.
struct StateDiagramCompositeSurroundings {
    /// For each composite with notes or loops, the unseen box around it (its index in the cluster graph's clusters).
    private(set) var wrapperClusters: [Int: Int] = [:]
    /// The unseen boxes, to append to the graph's clusters.
    private(set) var clusters: [LayeredCluster] = []
    /// For each note on a composite, its node among those appended to the graph's nodes, numbered from `firstNode`.
    private(set) var noteNodes: [Int: Int] = [:]
    /// The notes' sizes and boxes, to append to the graph's nodes.
    private(set) var nodeSizes: [CGSize] = []
    private(set) var nodeClusters: [Int?] = []
    /// The edges tying each note to its composite, to append to the graph's edges.
    private(set) var edges: [LayeredClusterEdge] = []
    /// For each composite, whether the box around it runs down or up: its loops then hang off its right, else its bottom.
    let containerRunsVertically: [Bool]

    /// - Parameters:
    ///   - containers: For each composite, the box it sits directly in, or nil at the top level.
    ///   - containerRunsVertically: For each composite, whether the box around it runs down or up.
    init(diagram: StateDiagram, measured: StateDiagramMeasurement, compositeOfState: [Int?], containers: [Int?], containerRunsVertically: [Bool],
         firstCluster: Int, firstNode: Int) {
        self.containerRunsVertically = containerRunsVertically
        var notesByComposite: [Int: [Int]] = [:]
        for (noteIndex, note) in diagram.notes.enumerated() {
            if let composite = compositeOfState[note.stateIndex] { notesByComposite[composite, default: []].append(noteIndex) }
        }
        for compositeIndex in diagram.composites.indices {
            let state = diagram.composites[compositeIndex].stateIndex
            let loops = measured.selfLoopTransitionIndices[state]
            let notes = notesByComposite[compositeIndex] ?? []
            guard !loops.isEmpty || !notes.isEmpty else { continue }
            let runsVertically = containerRunsVertically[compositeIndex]
            let room = StateDiagramSelfLoops.extent(textSizes: loops.map { index in measured.transitionTexts[index]?.size }, flowIsVertical: runsVertically).room
            let padding = runsVertically ? LayeredClusterPadding(side: room, top: 0, bottom: 0) : LayeredClusterPadding(side: 0, top: room, bottom: room)
            let wrapper = firstCluster + clusters.count
            wrapperClusters[compositeIndex] = wrapper
            clusters.append(LayeredCluster(parent: containers[compositeIndex], direction: runsVertically ? .leftToRight : .topToBottom, padding: padding,
                                           minimumWidth: 0))
            for noteIndex in notes {
                let node = firstNode + nodeSizes.count
                noteNodes[noteIndex] = node
                nodeSizes.append(measured.noteSizes[noteIndex])
                nodeClusters.append(wrapper)
                let isLeft = diagram.notes[noteIndex].side == .left
                edges.append(LayeredClusterEdge(source: isLeft ? .node(node) : .cluster(compositeIndex), target: isLeft ? .cluster(compositeIndex) : .node(node),
                                                minimumRankSpan: 1, labelSize: nil))
            }
        }
    }
}
