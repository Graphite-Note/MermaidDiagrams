/**
 * File: AgentFlowModel.swift
 * --------------------------
 * Layer: Core
 * Description: An agent flow as its reader writes it: flat records of small values, each text a range of the prepared
 *              text's bytes or of the bytes made after them, each name a number, and the lists of styles, classes,
 *              members and metadata bodies kept as entries by owner.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

/// A node as the reader keeps it: what Mermaid's database keeps of it, its texts as ranges of the model's bytes.
struct AgentFlowVertexRecord {
    /// Its identifier as first named, and its name's number.
    var identifier: MermaidTextRange
    var name: Int32
    var text = MermaidTextRange.empty
    var hasText = false
    var labelType = AgentFlowLabelType.text
    /// The shape its brackets or its metadata name, as a number of `AgentFlowShapeNames`, or -1.
    var type: Int16 = -1
    var isConnector = false
    /// Whether a node statement named it, which gives it properties, empty when none were written.
    var hasProperties = false
    var hasMetadata = false
    var link: MermaidTextRange?
    var linkTarget: MermaidTextRange?
    /// The first of the model's attributes that is still its own: a connector declared over a node starts it afresh.
    var firstAttribute: Int32 = 0
}

/// An edge as the reader keeps it.
struct AgentFlowEdgeRecord {
    /// Its ends as written in the statement that made it, and their names.
    var start: MermaidTextRange
    var end: MermaidTextRange
    var startName: Int32
    var endName: Int32
    var identifier: MermaidTextRange
    var identifierName: Int32
    var isUserDefinedIdentifier: Bool
    var arrow: AgentFlowArrow
    var stroke: AgentFlowStroke
    var semantic: AgentFlowEdgeSemantic?
    /// The ranks it spans, at most 10, or -1.
    var length: Int32
    var text = MermaidTextRange.empty
    var labelType = AgentFlowLabelType.text
    var interpolation: MermaidTextRange?
    /// Its `linkStyle` styles, a run of the model's style ranges, or nil.
    var style: Range<Int32>?
    var hasMetadata = false
}

/// What an arrow ends with: Mermaid's `arrow_open`, `arrow_cross`, `arrow_point`, or `INVALID` for a split arrow whose
/// halves disagree.
enum AgentFlowArrow: UInt8 {
    case open, cross, point, invalid

    var name: String {
        switch self {
        case .open: "arrow_open"
        case .cross: "arrow_cross"
        case .point: "arrow_point"
        case .invalid: "INVALID"
        }
    }
}

/// An edge's line: Mermaid's `normal`, `dotted`, or `INVALID`.
enum AgentFlowStroke: UInt8 {
    case normal, dotted, invalid

    var name: String {
        switch self {
        case .normal: "normal"
        case .dotted: "dotted"
        case .invalid: "INVALID"
        }
    }
}

/// A `flow … end` container as the reader keeps it.
struct AgentFlowFlowRecord {
    var identifier: MermaidTextRange
    var name: Int32
    var title: MermaidTextRange
    var directionKeyword: MermaidTextRange?
    var labelType: AgentFlowLabelType
    /// Whether its metadata's last `view` is `collapsed`.
    var isCollapsed = false
    var hasMetadata = false
}

/// A flow's member: the identifier as the statement naming it wrote it, and its name.
struct AgentFlowMember {
    var flow: Int32
    var name: Int32
    var identifier: MermaidTextRange
}

/// What a node, an edge, a flow or a class definition is given beyond its fields, in the order written: a style, a
/// class, a property (`field` and `value`), a metadata body, a class's style or text style.
struct AgentFlowAttribute {
    enum Kind: UInt8 {
        case style, className, property, metadata, textStyle
    }

    var owner: Int32
    var kind: Kind
    var value: MermaidTextRange
    /// A property's value; empty otherwise.
    var detail = MermaidTextRange.empty
}

/// A `classDef`: its identifier, its styles and text styles among the model's class attributes.
struct AgentFlowClassRecord {
    var identifier: MermaidTextRange
    var name: Int32
}

/// Where a statement sits: what it names (`identifier`, the name of a node's mapping, or -1), its kind, and its place.
struct AgentFlowMappingRecord {
    var identifier: MermaidTextRange
    var name: Int32
    var kind: AgentFlowElementMapping.Kind
    var startLine: Int32
    var startColumn: Int32
    var endLine: Int32
    var endColumn: Int32
    /// The node mapping of the same name before it that is still a node mapping, or -1.
    var previousVertexMapping: Int32 = -1
    /// Whether it is a node's named without brackets, which becomes an attachment when metadata follows it.
    var isBare = false
}

/// The agent flow's model: every record, the bytes their ranges index (the prepared text, then the bytes made while
/// reading), and the graph drawn of them.
struct AgentFlowModel {
    var text = AgentFlowTextBytes()
    var directionKeyword: MermaidTextRange?
    var vertices: [AgentFlowVertexRecord] = []
    var edges: [AgentFlowEdgeRecord] = []
    var flows: [AgentFlowFlowRecord] = []
    var members: [AgentFlowMember] = []
    var vertexAttributes: [AgentFlowAttribute] = []
    var edgeAttributes: [AgentFlowAttribute] = []
    var flowAttributes: [AgentFlowAttribute] = []
    var classDefinitions: [AgentFlowClassRecord] = []
    var classAttributes: [AgentFlowAttribute] = []
    /// The ranges of the styles `linkStyle` gives, which edges and the default style take runs of.
    var styleRanges: [MermaidTextRange] = []
    var connectorIdentifiers: [MermaidTextRange] = []
    var defaultEdgeStyle: Range<Int32>?
    var defaultInterpolation: MermaidTextRange?
    var mappings: [AgentFlowMappingRecord] = []
    var diagnostics: [AgentFlowDiagnostic] = []
    var accessibilityTitle: MermaidTextRange?
    var accessibilityDescription: MermaidTextRange?
    var graph = AgentFlowGraphRecords()
}

extension AgentFlowModel {
    /// The strings of a run of the graph's style ranges.
    func graphStyleStrings(_ run: Range<Int32>) -> [String] {
        run.map { style in text.string(graph.styleRanges[Int(style)]) }
    }
}
