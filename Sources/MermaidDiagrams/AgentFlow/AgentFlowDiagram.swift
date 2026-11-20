/**
 * File: AgentFlowDiagram.swift
 * ----------------------------
 * Layer: Core
 * Description: A Mermaid agent flow (`agentflow-beta`) as its text describes it: its nodes, edges, flows and
 *              connectors as Mermaid's database keeps them, what is drawn of them, and the diagnostics found.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// A Mermaid agent flow as its text describes it, the way Pele's `AgentflowDb` holds it: every node named (connectors
/// among them) in the order first named, every edge in the order written, every flow in the order its `end` closes it,
/// where each statement sits in the text, and the graph drawn of them (`AgentFlowGraph`): flows nested without cycles,
/// collapsed flows standing for what they hold, shapes reduced to the ones an agent flow has, palette slots.
public struct AgentFlowDiagram: Equatable, Sendable {
    /// The direction after the keyword as Mermaid normalizes it (`TB`, `BT`, `LR`, `RL`, or what else it read).
    public internal(set) var directionKeyword: String?
    public internal(set) var vertices: [AgentFlowVertex] = []
    public internal(set) var edges: [AgentFlowEdge] = []
    /// The `flow … end` containers, in the order their `end` closes them: a flow inside another before it.
    public internal(set) var flows: [AgentFlowFlow] = []
    /// The identifiers of the `connector` declarations, in the order first declared.
    public internal(set) var connectorIdentifiers: [String] = []
    public internal(set) var classDefinitions: [AgentFlowClassDefinition] = []
    /// `linkStyle default …`, or nil.
    public internal(set) var defaultEdgeStyle: [String]?
    /// `linkStyle default interpolate …`, or nil.
    public internal(set) var defaultInterpolation: String?
    /// Where each statement sits in the text, in the order read.
    public internal(set) var mappings: [AgentFlowElementMapping] = []
    /// What Pele's graph found wrong with shapes and nesting: diagnostics, not errors.
    public internal(set) var diagnostics: [AgentFlowDiagnostic] = []
    /// What is drawn: the nodes and the edges of Pele's `buildAgentGraph`.
    public internal(set) var graph = AgentFlowGraph()
    public internal(set) var title: String?
    public internal(set) var accessibilityTitle: String?
    public internal(set) var accessibilityDescription: String?
    /// The front matter's and directives' `agentflow:` options.
    public internal(set) var options = AgentFlowOptions()

    /// The direction the diagram runs in: top to bottom unless it says otherwise.
    public var direction: FlowchartDirection {
        directionKeyword.flatMap(FlowchartDirection.init(keyword:)) ?? .topToBottom
    }
}

/// How a text was written: unquoted, quoted, or as a Markdown string.
public enum AgentFlowLabelType: String, Equatable, Sendable {
    case text, string, markdown

    /// Mermaid's `labelType`: one of the three names, else Markdown.
    init(named name: String?) {
        self = name.flatMap(AgentFlowLabelType.init(rawValue:)) ?? .markdown
    }
}

/// What a node means in an agent flow, by its shape, which picks its palette slot.
public enum AgentFlowVertexKind: String, Equatable, Sendable, CaseIterable {
    case tool, task, decision, input, refdoc, connector, action

    /// Pele's fixed slot of the kind (`KIND_SLOT`), so that editing a diagram around a node never recolors it.
    public var paletteSlot: Int {
        switch self {
        case .tool: 0
        case .task: 1
        case .decision: 2
        case .input: 3
        case .refdoc: 4
        case .connector: 5
        case .action: 6
        }
    }
}

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

/// `classDef name styles`: the styles, and those of them that set a color, for the text.
public struct AgentFlowClassDefinition: Equatable, Sendable {
    public let identifier: String
    public internal(set) var styles: [String] = []
    public internal(set) var textStyles: [String] = []
}

/// Where a statement sits in the text: lines from 1, columns from 0, as Mermaid reports them.
public struct AgentFlowElementPosition: Equatable, Sendable {
    public internal(set) var startLine: Int
    public internal(set) var startColumn: Int
    public internal(set) var endLine: Int
    public internal(set) var endColumn: Int
}

/// A statement's place: what it names, what kind of statement it is, and where it sits.
public struct AgentFlowElementMapping: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case vertex, edge, subgraph, connector, attachment
    }

    public let identifier: String
    public internal(set) var kind: Kind
    public internal(set) var position: AgentFlowElementPosition
}

/// The `agentflow:` options of the front matter and the directives, within Pele's bounds (positive, at most 2,000).
public struct AgentFlowOptions: Equatable, Sendable {
    /// The widest a line of a node's or an edge's text is before it wraps.
    public internal(set) var wrappingWidth: Double = 120
    /// The least width a node's shape is sized for (a diamond excepted).
    public internal(set) var minimumNodeWidth: Double = 120
    public internal(set) var nodeSpacing: Double = 40
    public internal(set) var rankSpacing: Double = 48

    public init() {}

    init(_ options: MermaidConfigurationOptions) {
        wrappingWidth = Self.bounded(options.values["wrappingWidth"], fallback: 120)
        minimumNodeWidth = Self.bounded(options.values["minNodeWidth"], fallback: 120)
        nodeSpacing = Self.bounded(options.values["nodeSpacing"], fallback: 40)
        rankSpacing = Self.bounded(options.values["rankSpacing"], fallback: 48)
    }

    /// Pele's `numberOption`: a positive number, at most 2,000, else the fallback.
    private static func bounded(_ value: MermaidConfigurationOptions.Value?, fallback: Double) -> Double {
        guard case .number(let number) = value, number > 0 else { return fallback }
        return min(number, 2000)
    }
}

/// An element's metadata: Pele's YAML values by key.
typealias AgentFlowMetadata = [String: SequenceAttributeValue]
