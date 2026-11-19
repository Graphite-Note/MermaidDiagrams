/**
 * File: StateDiagramLayoutError.swift
 * -----------------------------------
 * Layer: Core
 * Description: Why a state diagram was not laid out.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */

/// Why a state diagram was not laid out.
public enum StateDiagramLayoutError: Error, Equatable, Sendable {
    /// The diagram's composite states (`state Id { … }`) cannot be laid out as boxes: a composite is inside itself through
    /// the states it holds. Kept for callers that match it; transitions into and onto composites, notes beside them and
    /// exits across a box's flow are now laid out as Pele lays them out.
    case compositeStatesNotLaidOut
    /// The states and the points transitions pass through would be more than the limit.
    case tooManyLayoutPoints(limit: Int)
}
