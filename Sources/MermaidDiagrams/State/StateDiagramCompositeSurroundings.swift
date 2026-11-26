/**
 * File: StateDiagramCompositeSurroundings.swift
 * ---------------------------------------------
 * Layer: Core
 * Description: The notes beside a composite state and the room for its loops, laid out in an unseen box around it, as
 *              Pele's state renderer lays them out.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 26/11/2026
 */

import CoreGraphics

/// A composite state with notes or transitions to itself sits in an unseen box of its own, as in Pele's state renderer
/// (`state/render.ts`, "a state with notes, or a composite with self-transitions"): the box runs across the flow around
/// it, so that its notes are laid out beside the composite, each tied to it by an edge from the left note to it or from
/// it to the right note, and it has room on both sides across the flow for the loops, which hang off the composite's
/// own box.
struct StateDiagramCompositeSurroundings {
    /// Each composite with notes or loops and the unseen box around it (its index among the cluster graph's boxes), in the
    /// composites' order.
    private(set) var wrapperClusters: [(composite: Int, wrapper: Int)] = []
    /// The unseen boxes as the compound layout's group nodes, to append to the graph's boxes.
    private(set) var clusters: [LayeredCompoundNode] = []
    /// Each note on a composite and its node among those appended to the graph's nodes, numbered from `firstNode`.
    private(set) var noteNodes: [(note: Int, node: Int)] = []
    /// The notes' sizes and boxes, to append to the graph's nodes.
    private(set) var nodeSizes: [CGSize] = []
    private(set) var nodeClusters: [Int?] = []
    /// The edges tying each note to its composite's box, to append to the graph's edges.
    private(set) var edges: [LayeredCompoundSpanEdge] = []
    /// For each composite, whether the box around it runs down or up: its loops then hang off its right, else its bottom.
    let containerRunsVertically: [Bool]

    /// How many notes the surroundings lay out as nodes: every note on a composite, as each sits beside its composite.
    static func noteNodeCount(of diagram: StateDiagram, compositeOfState: [Int?]) -> Int {
        var count = 0
        for note in diagram.notes where compositeOfState[note.stateIndex] != nil { count += 1 }
        return count
    }

    /// - Parameters:
    ///   - containers: For each composite, the box it sits directly in, or nil at the top level.
    ///   - containerRunsVertically: For each composite, whether the box around it runs down or up.
    ///   - nodeCount: How many nodes the graph has, these notes' included: its boxes' group nodes follow them.
    init(diagram: StateDiagram, measured: StateDiagramMeasurement, compositeOfState: [Int?], containers: [Int?], containerRunsVertically: [Bool],
         firstCluster: Int, firstNode: Int, nodeCount: Int) {
        self.containerRunsVertically = containerRunsVertically
        let notesByComposite = Self.notesByComposite(diagram, compositeOfState: compositeOfState)
        for compositeIndex in diagram.composites.indices {
            let state = diagram.composites[compositeIndex].stateIndex
            let loops = measured.selfLoopTransitionIndices[state]
            let notes = notesByComposite.notes[notesByComposite.starts[compositeIndex]..<notesByComposite.starts[compositeIndex + 1]]
            guard !loops.isEmpty || !notes.isEmpty else { continue }
            let runsVertically = containerRunsVertically[compositeIndex]
            let room = StateDiagramSelfLoops.extent(textSizes: loops.map { index in measured.transitionTexts[index]?.size }, flowIsVertical: runsVertically).room
            let padding = runsVertically ? LayeredClusterPadding(side: room, top: 0, bottom: 0) : LayeredClusterPadding(side: 0, top: room, bottom: room)
            let wrapper = firstCluster + clusters.count
            wrapperClusters.append((compositeIndex, wrapper))
            clusters.append(.box(parent: containers[compositeIndex], nodeCount: nodeCount, direction: runsVertically ? .leftToRight : .topToBottom,
                                 padding: padding, minimumWidth: 0, sequence: CGFloat(nodeCount + wrapper)))
            for noteIndex in notes {
                let node = firstNode + nodeSizes.count
                noteNodes.append((noteIndex, node))
                nodeSizes.append(measured.noteSizes[noteIndex])
                nodeClusters.append(wrapper)
                let isLeft = diagram.notes[noteIndex].side == .left
                let compositeNode = nodeCount + compositeIndex
                edges.append(LayeredCompoundSpanEdge(source: isLeft ? node : compositeNode, target: isLeft ? compositeNode : node, minimumRankSpan: 1,
                                                     labelSize: nil))
            }
        }
    }

    /// The notes on composites grouped by composite, each composite's in their written order: composite `c`'s are
    /// `notes[starts[c]..<starts[c + 1]]`.
    private static func notesByComposite(_ diagram: StateDiagram, compositeOfState: [Int?]) -> (notes: [Int], starts: [Int]) {
        var starts = [Int](repeating: 0, count: diagram.composites.count + 1)
        for note in diagram.notes {
            if let composite = compositeOfState[note.stateIndex] { starts[composite + 1] += 1 }
        }
        for composite in diagram.composites.indices { starts[composite + 1] += starts[composite] }
        var filled = starts
        var notes = [Int](repeating: 0, count: starts[diagram.composites.count])
        for (noteIndex, note) in diagram.notes.enumerated() {
            guard let composite = compositeOfState[note.stateIndex] else { continue }
            notes[filled[composite]] = noteIndex
            filled[composite] += 1
        }
        return (notes, starts)
    }
}
