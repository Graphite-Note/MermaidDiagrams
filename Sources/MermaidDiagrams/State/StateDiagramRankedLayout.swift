/**
 * File: StateDiagramRankedLayout.swift
 * ------------------------------------
 * Layer: Core
 * Description: A state diagram without composite states laid out in ranks in the scratch arena: its states and
 *              transitions written straight into the flat layout's spans, and the placed spans read on the page.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 26/11/2026
 */

import CoreGraphics

/// A state diagram without composite states, as Pele lays out a diagram with no groups: its states in the layout's order
/// (`StateDiagramFlowOrder`) and the transitions between two different states as one flat layered graph
/// (`LayeredFlatLayout`), each state's place sized with its loops and notes; then each state at its center on the page,
/// each transition along its route from one state's side to the other's (`StateDiagramPageAssembly`). The working lists
/// are spans of the calling thread's arena; only the layout returned is allocated.
enum StateDiagramRankedLayout {
    /// The layout, or nil when the flat graph would need more than `maximumPointCount` nodes and passing points.
    static func layout(_ diagram: StateDiagram, measured: StateDiagramMeasurement, surroundings: StateDiagramSurroundings, title: DiagramMeasuredText?,
                       font: DiagramFont, maximumPointCount: Int, arena: DiagramScratchArena) -> StateDiagramLayout? {
        let flowAxes = FlowchartFlowAxes(direction: diagram.direction, alongExtent: 0)
        let graph = RankedGraph(diagram, measured: measured, surroundings: surroundings, axes: flowAxes, arena: arena)
        #if DEBUG
        LayeredLayoutRecording.recordPlacement(nodes: graph.nodes, edges: graph.edges, spacing: StateDiagramLayoutEngine.spacing,
                                               maximumPointCount: maximumPointCount)
        #endif
        var points = arena.list(capacity: 4 * graph.edges.count, of: CGPoint.self)
        guard let size = LayeredFlatLayout.layout(nodes: graph.nodes, edges: graph.edges, points: &points,
                                                  options: LayeredFlatOptions(StateDiagramLayoutEngine.spacing), maximumVertexCount: maximumPointCount,
                                                  arena: arena) else {
            return nil
        }
        let axes = FlowchartFlowAxes(direction: diagram.direction, alongExtent: CGFloat(size.height))
        var page = StateDiagramPageAssembly(diagram: diagram, measured: measured, surroundings: surroundings, axes: axes)
        page.placeStates(nodes: graph.nodes, positionOfState: graph.positionOfState)
        page.placeTransitions(layeredTransitionIndices: graph.layeredTransitionIndices, edges: graph.edges, points: points.elements)
        page.placeSelfLoops()
        return page.finished(font: font, title: title, padding: StateDiagramLayoutEngine.padding, titleGap: StateDiagramLayoutEngine.titleGap)
    }

    /// The states and the transitions between two different states as the flat layout's graph, in flow space.
    private struct RankedGraph {
        /// Each state's place in the layout's order.
        let positionOfState: ScratchSpan<Int>
        /// Every transition but those from a state to itself, which loop beside it, by its index in the diagram.
        let layeredTransitionIndices: ScratchSpan<Int>
        let nodes: ScratchSpan<LayeredFlatNode>
        let edges: ScratchSpan<LayeredSpanEdge>

        init(_ diagram: StateDiagram, measured: StateDiagramMeasurement, surroundings: StateDiagramSurroundings, axes: FlowchartFlowAxes,
             arena: DiagramScratchArena) {
            let stateCount = diagram.stateCount
            let order = StateDiagramFlowOrder.order(of: diagram, arena: arena)
            positionOfState = arena.uninitializedSpan(count: stateCount)
            nodes = arena.uninitializedSpan(count: stateCount)
            for position in 0..<stateCount {
                let state = order[position]
                positionOfState[state] = position
                let place = surroundings.placeSizes[state]
                var node = LayeredFlatNode(width: Double(place.across), height: Double(place.along))
                node.sideSpan = Double(measured.sideSpan(of: state, in: diagram, flowIsVertical: axes.flowIsVertical))
                nodes[position] = node
            }
            var layered = arena.list(capacity: diagram.transitionCount, of: Int.self)
            for (transitionIndex, transition) in diagram.model.transitions.enumerated() where transition.source != transition.target {
                layered.append(transitionIndex)
            }
            layeredTransitionIndices = layered.elements
            edges = arena.uninitializedSpan(count: layered.count)
            for layeredIndex in 0..<layered.count {
                let transitionIndex = layered[layeredIndex]
                let transition = diagram.model.transitions[transitionIndex]
                let labelSize = Self.labelFlowSize(of: transitionIndex, measured: measured, axes: axes)
                edges[layeredIndex] = LayeredSpanEdge(tail: positionOfState[transition.sourceIndex], head: positionOfState[transition.targetIndex],
                                                      minimumLength: 1, labelWidth: Double(labelSize?.across ?? 0),
                                                      labelHeight: Double(labelSize?.along ?? 0), tailOffset: 0, headOffset: 0)
            }
        }

        /// The flow-space size of a transition's text's place, or nil for a transition without text.
        static func labelFlowSize(of transitionIndex: Int, measured: StateDiagramMeasurement, axes: FlowchartFlowAxes) -> LayeredSize? {
            measured.transitionTexts[transitionIndex].map { text in
                let room = StateDiagramLayoutEngine.transitionTextRoom
                return axes.flowSize(of: CGSize(width: text.size.width + room.width, height: text.size.height + room.height))
            }
        }
    }
}

/// The order the layout takes a diagram's states in, Pele's: starts first, then the others in the order transitions
/// first name them, then those no transition names, each group in the diagram's order. A state declared before the
/// transitions does not become the top of the flow.
enum StateDiagramFlowOrder {
    /// The states in that order, in `arena`.
    static func order(of diagram: StateDiagram, arena: DiagramScratchArena) -> ScratchSpan<Int> {
        let stateCount = diagram.stateCount
        let firstAppearance = arena.span(count: stateCount, repeating: Int.max)
        var appearanceCount = 0
        for transition in diagram.model.transitions {
            if firstAppearance[transition.sourceIndex] == .max {
                firstAppearance[transition.sourceIndex] = appearanceCount
                appearanceCount += 1
            }
            if firstAppearance[transition.targetIndex] == .max {
                firstAppearance[transition.targetIndex] = appearanceCount
                appearanceCount += 1
            }
        }
        // Each state's key: starts before the others, then by first appearance, then by index; no two keys are equal, so
        // any sort gives the order a sort by (start, appearance, index) gives.
        let keys: ScratchSpan<StateKey> = arena.uninitializedSpan(count: stateCount)
        for state in 0..<stateCount {
            keys[state] = StateKey(isNotStart: diagram.model.states[state].kind.isStart ? 0 : 1, firstAppearance: firstAppearance[state], state: state)
        }
        var sorted = keys.buffer
        sorted.sort { first, second in
            (first.isNotStart, first.firstAppearance, first.state) < (second.isNotStart, second.firstAppearance, second.state)
        }
        let order: ScratchSpan<Int> = arena.uninitializedSpan(count: stateCount)
        for position in 0..<stateCount { order[position] = keys[position].state }
        return order
    }

    private struct StateKey {
        let isNotStart: Int
        let firstAppearance: Int
        let state: Int
    }
}
