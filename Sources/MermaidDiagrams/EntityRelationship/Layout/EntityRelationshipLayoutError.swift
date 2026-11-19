/**
 * File: EntityRelationshipLayoutError.swift
 * -----------------------------------------
 * Layer: Core
 * Description: Why an entity relationship diagram was not laid out.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.3
 * Date: 19/11/2026
 */

/// Why an entity relationship diagram was not laid out.
public enum EntityRelationshipLayoutError: Error, Equatable, Sendable {
    /// Groups could not be laid out: kept for callers that match it, though every group is now drawn as a box, and
    /// thrown only for groups that hold each other.
    case subgraphsNotLaidOut
    /// The entities and the points relationships pass through would be more than the limit.
    case tooManyLayoutPoints(limit: Int)
}
