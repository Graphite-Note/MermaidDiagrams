/**
 * File: StateDiagramLayoutBounds.swift
 * ------------------------------------
 * Layer: Core
 * Description: The rectangle a placed state diagram's drawing covers, read from its flat records and their runs of
 *              segments.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.2
 * Date: 26/11/2026
 */

import CoreGraphics

/// The rectangle a state diagram's drawing covers: its states and notes, its lines with their curves' control points,
/// its arrows, and its transitions' texts with the patches behind them.
enum StateDiagramLayoutBounds {
    static func union(states: [StateDiagramPlacedState], transitions: [StateDiagramPlacedTransition], notes: [StateDiagramPlacedNote],
                      segments: [DiagramPathSegment]) -> CGRect {
        var bounds = CGRect.null
        for state in states { bounds = bounds.union(state.frame) }
        for note in notes {
            bounds = bounds.union(note.frame)
            bounds = DiagramRouteSegments.union(bounds, note.connector, in: segments)
        }
        for transition in transitions {
            bounds = DiagramRouteSegments.union(bounds, transition.line, in: segments)
            let arrowLength = DiagramEdgeMark.arrowLength
            bounds = bounds.union(CGRect(origin: transition.arrow.tip, size: .zero).insetBy(dx: -arrowLength, dy: -arrowLength))
            if let text = transition.text {
                let room = StateDiagramLayoutEngine.transitionTextRoom
                bounds = bounds.union(text.frame.insetBy(dx: -room.width / 2, dy: -room.height / 2))
            }
        }
        return bounds.isNull ? .zero : bounds
    }
}
