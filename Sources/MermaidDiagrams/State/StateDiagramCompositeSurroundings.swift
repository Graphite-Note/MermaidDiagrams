/**
 * File: StateDiagramCompositeSurroundings.swift
 * ---------------------------------------------
 * Layer: Core
 * Description: The notes beside a composite state and the room for its loops, laid out in an unseen box around it, as
 *              Pele's state renderer lays them out.
 *
 * Authors: Bahey Shalash
 * Version: 0.5
 * Date: 26/11/2026
 */

import CoreGraphics

/// A composite state with notes or transitions to itself sits in an unseen box of its own, as in Pele's state renderer
/// (`state/render.ts`, "a state with notes, or a composite with self-transitions"): the box runs across the flow around
/// it, so that its notes are laid out beside the composite, each tied to it by an edge from the left note to it or from
/// it to the right note, and it has room on both sides across the flow for the loops, which hang off the composite's
/// own box.
struct StateDiagramCompositeSurroundings {
    /// A composite with notes or loops and the unseen box around it (its index among the cluster graph's boxes).
    struct Wrapper {
        let composite: Int32
        let wrapper: Int32
    }

    /// A note on a composite and its node among those appended to the graph's nodes.
    struct NoteNode {
        let note: Int32
        let node: Int32
    }

    /// Each composite with notes or loops and the unseen box around it, in the composites' order.
    private(set) var wrapperClusters: ScratchList<Wrapper>
    /// The unseen boxes as the compound layout's group nodes, to append to the graph's boxes.
    private(set) var clusters: ScratchList<LayeredCompoundNode>
    /// Each note on a composite and its node, numbered from `firstNode`.
    private(set) var noteNodes: ScratchList<NoteNode>
    /// The notes' sizes and boxes, to append to the graph's nodes.
    private(set) var nodeSizes: ScratchList<CGSize>
    private(set) var nodeClusters: ScratchList<Int32>
    /// The edges tying each note to its composite's box, to append to the graph's edges.
    private(set) var edges: ScratchList<LayeredCompoundSpanEdge>
    /// For each composite, whether the box around it runs down or up: its loops then hang off its right, else its bottom.
    let containerRunsVertically: ScratchSpan<Bool>

    /// How many notes the surroundings lay out as nodes: every note on a composite, as each sits beside its composite.
    static func noteNodeCount(of diagram: StateDiagram, compositeIndices: ScratchSpan<Int32>) -> Int {
        var count = 0
        for note in diagram.model.notes where compositeIndices[note.stateIndex] >= 0 { count += 1 }
        return count
    }

    /// - Parameters:
    ///   - containers: The box each composite sits in, -1 for the top level.
    ///   - firstCluster: The index among the graph's boxes of the first unseen box.
    ///   - firstNode: The node of the first note on a composite; `nodeCount` is how many nodes the graph has.
    init(diagram: StateDiagram, measured: StateDiagramMeasurement, compositeIndices: ScratchSpan<Int32>, containers: ScratchSpan<Int32>,
         containerRunsVertically: ScratchSpan<Bool>, firstCluster: Int, firstNode: Int, nodeCount: Int, arena: DiagramScratchArena) {
        self.containerRunsVertically = containerRunsVertically
        let compositeCount = diagram.composites.count
        wrapperClusters = arena.list(capacity: compositeCount, of: Wrapper.self)
        clusters = arena.list(capacity: compositeCount, of: LayeredCompoundNode.self)
        let notes = Self.notesByComposite(diagram, compositeIndices: compositeIndices, arena: arena)
        let noteCount = notes.starts[compositeCount]
        noteNodes = arena.list(capacity: noteCount, of: NoteNode.self)
        nodeSizes = arena.list(capacity: noteCount, of: CGSize.self)
        nodeClusters = arena.list(capacity: noteCount, of: Int32.self)
        edges = arena.list(capacity: noteCount, of: LayeredCompoundSpanEdge.self)
        for compositeIndex in 0..<compositeCount {
            let state = diagram.composites[compositeIndex].stateIndex
            let loops = measured.selfLoopTransitionIndices[state]
            let compositeNotes = notes.notes.part(notes.starts[compositeIndex]..<notes.starts[compositeIndex + 1])
            guard !loops.isEmpty || !compositeNotes.isEmpty else { continue }
            let runsVertically = containerRunsVertically[compositeIndex]
            let room = StateDiagramSelfLoops.extent(textSizes: loops.map { index in measured.transitionTexts[index]?.size }, flowIsVertical: runsVertically).room
            let padding = runsVertically ? LayeredClusterPadding(side: room, top: 0, bottom: 0) : LayeredClusterPadding(side: 0, top: room, bottom: room)
            let wrapper = firstCluster + clusters.count
            wrapperClusters.append(Wrapper(composite: Int32(compositeIndex), wrapper: Int32(wrapper)))
            let container = containers[compositeIndex]
            clusters.append(.box(parent: container < 0 ? nil : Int(container), nodeCount: nodeCount, direction: runsVertically ? .leftToRight : .topToBottom,
                                 padding: padding, minimumWidth: 0, sequence: CGFloat(nodeCount + wrapper)))
            for noteIndex in compositeNotes {
                let node = firstNode + nodeSizes.count
                noteNodes.append(NoteNode(note: Int32(noteIndex), node: Int32(node)))
                nodeSizes.append(measured.noteSizes[noteIndex])
                nodeClusters.append(Int32(wrapper))
                let isLeft = diagram.model.notes[noteIndex].side == .left
                let compositeNode = nodeCount + compositeIndex
                edges.append(LayeredCompoundSpanEdge(source: isLeft ? node : compositeNode, target: isLeft ? compositeNode : node, minimumRankSpan: 1,
                                                     labelSize: nil))
            }
        }
    }

    /// The notes on composites grouped by composite, each group in the notes' order: the indices of composite `c`'s notes
    /// are `notes[starts[c]..<starts[c + 1]]`.
    private static func notesByComposite(_ diagram: StateDiagram, compositeIndices: ScratchSpan<Int32>,
                                         arena: DiagramScratchArena) -> (notes: ScratchSpan<Int>, starts: ScratchSpan<Int>) {
        let compositeCount = diagram.composites.count
        let starts = arena.span(count: compositeCount + 1, repeating: 0)
        for note in diagram.model.notes where compositeIndices[note.stateIndex] >= 0 { starts[Int(compositeIndices[note.stateIndex]) + 1] += 1 }
        for composite in 0..<compositeCount { starts[composite + 1] += starts[composite] }
        let filled: ScratchSpan<Int> = arena.uninitializedSpan(count: compositeCount + 1)
        filled.copyElements(from: starts)
        let notes: ScratchSpan<Int> = arena.uninitializedSpan(count: starts[compositeCount])
        for (noteIndex, note) in diagram.model.notes.enumerated() {
            let composite = compositeIndices[note.stateIndex]
            guard composite >= 0 else { continue }
            notes[filled[Int(composite)]] = noteIndex
            filled[Int(composite)] += 1
        }
        return (notes, starts)
    }
}
