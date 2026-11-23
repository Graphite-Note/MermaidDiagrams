/**
 * File: StateDiagramRouteEnds.swift
 * ---------------------------------
 * Layer: Core
 * Description: A transition's end moved from where the layout settled it on a state's layout box onto the state drawn
 *              in the box, as Pele's state diagram attaches it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import CoreGraphics

/// Pele's `attach` (state/render.ts): the layout leaves each end of a transition on a side of its state's layout box
/// (the state with the room its loops and notes take), where it spread and settled it; the drawing moves it straight in
/// onto the state's own box, keeping its place along the side. On a fork's or join's bar, which is longer than it is
/// thick, the end takes the place across of the route's next point, kept 6 points inside the bar's ends. An end on no
/// side of the box is left where it is.
enum StateDiagramRouteEnds {
    /// How near a side of the layout box an end must be to lie on it.
    static let sideTolerance: CGFloat = 0.5
    /// How far inside a bar's ends an end on it stays.
    static let barEndClearance: CGFloat = 6

    /// - Parameters:
    ///   - end: The route's end, on the page.
    ///   - next: The route's point next to `end`.
    ///   - center: The state's center, which is its layout box's.
    ///   - layoutSize: The state's layout box.
    ///   - drawnSize: The state's own box, or its mark's.
    ///   - isBar: Whether the state is a fork or a join.
    static func attached(_ end: CGPoint, next: CGPoint, center: CGPoint, layoutSize: CGSize, drawnSize: CGSize, isBar: Bool) -> CGPoint {
        // Pele tries the sides facing down the page first, then those facing across.
        for isVerticalAxis in [true, false] {
            let extent = isVerticalAxis ? layoutSize.height : layoutSize.width
            let drawnExtent = isVerticalAxis ? drawnSize.height : drawnSize.width
            let breadth = isVerticalAxis ? drawnSize.width : drawnSize.height
            let delta = isVerticalAxis ? end.y - center.y : end.x - center.x
            guard abs(abs(delta) - extent / 2) < sideTolerance else { continue }
            let inset = (delta > 0 ? 1 : delta < 0 ? -1 : 0) * (extent - drawnExtent) / 2
            var attached = end
            if isVerticalAxis { attached.y -= inset } else { attached.x -= inset }
            if isBar && breadth > drawnExtent {
                let cross = isVerticalAxis ? center.x : center.y
                let low = cross - breadth / 2 + barEndClearance
                let high = cross + breadth / 2 - barEndClearance
                // Pele's clamp: below the low end, the low end, even on a bar too short for both clearances.
                let value = isVerticalAxis ? next.x : next.y
                let along = value < low ? low : value > high ? high : value
                if isVerticalAxis { attached.x = along } else { attached.y = along }
            }
            return attached
        }
        return end
    }
}
