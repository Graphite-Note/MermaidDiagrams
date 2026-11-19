/**
 * File: SequenceLayoutError.swift
 * -------------------------------
 * Layer: Core
 * Description: Why a sequence diagram was not laid out; no longer thrown, kept for readers that name it.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */

/// Why a sequence diagram was not laid out. Not thrown any more: every statement the reader reads is laid out, so
/// `SequenceDiagram.statementsNotLaidOut` is always empty. Kept so that readers that handle it (Graphite's reading view)
/// still build.
public enum SequenceLayoutError: Error, Equatable, Sendable {
    /// The diagram holds statements that are read but not laid out yet (`SequenceDiagram.statementsNotLaidOut`).
    case statementsNotLaidOut(Set<SequenceStatementNotLaidOut>)
}
