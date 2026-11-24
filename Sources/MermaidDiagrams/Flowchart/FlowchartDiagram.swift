/**
 * File: FlowchartDiagram.swift
 * ----------------------------
 * Layer: Core
 * Description: A Mermaid flowchart as its text describes it, over the flat model its reading made, its nodes, edges and
 *              groups made from the model when they are read.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.4
 * Date: 24/11/2026
 */

/// A Mermaid flowchart (`flowchart` or `graph`) as its text describes it: the nodes in the order they first
/// appear, the edges between them in the order they are written, and the groups and statements read but not drawn.
///
/// The flowchart keeps the flat model its reading made (`FlowchartModel`): `nodes`, `edges` and `subgraphs` are made from
/// it each time they are read, so a loop over a flowchart's nodes reads `nodeCount` and `node(at:)` instead.
public struct FlowchartDiagram: Equatable, Sendable {
    public internal(set) var direction: FlowchartDirection
    /// The nodes, edges and groups, as the reading made them.
    private(set) var model: FlowchartModel
    /// The diagram's title, from `title:` in the front matter, or nil.
    public internal(set) var title: String?
    /// `accTitle: …`, the short name a screen reader gives the diagram, or nil.
    public internal(set) var accessibilityTitle: String?
    /// `accDescr: …` or `accDescr { … }`, the longer description a screen reader reads, or nil.
    public internal(set) var accessibilityDescription: String?
    /// Statements, or parts of them, that are read and not applied: a `click`, a style property this drawing has no place
    /// for (`font-size`) or a value it does not read, a style for a group or a link that is not there. The colors and
    /// strokes of `classDef`, `class`, `:::`, `style` and `linkStyle` are applied (`FlowchartNode.style`, `FlowchartEdge.style`).
    public internal(set) var unappliedStatementCount: Int

    init(direction: FlowchartDirection = .topToBottom, nodes: [FlowchartNode] = [], edges: [FlowchartEdge] = [],
         subgraphs: [FlowchartSubgraph] = [], title: String? = nil, accessibilityTitle: String? = nil,
         accessibilityDescription: String? = nil, unappliedStatementCount: Int = 0) {
        self.init(direction: direction, model: FlowchartModel(nodes: nodes, edges: edges, subgraphs: subgraphs), title: title,
                  accessibilityTitle: accessibilityTitle, accessibilityDescription: accessibilityDescription, unappliedStatementCount: unappliedStatementCount)
    }

    init(direction: FlowchartDirection, model: FlowchartModel, title: String? = nil, accessibilityTitle: String?, accessibilityDescription: String?,
         unappliedStatementCount: Int) {
        self.direction = direction
        self.model = model
        self.title = title
        self.accessibilityTitle = accessibilityTitle
        self.accessibilityDescription = accessibilityDescription
        self.unappliedStatementCount = unappliedStatementCount
    }

    /// The nodes in the order they first appear, made from the model on each read.
    public internal(set) var nodes: [FlowchartNode] {
        get { model.materializedNodes }
        set { model = FlowchartModel(nodes: newValue, edges: edges, subgraphs: subgraphs) }
    }

    /// The edges in the order they are written, made from the model on each read.
    public internal(set) var edges: [FlowchartEdge] {
        get { model.materializedEdges }
        set { model = FlowchartModel(nodes: nodes, edges: newValue, subgraphs: subgraphs) }
    }

    /// The `subgraph … end` groups, each before the groups inside it, groups side by side in the order they are written;
    /// made from the model on each read.
    public internal(set) var subgraphs: [FlowchartSubgraph] {
        get { model.materializedSubgraphs }
        set { model = FlowchartModel(nodes: nodes, edges: edges, subgraphs: newValue) }
    }

    public var nodeCount: Int { model.nodes.count }
    public var edgeCount: Int { model.edges.count }
    public var subgraphCount: Int { model.groupCount }

    /// The node at `index`, made from the model.
    public func node(at index: Int) -> FlowchartNode { model.node(at: index) }
    /// The edge at `index`, made from the model.
    public func edge(at index: Int) -> FlowchartEdge { model.edge(at: index) }
    /// The group at `index`, made from the model.
    public func subgraph(at index: Int) -> FlowchartSubgraph { model.subgraph(at: index) }

    /// Flowcharts are equal when they read the same: the same nodes, edges, groups, titles and statements not applied,
    /// whatever text their models index.
    public static func == (left: FlowchartDiagram, right: FlowchartDiagram) -> Bool {
        left.direction == right.direction && left.title == right.title && left.accessibilityTitle == right.accessibilityTitle
            && left.accessibilityDescription == right.accessibilityDescription && left.unappliedStatementCount == right.unappliedStatementCount
            && left.nodeCount == right.nodeCount && left.edgeCount == right.edgeCount && left.subgraphCount == right.subgraphCount
            && left.nodes == right.nodes && left.edges == right.edges && left.subgraphs == right.subgraphs
    }

    /// The flowchart with its groups titled `titles`, in their order.
    func retitlingSubgraphs(_ titles: [DiagramLabel]) -> FlowchartDiagram {
        var retitled = self
        retitled.model = model.retitlingGroups(titles)
        return retitled
    }

    /// The flowchart with each group's direction changed by `turn`.
    func turningGroupDirections(_ turn: (FlowchartDirection?) -> FlowchartDirection?) -> FlowchartDiagram {
        var turned = self
        turned.model = model.turningGroupDirections(turn)
        return turned
    }
}

/// The way a flowchart's ranks follow each other.
public enum FlowchartDirection: Equatable, Sendable, CaseIterable {
    /// `TB` or `TD`, the default.
    case topToBottom
    /// `BT`.
    case bottomToTop
    /// `LR`.
    case leftToRight
    /// `RL`.
    case rightToLeft

    /// The direction a Mermaid keyword names: `TB`, `TD`, `BT`, `LR`, `RL`, or the older arrows `v`, `^`, `>`, `<`.
    init?(keyword: String) {
        switch keyword.uppercased() {
        case "TB", "TD", "V": self = .topToBottom
        case "BT", "^": self = .bottomToTop
        case "LR", ">": self = .leftToRight
        case "RL", "<": self = .rightToLeft
        default: return nil
        }
    }

    /// Whether ranks follow each other across the page rather than down it.
    var runsAcross: Bool {
        switch self {
        case .leftToRight, .rightToLeft: true
        case .topToBottom, .bottomToTop: false
        }
    }
}

/// A `subgraph … end` group: its identifier, its title, what is directly inside it and the direction it runs in.
///
/// Membership follows Mermaid: a group holds the nodes and groups named in its own statements, and a node named in
/// several groups belongs to the first of them to end, so a node named in a group and again in the group around it
/// is in the inner one only. A group whose identifier is named inside another group (`A --> inner`) sits inside it.
public struct FlowchartSubgraph: Equatable, Sendable {
    /// The identifier written after `subgraph`, or `subGraph` and the number of groups that ended before this one.
    public let identifier: String
    public internal(set) var title: DiagramLabel
    /// Indexes into `FlowchartDiagram.nodes` of the nodes directly inside the group, in the order they are named in it.
    public internal(set) var nodeIndices: [Int]
    /// Indexes into `FlowchartDiagram.subgraphs` of the groups directly inside this one.
    public internal(set) var childSubgraphIndices: [Int]
    /// `direction TB`, `TD`, `BT`, `LR` or `RL` inside the group, or nil when it runs as the group around it does.
    public internal(set) var direction: FlowchartDirection?
    /// The node whose identifier is the group's, when the text names the group like a node (`A --> group`,
    /// `group@{ … }`): it stands for the group, so edges to it meet the group's box, and it is not drawn as a node.
    public internal(set) var representingNodeIndex: Int?
    /// Whether `@{ view: collapsed }` asks for the group drawn as one node in place of its content.
    public internal(set) var isCollapsed: Bool

    init(identifier: String, title: DiagramLabel, nodeIndices: [Int] = [], childSubgraphIndices: [Int] = [],
         direction: FlowchartDirection? = nil, representingNodeIndex: Int? = nil, isCollapsed: Bool = false) {
        self.identifier = identifier
        self.title = title
        self.nodeIndices = nodeIndices
        self.childSubgraphIndices = childSubgraphIndices
        self.direction = direction
        self.representingNodeIndex = representingNodeIndex
        self.isCollapsed = isCollapsed
    }
}
