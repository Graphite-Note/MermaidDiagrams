/**
 * File: ReferenceFlowchartDiagram.swift
 * -------------------------------------
 * Layer: Tests
 * Description: MermaidDiagrams 0.7.0's flowchart model, frozen with its reader as the reference the flat reader is
 *              proven against: the nodes, edges and groups as arrays, and the same read from the package's
 *              FlowchartDiagram through its public views, so that the two models compare field by field.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

@testable import MermaidDiagrams

/// A flowchart as 0.7.0's FlowchartDiagram stored it: the nodes in the order they first appear, the edges in the
/// order they are written, the groups each before the groups inside it, the titles and the count of statements read
/// but not applied.
struct ReferenceFlowchartDiagram: Equatable {
    var direction: FlowchartDirection
    var nodes: [FlowchartNode]
    var edges: [FlowchartEdge]
    var subgraphs: [FlowchartSubgraph]
    var title: String?
    var accessibilityTitle: String?
    var accessibilityDescription: String?
    var unappliedStatementCount: Int

    init(direction: FlowchartDirection = .topToBottom, nodes: [FlowchartNode] = [], edges: [FlowchartEdge] = [],
         subgraphs: [FlowchartSubgraph] = [], title: String? = nil, accessibilityTitle: String? = nil,
         accessibilityDescription: String? = nil, unappliedStatementCount: Int = 0) {
        self.direction = direction
        self.nodes = nodes
        self.edges = edges
        self.subgraphs = subgraphs
        self.title = title
        self.accessibilityTitle = accessibilityTitle
        self.accessibilityDescription = accessibilityDescription
        self.unappliedStatementCount = unappliedStatementCount
    }

    /// The package's flowchart, read through its public views.
    init(_ diagram: FlowchartDiagram) {
        self.init(direction: diagram.direction, nodes: diagram.nodes, edges: diagram.edges, subgraphs: diagram.subgraphs, title: diagram.title,
                  accessibilityTitle: diagram.accessibilityTitle, accessibilityDescription: diagram.accessibilityDescription,
                  unappliedStatementCount: diagram.unappliedStatementCount)
    }

    /// The same flowchart with a width or a height that is not a number (`w: x`, which Pele's `Number` makes NaN) made
    /// a number no text writes, so that two such nodes compare equal.
    var withComparableSizes: ReferenceFlowchartDiagram {
        var comparable = self
        for index in comparable.nodes.indices {
            if comparable.nodes[index].assetAttributes.width?.isNaN == true { comparable.nodes[index].assetAttributes.width = -Self.notANumberStandIn }
            if comparable.nodes[index].assetAttributes.height?.isNaN == true { comparable.nodes[index].assetAttributes.height = -Self.notANumberStandIn }
        }
        return comparable
    }

    private static let notANumberStandIn = 1.234_567_8e300

    /// Where the labels of the two flowcharts, equal as labels, are read differently: `DiagramLabel.isReadWithoutMarkup`
    /// is not part of a label's equality, yet it changes where the label wraps. Empty when every label is read alike.
    func labelReadingDifferences(from other: ReferenceFlowchartDiagram) -> [String] {
        var differences: [String] = []
        for (index, pair) in zip(nodes, other.nodes).enumerated() where pair.0.label.isReadWithoutMarkup != pair.1.label.isReadWithoutMarkup {
            differences.append("node \(index) label read \(pair.0.label.isReadWithoutMarkup ? "without" : "with") markup")
        }
        for (index, pair) in zip(edges, other.edges).enumerated() where pair.0.label?.isReadWithoutMarkup != pair.1.label?.isReadWithoutMarkup {
            differences.append("edge \(index) label read differently")
        }
        for (index, pair) in zip(subgraphs, other.subgraphs).enumerated() where pair.0.title.isReadWithoutMarkup != pair.1.title.isReadWithoutMarkup {
            differences.append("group \(index) title read differently")
        }
        return differences
    }
}
