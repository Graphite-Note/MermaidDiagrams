/**
 * File: ReferenceStateDiagramLayoutBounds.swift
 * ---------------------------------------------
 * Layer: Tests
 * Description: The 0.7.0 StateDiagramLayoutBounds kept as the reference the 0.8.0 layout is checked against: the
 *              rectangle a state diagram's drawing covers.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// The rectangle a state diagram's drawing covers: its states and notes, its lines with their curves' control points,
/// its arrows, and its transitions' texts with the patches behind them.
enum ReferenceStateDiagramLayoutBounds {
    static func union(states: [StateDiagramLayoutState], transitions: [StateDiagramLayoutTransition], notes: [StateDiagramLayoutNote]) -> CGRect {
        var bounds = CGRect.null
        for state in states { bounds = bounds.union(state.frame) }
        for note in notes {
            bounds = bounds.union(note.frame)
            bounds = union(bounds, note.connector)
        }
        for transition in transitions {
            bounds = union(bounds, transition.path)
            let arrowLength = DiagramEdgeMark.arrowLength
            bounds = bounds.union(CGRect(origin: transition.arrow.tip, size: .zero).insetBy(dx: -arrowLength, dy: -arrowLength))
            if let text = transition.text {
                let room = ReferenceStateDiagramLayoutEngine.transitionTextRoom
                bounds = bounds.union(text.frame.insetBy(dx: -room.width / 2, dy: -room.height / 2))
            }
        }
        return bounds.isNull ? .zero : bounds
    }

    private static func union(_ bounds: CGRect, _ path: DiagramPath) -> CGRect {
        var bounds = bounds.union(CGRect(origin: path.start, size: .zero))
        for segment in path.segments {
            switch segment {
            case .line(let end): bounds = bounds.union(CGRect(origin: end, size: .zero))
            case .curve(let end, let firstControl, let secondControl):
                bounds = bounds.union(CGRect(origin: end, size: .zero)).union(CGRect(origin: firstControl, size: .zero))
                    .union(CGRect(origin: secondControl, size: .zero))
            }
        }
        return bounds
    }
}
