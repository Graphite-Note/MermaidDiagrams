/**
 * File: AgentFlowDiagramElements.swift
 * ------------------------------------
 * Layer: Core
 * Description: An agent flow's nodes, edges and flows as Mermaid's database keeps them, the values its model gives when
 *              they are asked for.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

/// A node as Mermaid's database keeps it.
public struct AgentFlowVertex: Equatable, Sendable {
    public let identifier: String
    public internal(set) var text: String?
    public internal(set) var labelType: AgentFlowLabelType = .text
    /// The shape its brackets or its metadata name (`square`, `diamond`, `subroutine`), or nil.
    public internal(set) var type: String?
    public internal(set) var styles: [String] = []
    public internal(set) var classes: [String] = []
    /// What a node statement's text gave it beyond its label; nil for a connector no node statement named.
    public internal(set) var properties: [String: String]?
    /// A `click … href` link made safe, or nil; and its target.
    public internal(set) var link: String?
    public internal(set) var linkTarget: String?
    public internal(set) var isConnector = false
    var metadata: AgentFlowMetadata?

    init(identifier: String) {
        self.identifier = identifier
    }

    /// The metadata's keys, in no order.
    public var metadataKeys: Set<String> { Set(metadata.map { metadata in Array(metadata.keys) } ?? []) }

    /// The metadata's value for `key` as JavaScript's `String` writes it, or nil.
    public func metadataText(_ key: String) -> String? {
        metadata?[key].map(\.javaScriptText)
    }
}

/// What an edge means: `-->` a step, `--x` a failure, `-.-` a reference.
public enum AgentFlowEdgeSemantic: String, Equatable, Sendable {
    case sequence, reference, failure
}

/// An edge as Mermaid's database keeps it.
public struct AgentFlowEdge: Equatable, Sendable {
    public let start: String
    public let end: String
    /// `arrow_point`, `arrow_cross`, `arrow_open`, or `INVALID` for a split arrow whose halves disagree.
    public internal(set) var type: String?
    public internal(set) var text = ""
    public internal(set) var labelType: AgentFlowLabelType = .text
    /// `normal` or `dotted`.
    public internal(set) var stroke: String?
    public internal(set) var semantic: AgentFlowEdgeSemantic?
    /// The ranks it spans, at most 10.
    public internal(set) var length: Int?
    public internal(set) var style: [String]?
    public internal(set) var classes: [String] = []
    public internal(set) var identifier: String
    public internal(set) var isUserDefinedIdentifier = false
    public internal(set) var interpolation: String?
    var metadata: AgentFlowMetadata?
}

/// A `flow … end` container.
public struct AgentFlowFlow: Equatable, Sendable {
    public let identifier: String
    /// What it holds directly, by identifier, in the order named; a flow, a global node or a node another flow holds is
    /// never here.
    public internal(set) var nodeIdentifiers: [String]
    public internal(set) var title: String
    public internal(set) var classes: [String] = []
    public internal(set) var directionKeyword: String?
    public internal(set) var labelType: AgentFlowLabelType
    var metadata: AgentFlowMetadata?

    /// Whether `@{ view: collapsed }` asks for the flow drawn as one node.
    public var isCollapsed: Bool {
        if case .text("collapsed") = metadata?["view"] { return true }
        return false
    }
}

