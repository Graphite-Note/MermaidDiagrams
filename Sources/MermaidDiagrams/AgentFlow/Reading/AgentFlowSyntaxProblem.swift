/**
 * File: AgentFlowSyntaxProblem.swift
 * ----------------------------------
 * Layer: Core
 * Description: What broke an agent flow's syntax, as Mermaid's grammar and database find it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// What broke an agent flow's syntax or what its database refuses, with the facts Mermaid's message gives.
public enum AgentFlowSyntaxProblem: Equatable, Sendable {
    /// Text no rule of the lexer reads where it stands.
    case unrecognizedText
    /// A token the grammar does not take where it stands, by Jison's name of it, with what the grammar expected there
    /// as Jison lists it (`'SQE', 'UNICODE_TEXT', 'TEXT', 'TAGSTART'`).
    case unexpectedToken(found: String, expected: String)
    /// A node's, an edge's, a flow's or a connector's `@{ … }` is not YAML, by its identifier.
    case metadataNotYAML(identifier: String)
    /// A `shape:` that names no shape Mermaid knows, or that is not text, as written.
    case unknownShape(String)
    /// A `shape:` written with a capital or an underscore.
    case shapeNameNotLowercase(String)
    /// `linkStyle` names an edge that is not there, by the index written and the number of edges.
    case linkStyleIndexOutOfBounds(index: String, edgeCount: Int)
}
