/**
 * File: ClassDiagramLayoutBounds.swift
 * ------------------------------------
 * Layer: Core
 * Description: The rectangle a class diagram's drawing covers, taken part by part.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.3
 * Date: 26/11/2026
 */

import CoreGraphics

/// The rectangle a class diagram's drawing covers: its boxes, notes and interface names, its lines with their
/// curves' control points, room for the longest mark around each tip, and its texts with the patches behind them.
enum ClassDiagramLayoutBounds {
    /// `bounds` and what `edge` covers: its line's points with its curves' control points, room for the longest mark
    /// around each tip, its text with the patch behind it, and its cardinalities, taken in that order.
    static func union(_ bounds: CGRect, edge: ClassDiagramPlacedEdge, segments: [DiagramPathSegment]) -> CGRect {
        var bounds = DiagramRouteSegments.union(bounds, edge.path, in: segments)
        let reach = ClassDiagramMarkGeometry.longestMark
        if let mark = edge.sourceMark { bounds = bounds.union(CGRect(origin: mark.tip, size: .zero).insetBy(dx: -reach, dy: -reach)) }
        if let mark = edge.targetMark { bounds = bounds.union(CGRect(origin: mark.tip, size: .zero).insetBy(dx: -reach, dy: -reach)) }
        if let text = edge.text {
            let room = ClassDiagramLayoutEngine.edgeTextRoom
            bounds = bounds.union(text.frame.insetBy(dx: -room.width / 2, dy: -room.height / 2))
        }
        if let cardinality = edge.sourceCardinality { bounds = bounds.union(cardinality.frame) }
        if let cardinality = edge.targetCardinality { bounds = bounds.union(cardinality.frame) }
        return bounds
    }
}
