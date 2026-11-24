/**
 * File: ReferenceStateDiagramCompositeAnchors.swift
 * -------------------------------------------------
 * Layer: Tests
 * Description: The 0.7.0 StateDiagramCompositeAnchors kept as the reference the 0.8.0 layout is checked against:
 *              transitions between a composite state and a state inside it, run from a point just inside the composite,
 *              as Pele's state renderer runs them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

@testable import MermaidDiagrams

/// A transition between a composite state and a state inside it (`Moving --> slow` with `slow` in `Moving`), as Pele's
/// state renderer lays it out (`state/render.ts`, its `anchor`): the composite's end is a point of no size inside the
/// composite's box, first in the box's order when the transition leaves the composite and last when it arrives, the
/// transition is laid out between that point and the inner state, and it is then drawn on to the composite's border:
/// below its title, on the side its flow starts from, when it leaves the composite; on the side its flow ends at when it
/// arrives.
struct ReferenceStateDiagramCompositeAnchor: Equatable {
    let transitionIndex: Int
    /// The composite (its index in `StateDiagram.composites`) whose box holds the point.
    let compositeIndex: Int
    /// Whether the transition leaves the composite for the state inside, rather than arrives from it.
    let isInward: Bool
}

enum ReferenceStateDiagramCompositeAnchors {
    /// The anchors of a diagram's transitions, in their order.
    static func anchors(of diagram: StateDiagram, compositeOfState: [Int?]) -> [ReferenceStateDiagramCompositeAnchor] {
        diagram.transitions.enumerated().compactMap { transitionIndex, transition in
            if let composite = compositeOfState[transition.sourceIndex], encloses(composite, transition.targetIndex, in: diagram) {
                return ReferenceStateDiagramCompositeAnchor(transitionIndex: transitionIndex, compositeIndex: composite, isInward: true)
            }
            if let composite = compositeOfState[transition.targetIndex], encloses(composite, transition.sourceIndex, in: diagram) {
                return ReferenceStateDiagramCompositeAnchor(transitionIndex: transitionIndex, compositeIndex: composite, isInward: false)
            }
            return nil
        }
    }

    /// Whether `state` sits inside the composite, at any depth; the walk out is bounded by the number of composites.
    private static func encloses(_ compositeIndex: Int, _ state: Int, in diagram: StateDiagram) -> Bool {
        var current = diagram.states[state].compositeIndex
        var steps = 0
        while let index = current, steps <= diagram.composites.count {
            if index == compositeIndex { return true }
            current = diagram.states[diagram.composites[index].stateIndex].compositeIndex
            steps += 1
        }
        return false
    }

    /// The direction each composite's box runs in: its own, else the box around it's, else the diagram's.
    static func compositeDirections(of diagram: StateDiagram) -> [FlowchartDirection] {
        diagram.composites.indices.map { index in
            var current: Int? = index
            var steps = 0
            while let composite = current, steps <= diagram.composites.count {
                if let direction = diagram.composites[composite].direction { return direction }
                current = diagram.states[diagram.composites[composite].stateIndex].compositeIndex
                steps += 1
            }
            return diagram.direction
        }
    }
}
