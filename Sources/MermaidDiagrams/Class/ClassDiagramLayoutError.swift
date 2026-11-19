/**
 * File: ClassDiagramLayoutError.swift
 * -----------------------------------
 * Layer: Core
 * Description: Why a class diagram was not laid out.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */

/// Why a class diagram was not laid out.
public enum ClassDiagramLayoutError: Error, Equatable, Sendable {
    /// The namespaces could not be laid out: kept for callers that match it, though every namespace is now drawn as a
    /// box, and thrown only for namespaces inside each other.
    case namespacesNotLaidOut
    /// The nodes and the points relations pass through would be more than the limit.
    case tooManyLayoutPoints(limit: Int)
}
