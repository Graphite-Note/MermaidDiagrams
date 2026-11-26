/**
 * File: StateDiagramClusterParts.swift
 * ------------------------------------
 * Layer: Core
 * Description: The parts of a state diagram's graph of nested boxes, each written into the calling thread's scratch
 *              arena: the composites' titles and depths, the regions' boxes, the nodes of the states and anchors, the
 *              boxes, the transitions laid out and how far each node's ends spread.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics

/// The parts `StateDiagramClusterGraph` is made of, Pele's state renderer's (`state/render.ts`).
enum StateDiagramClusterParts {
    /// Each composite's name in the box's band, measured unwrapped in the names' font; nil for an empty one.
    static func titles<Measurer: DiagramTextMeasuring>(of diagram: StateDiagram, titleText: Measurer) -> [DiagramTextBlock?] {
        diagram.composites.map { composite in
            let title = DiagramTextBlock(label: diagram.model.nameLabel(of: composite.stateIndex), measurer: titleText, maximumWidth: .greatestFiniteMagnitude)
            return title.lineCount == 0 ? nil : title
        }
    }

    /// How many composites each composite is inside; a composite inside itself is refused.
    static func depths(of diagram: StateDiagram, arena: DiagramScratchArena) throws(StateDiagramLayoutError) -> ScratchSpan<Int32> {
        let states = diagram.model.states
        let depths: ScratchSpan<Int32> = arena.uninitializedSpan(count: diagram.composites.count)
        for (index, composite) in diagram.composites.enumerated() {
            var depth = 0
            var parent = states[composite.stateIndex].compositeIndex
            while let parentIndex = parent {
                depth += 1
                guard depth <= diagram.composites.count else { throw .compositeStatesNotLaidOut }
                parent = states[diagram.composites[parentIndex].stateIndex].compositeIndex
            }
            depths[index] = Int32(depth)
        }
        return depths
    }

    /// How far each node's transitions spread along its sides, by the flow of the box it sits in.
    static func sideSpans(of diagram: StateDiagram, measured: StateDiagramMeasurement, layoutNodeIndices: ScratchSpan<Int32>,
                          directions: [FlowchartDirection], nodeCount: Int, arena: DiagramScratchArena) -> ScratchSpan<CGFloat> {
        let spans = arena.span(count: nodeCount, repeating: CGFloat(0))
        for state in 0..<layoutNodeIndices.count {
            let node = layoutNodeIndices[state]
            guard node >= 0 else { continue }
            let direction = diagram.model.states[state].compositeIndex.map { composite in directions[composite] } ?? diagram.direction
            spans[Int(node)] = measured.sideSpan(of: state, in: diagram, flowIsVertical: !direction.runsAcross)
        }
        return spans
    }

    /// The composites' boxes, in their order, then each composite's regions' boxes, in theirs.
    static func boxes(of diagram: StateDiagram, titles: [DiagramTextBlock?], containers: ScratchSpan<Int32>, regions: StateDiagramRegionClusters,
                      nodeCount: Int, arena: DiagramScratchArena) -> ScratchList<LayeredCompoundNode> {
        var boxes = arena.list(capacity: 2 * diagram.composites.count + regions.boxCount, of: LayeredCompoundNode.self)
        for compositeIndex in diagram.composites.indices {
            let container = containers[compositeIndex]
            boxes.append(compositeBox(direction: diagram.composites[compositeIndex].direction, title: titles[compositeIndex],
                                      container: container < 0 ? nil : Int(container), nodeCount: nodeCount, sequence: nodeCount + compositeIndex))
        }
        let padding = LayeredClusterPadding(side: StateDiagramClusterGraph.regionPadding, top: StateDiagramClusterGraph.regionPadding,
                                            bottom: StateDiagramClusterGraph.regionPadding)
        for compositeIndex in 0..<regions.boxesByComposite.count {
            for _ in regions.boxesByComposite[compositeIndex].indices {
                boxes.append(.box(parent: compositeIndex, nodeCount: nodeCount, direction: nil, padding: padding, minimumWidth: 0,
                                  sequence: CGFloat(nodeCount + boxes.count)))
            }
        }
        return boxes
    }

    /// A composite's box: Pele's room around its states, its title's band on top, at least as wide as its title.
    private static func compositeBox(direction: FlowchartDirection?, title: DiagramTextBlock?, container: Int?, nodeCount: Int,
                                     sequence: Int) -> LayeredCompoundNode {
        let padding = StateDiagramClusterGraph.compositePadding
        let titleSize = title?.size ?? .zero
        let top = (title == nil ? 0 : titleSize.height + StateDiagramClusterGraph.titleRoom) + padding
        return .box(parent: container, nodeCount: nodeCount, direction: direction?.layeredDirection,
                    padding: LayeredClusterPadding(side: padding, top: top, bottom: padding), minimumWidth: titleSize.width + 2 * padding,
                    sequence: CGFloat(sequence))
    }

    /// The unseen boxes around the composites with notes or loops, appended to `boxes`, each composite then sitting in its
    /// own box, which runs in its own direction.
    static func wrapComposites(of diagram: StateDiagram, measured: StateDiagramMeasurement, compositeIndices: ScratchSpan<Int32>,
                               containers: ScratchSpan<Int32>, directions: [FlowchartDirection], boxes: inout ScratchList<LayeredCompoundNode>,
                               firstNode: Int, nodeCount: Int, arena: DiagramScratchArena) -> StateDiagramCompositeSurroundings {
        let containerRunsVertically: ScratchSpan<Bool> = arena.uninitializedSpan(count: diagram.composites.count)
        for (index, composite) in diagram.composites.enumerated() {
            containerRunsVertically[index] = !(diagram.model.states[composite.stateIndex].compositeIndex.map { directions[$0] } ?? diagram.direction).runsAcross
        }
        let surroundings = StateDiagramCompositeSurroundings(diagram: diagram, measured: measured, compositeIndices: compositeIndices,
                                                             containers: containers, containerRunsVertically: containerRunsVertically,
                                                             firstCluster: boxes.count, firstNode: firstNode, nodeCount: nodeCount, arena: arena)
        for pair in 0..<surroundings.wrapperClusters.count {
            let (compositeIndex, wrapper) = (Int(surroundings.wrapperClusters[pair].composite), Int(surroundings.wrapperClusters[pair].wrapper))
            boxes[compositeIndex].parent = nodeCount + wrapper
            boxes[compositeIndex].direction = directions[compositeIndex].layeredDirection
        }
        boxes.append(contentsOf: surroundings.clusters.elements)
        return surroundings
    }

    /// Each transition between two different nodes or boxes as an edge, written into `edges`; the transitions laid out,
    /// in the edges' order.
    static func edges(of diagram: StateDiagram, measured: StateDiagramMeasurement, layoutNodeIndices: ScratchSpan<Int32>,
                      compositeIndices: ScratchSpan<Int32>, anchors: ScratchSpan<StateDiagramClusterGraph.PlacedAnchor>, nodeCount: Int,
                      into edges: inout ScratchList<LayeredCompoundSpanEdge>, arena: DiagramScratchArena) -> ScratchSpan<Int32> {
        func end(of state: Int) -> Int {
            let composite = compositeIndices[state]
            if composite >= 0 { return nodeCount + Int(composite) }
            return max(Int(layoutNodeIndices[state]), 0)
        }
        let room = StateDiagramLayoutEngine.transitionTextRoom
        var transitionIndices = arena.list(capacity: diagram.model.transitions.count, of: Int32.self)
        for (transitionIndex, transition) in diagram.model.transitions.enumerated() {
            var source = end(of: transition.sourceIndex)
            var target = end(of: transition.targetIndex)
            if transitionIndex < anchors.count, anchors[transitionIndex].layoutNodeIndex >= 0 {
                let anchored = anchors[transitionIndex]
                if anchored.anchor.isInward { source = anchored.layoutNodeIndex } else { target = anchored.layoutNodeIndex }
            }
            // A loop on a state or a composite hangs beside it and is not laid out.
            guard source != target else { continue }
            let labelSize = measured.transitionTexts[transitionIndex].map { text in
                CGSize(width: text.size.width + room.width, height: text.size.height + room.height)
            }
            edges.append(LayeredCompoundSpanEdge(source: source, target: target, minimumRankSpan: 1, labelSize: labelSize))
            transitionIndices.append(Int32(transitionIndex))
        }
        return transitionIndices.elements
    }
}
