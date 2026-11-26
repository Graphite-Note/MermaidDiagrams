/**
 * File: AgentFlowGraph.swift
 * --------------------------
 * Layer: Core
 * Description: What an agent flow draws, as Pele's graph.ts resolves it, as the model gives it and as the reader keeps
 *              it, and the diagnostics Mermaid's vocabulary names.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 26/11/2026
 */

/// The nodes and edges an agent flow draws: its flows as groups (innermost first, as Pele lists them, the last closed
/// first), then its nodes, each with its parent flow, its shape reduced to the ones an agent flow has, its palette slot;
/// the edges between what is still drawn once collapsed flows stand for what they hold.
public struct AgentFlowGraph: Equatable, Sendable {
    public internal(set) var nodes: [AgentFlowGraphNode] = []
    public internal(set) var edges: [AgentFlowGraphEdge] = []
}

public struct AgentFlowGraphNode: Equatable, Sendable {
    public let identifier: String
    public internal(set) var label: String?
    public internal(set) var labelType: AgentFlowLabelType
    /// Mermaid's shape name: `flowGroup` for an open flow, `collapsedGroup` for a collapsed one, else one of
    /// `roundedRect`, `subroutine`, `subprocess`, `subproc`, `framed-rectangle`, `lean-right`, `diamond`, `lin-doc`,
    /// `lined-document`, `hexagon`, `hex` and `connector`.
    public internal(set) var shape: String
    /// Whether it is an open flow, drawn as a box around what it holds.
    public let isGroup: Bool
    public internal(set) var parentIdentifier: String?
    /// The node's own `style` statements, and the styles its classes give it.
    public internal(set) var styles: [String]
    public internal(set) var compiledStyles: [String]
    public internal(set) var classes: String
    public internal(set) var directionKeyword: String?
    public internal(set) var link: String?
    public internal(set) var linkTarget: String?
    public internal(set) var tooltip: String?
    /// A flow's palette slot, open or collapsed.
    public internal(set) var colorIndex: Int?
    /// A flow's number among the containers in the order they were written, which picks its slot in a palette of any length.
    var containerNumber: Int?
    /// What a node means, which picks its palette slot; nil for a flow.
    public internal(set) var kind: AgentFlowVertexKind?
}

public struct AgentFlowGraphEdge: Equatable, Sendable {
    public let identifier: String
    public let isUserDefinedIdentifier: Bool
    public let start: String
    public let end: String
    public let type: String
    public let label: String
    public let labelType: AgentFlowLabelType
    /// `normal` or `dotted`, or nil.
    public let thickness: String?
    public let minimumLength: Int?
    /// `none`, `arrow_point` or `arrow_cross`.
    public let arrowTypeEnd: String
    public let compiledStyles: [String]
    public let style: [String]
    public let curve: String?
}

/// A finding Mermaid's agent flow reports on the model rather than as an error, with its words.
public struct AgentFlowDiagnostic: Equatable, Sendable {
    /// Mermaid's diagnostic vocabulary. Only `shapeUnsupported`, `shapeRemoved` and `containmentViolation` are raised
    /// while reading; the others are reserved for tools that check what a diagram means.
    public enum Identifier: String, Equatable, Sendable, CaseIterable {
        case shapeUnsupported = "SHAPE_UNSUPPORTED"
        case shapeRemoved = "SHAPE_REMOVED"
        case edgeOperatorUnsupported = "EDGE_OPERATOR_UNSUPPORTED"
        case referenceEdgeLabelRejected = "REFERENCE_EDGE_LABEL_REJECTED"
        case connectorReferenceUnresolved = "CONNECTOR_REF_UNRESOLVED"
        case connectorReferenceNotAConnector = "CONNECTOR_REF_NOT_A_CONNECTOR"
        case metadataKeyMisapplied = "METADATA_KEY_MISAPPLIED"
        case duplicateNodeIdentifier = "DUPLICATE_ID_NODE"
        case reservedSyntheticIdentifier = "RESERVED_SYNTHETIC_ID"
        case containmentViolation = "CONTAINMENT_VIOLATION"
        case edgeSemanticContradiction = "EDGE_SEMANTIC_CONTRADICTION"
        case flowWithoutInput = "FLOW_NO_INPUT"

        /// Whether a parser raises it.
        public var isEmitted: Bool {
            self == .shapeUnsupported || self == .shapeRemoved || self == .containmentViolation
        }
    }

    public enum Severity: String, Equatable, Sendable {
        case warning, error
    }

    public let identifier: Identifier
    public let severity: Severity
    public let message: String
    public let nodeIdentifier: String?
    /// Where the node it is about was first named, or nil.
    public let position: AgentFlowElementPosition?
}

/// A node of the graph drawn, as the reader keeps it: its name and identifier, its text, its shape as a number of
/// `AgentFlowShapeNames`, the flow holding it, where its styles come from, its palette slot and kind.
struct AgentFlowGraphNodeRecord {
    var name: Int32
    var identifier: MermaidTextRange
    var label: MermaidTextRange
    var labelType: AgentFlowLabelType
    var shape: Int16
    var isGroup: Bool
    /// The graph node of the flow holding it, or -1.
    var parent: Int32 = -1
    /// The node and the flow it was made of (a flow and a node of one identifier make one graph node), or -1.
    var vertex: Int32 = -1
    var flow: Int32 = -1
    /// Its class styles then its own styles, two runs of the graph's style ranges.
    var compiledStyles: Range<Int32> = 0..<0
    var styles: Range<Int32> = 0..<0
    /// A node's `click` tooltip; a flow has none.
    var tooltip: MermaidTextRange?
    var colorIndex: Int32 = -1
    var containerNumber: Int32 = -1
    var kind: AgentFlowVertexKind?
}

/// An edge of the graph drawn, as the reader keeps it: the model's edge it draws, its ends once collapsed flows stand
/// for what they hold (their graph nodes, -1 for an end no node is drawn for), its arrowhead and styles.
struct AgentFlowGraphEdgeRecord {
    var edge: Int32
    var identifier: MermaidTextRange
    var start: AgentFlowNamedText
    var end: AgentFlowNamedText
    var startNode: Int32
    var endNode: Int32
    var arrowTypeEnd: FlowchartArrowhead
    var compiledStyles: Range<Int32>
    var style: Range<Int32>
    var curve: MermaidTextRange?
}

/// The graph drawn, as the reader keeps it.
struct AgentFlowGraphRecords {
    var nodes: [AgentFlowGraphNodeRecord] = []
    var edges: [AgentFlowGraphEdgeRecord] = []
    /// The ranges of the nodes' and edges' styles, which they take runs of.
    var styleRanges: [MermaidTextRange] = []
}
