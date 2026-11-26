/**
 * File: AgentFlowDiagram.swift
 * ----------------------------
 * Layer: Core
 * Description: A Mermaid agent flow (`agentflow-beta`) as its text describes it: a façade over the flat model its reader
 *              writes, giving its nodes, edges, flows and connectors as Mermaid's database keeps them, what is drawn of
 *              them, and the diagnostics found, made when asked for.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 26/11/2026
 */

/// A Mermaid agent flow as its text describes it, the way Pele's `AgentflowDb` holds it: every node named (connectors
/// among them) in the order first named, every edge in the order written, every flow in the order its `end` closes it,
/// where each statement sits in the text, and the graph drawn of them (`AgentFlowGraph`): flows nested without cycles,
/// collapsed flows standing for what they hold, shapes reduced to the ones an agent flow has, palette slots.
///
/// The diagram keeps the flat records its reader wrote (`AgentFlowModel`): each list here is made from them when it is
/// read, so a layout that reads the records costs no String, and a host that reads the lists gets 0.7.0's values.
public struct AgentFlowDiagram: Equatable, Sendable {
    var model: AgentFlowModel
    public internal(set) var title: String?
    /// The front matter's and directives' `agentflow:` options.
    public internal(set) var options: AgentFlowOptions

    init(model: AgentFlowModel = AgentFlowModel(), options: AgentFlowOptions = AgentFlowOptions()) {
        self.model = model
        self.options = options
    }

    /// The direction after the keyword as Mermaid normalizes it (`TB`, `BT`, `LR`, `RL`, or what else it read).
    public var directionKeyword: String? { model.text.string(orNil: model.directionKeyword) }

    /// The direction the diagram runs in: top to bottom unless it says otherwise.
    public var direction: FlowchartDirection {
        directionKeyword.flatMap(FlowchartDirection.init(keyword:)) ?? .topToBottom
    }

    /// The identifiers of the `connector` declarations, in the order first declared.
    public var connectorIdentifiers: [String] { model.connectorIdentifiers.map(model.text.string) }

    /// `linkStyle default …`, or nil.
    public var defaultEdgeStyle: [String]? { model.defaultEdgeStyle.map(styleStrings) }

    /// `linkStyle default interpolate …`, or nil.
    public var defaultInterpolation: String? { model.text.string(orNil: model.defaultInterpolation) }

    public var accessibilityTitle: String? { model.text.string(orNil: model.accessibilityTitle) }
    public var accessibilityDescription: String? { model.text.string(orNil: model.accessibilityDescription) }

    /// Where each statement sits in the text, in the order read.
    public var mappings: [AgentFlowElementMapping] {
        model.mappings.map { mapping in AgentFlowElementMapping(identifier: model.text.string(mapping.identifier), kind: mapping.kind, position: mapping.position) }
    }

    /// What Pele's graph found wrong with shapes and nesting: diagnostics, not errors.
    public var diagnostics: [AgentFlowDiagnostic] { model.diagnostics }

    /// The `classDef` definitions, in the order first defined.
    public var classDefinitions: [AgentFlowClassDefinition] {
        DiagramScratchArena.withCurrentThread { arena in
            let attributes = AgentFlowGraphStyles.index(model.classAttributes, ownerCount: model.classDefinitions.count, arena: arena)
            return classDefinitions(attributes)
        }
    }

    private func classDefinitions(_ attributes: AgentFlowOwnerIndex) -> [AgentFlowClassDefinition] {
        model.classDefinitions.indices.map { index in
            var definition = AgentFlowClassDefinition(identifier: model.text.string(model.classDefinitions[index].identifier))
            for entry in attributes.entries(of: index) {
                let attribute = model.classAttributes[Int(entry)]
                if attribute.kind == .textStyle { definition.textStyles.append(model.text.string(attribute.value)) } else { definition.styles.append(model.text.string(attribute.value)) }
            }
            return definition
        }
    }

    /// The strings of a run of the model's style ranges.
    func styleStrings(_ run: Range<Int32>) -> [String] {
        run.map { style in model.text.string(model.styleRanges[Int(style)]) }
    }

    public static func == (left: AgentFlowDiagram, right: AgentFlowDiagram) -> Bool {
        left.title == right.title && left.options == right.options && left.directionKeyword == right.directionKeyword && left.vertices == right.vertices
            && left.edges == right.edges && left.flows == right.flows && left.connectorIdentifiers == right.connectorIdentifiers
            && left.classDefinitions == right.classDefinitions && left.defaultEdgeStyle == right.defaultEdgeStyle
            && left.defaultInterpolation == right.defaultInterpolation && left.mappings == right.mappings && left.diagnostics == right.diagnostics
            && left.graph == right.graph && left.accessibilityTitle == right.accessibilityTitle
            && left.accessibilityDescription == right.accessibilityDescription
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
