/**
 * File: EntityRelationshipLayoutError.swift
 * -----------------------------------------
 * Layer: Core
 * Description: Why an entity relationship diagram was not laid out.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */

/// Why an entity relationship diagram was not laid out.
public enum EntityRelationshipLayoutError: Error, Equatable, Sendable {
    /// A group could not be laid out: one related to itself (Pele hangs that loop outside its box, which is not drawn
    /// yet), or groups that hold each other. Every other group is drawn as a box.
    case subgraphsNotLaidOut
    /// The entities and the points relationships pass through would be more than the limit.
    case tooManyLayoutPoints(limit: Int)
}
