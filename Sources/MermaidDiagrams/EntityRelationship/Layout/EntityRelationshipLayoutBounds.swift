/**
 * File: EntityRelationshipLayoutBounds.swift
 * ------------------------------------------
 * Layer: Core
 * Description: The rectangle an entity relationship diagram's drawing covers, taken relationship by relationship.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

import CoreGraphics

/// The rectangle an entity relationship diagram's drawing covers: its boxes, its lines with their curves' control
/// points, its marks and its labels with the patches behind them.
enum EntityRelationshipLayoutBounds {
    /// `bounds` and what `relationship` covers: its line's points with its curves' control points, its marks, and its
    /// label with the patch behind it unless `includesLabel` is false, taken in that order.
    static func union(_ bounds: CGRect, relationship: EntityRelationshipLayoutRelationship, includesLabel: Bool = true) -> CGRect {
        var bounds = bounds.union(CGRect(origin: relationship.path.start, size: .zero))
        for segment in relationship.path.segments {
            switch segment {
            case .line(let end): bounds = bounds.union(CGRect(origin: end, size: .zero))
            case .curve(let end, let firstControl, let secondControl):
                bounds = bounds.union(CGRect(origin: end, size: .zero)).union(CGRect(origin: firstControl, size: .zero))
                    .union(CGRect(origin: secondControl, size: .zero))
            }
        }
        let reach = EntityRelationshipCardinalityMark.length
        bounds = bounds.union(CGRect(origin: relationship.firstEntityMark.tip, size: .zero).insetBy(dx: -reach, dy: -reach))
        bounds = bounds.union(CGRect(origin: relationship.secondEntityMark.tip, size: .zero).insetBy(dx: -reach, dy: -reach))
        if includesLabel, let label = relationship.label {
            let room = EntityRelationshipLayoutEngine.labelRoom
            bounds = bounds.union(label.frame.insetBy(dx: -room.width / 2, dy: -room.height / 2))
        }
        return bounds
    }
}
