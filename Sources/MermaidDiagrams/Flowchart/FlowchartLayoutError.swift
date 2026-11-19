/**
 * File: FlowchartLayoutError.swift
 * --------------------------------
 * Layer: Core
 * Description: Why a flowchart was not laid out.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */

/// Why a flowchart was not laid out.
public enum FlowchartLayoutError: Error, Equatable, Sendable {
    /// The flowchart's groups could not be laid out: kept for callers that match it, though every group is now laid out
    /// (collapsed ones as nodes, edges into a group and loops on one as Pele draws them), and thrown only for groups
    /// that sit inside each other.
    case subgraphsNotLaidOut
    /// The nodes and the points edges pass through would be more than the limit.
    case tooManyLayoutPoints(limit: Int)
}
