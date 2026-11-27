/**
 * File: StateDiagramCompositeAnchors.swift
 * ----------------------------------------
 * Layer: Core
 * Description: Transitions between a composite state and a state inside it, run from a point just inside the composite,
 *              as Pele's state renderer runs them.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 26/11/2026
 */

/// A transition between a composite state and a state inside it (`Moving --> slow` with `slow` in `Moving`), as Pele's
/// state renderer lays it out (`state/render.ts`, its `anchor`): the composite's end is a point of no size inside the
/// composite's box, first in the box's order when the transition leaves the composite and last when it arrives, the
/// transition is laid out between that point and the inner state, and it is then drawn on to the composite's border:
/// below its title, on the side its flow starts from, when it leaves the composite; on the side its flow ends at when it
/// arrives.
struct StateDiagramCompositeAnchor: Equatable {
    let transitionIndex: Int
    /// The composite (its index in `StateDiagram.composites`) whose box holds the point.
    let compositeIndex: Int
    /// Whether the transition leaves the composite for the state inside, rather than arrives from it.
    let isInward: Bool
}

enum StateDiagramCompositeAnchors {
    /// The anchors of a diagram's transitions, in their order, in `arena`.
    static func anchors(of diagram: StateDiagram, compositeIndices: ScratchSpan<Int32>, arena: DiagramScratchArena) -> ScratchSpan<StateDiagramCompositeAnchor> {
        var anchors = arena.list(capacity: diagram.model.transitions.count, of: StateDiagramCompositeAnchor.self)
        for (transitionIndex, transition) in diagram.model.transitions.enumerated() {
            let source = compositeIndices[transition.sourceIndex]
            if source >= 0, encloses(Int(source), transition.targetIndex, in: diagram) {
                anchors.append(StateDiagramCompositeAnchor(transitionIndex: transitionIndex, compositeIndex: Int(source), isInward: true))
                continue
            }
            let target = compositeIndices[transition.targetIndex]
            if target >= 0, encloses(Int(target), transition.sourceIndex, in: diagram) {
                anchors.append(StateDiagramCompositeAnchor(transitionIndex: transitionIndex, compositeIndex: Int(target), isInward: false))
            }
        }
        return anchors.elements
    }

    /// Whether `state` was last named inside the composite at `compositeIndex`, directly or in composites inside it.
    private static func encloses(_ compositeIndex: Int, _ state: Int, in diagram: StateDiagram) -> Bool {
        let states = diagram.model.states
        var current = states[state].compositeIndex
        var steps = 0
        while let index = current, steps <= diagram.composites.count {
            if index == compositeIndex { return true }
            current = states[diagram.composites[index].stateIndex].compositeIndex
            steps += 1
        }
        return false
    }

    /// The direction each composite's box runs in: its own, else that of the nearest composite around it that has one,
    /// else the diagram's.
    static func compositeDirections(of diagram: StateDiagram) -> [FlowchartDirection] {
        let states = diagram.model.states
        var directions: [FlowchartDirection] = []
        directions.reserveCapacity(diagram.composites.count)
        for index in diagram.composites.indices {
            var direction = diagram.direction
            var current: Int? = index
            var steps = 0
            while let composite = current, steps <= diagram.composites.count {
                if let own = diagram.composites[composite].direction {
                    direction = own
                    break
                }
                current = states[diagram.composites[composite].stateIndex].compositeIndex
                steps += 1
            }
            directions.append(direction)
        }
        return directions
    }
}
