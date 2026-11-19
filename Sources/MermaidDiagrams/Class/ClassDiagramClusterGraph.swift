/**
 * File: ClassDiagramClusterGraph.swift
 * ------------------------------------
 * Layer: Core
 * Description: A class diagram with namespaces as a graph of nested boxes to lay out, as Pele's class renderer makes it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// A class diagram with namespaces as a graph of nested boxes to lay out (`LayeredClusterLayout`), as Pele's class
/// renderer gives them to its compound layout (`class/render.ts`): each namespace that holds something a box with 20
/// points of room on its sides and below and its title in a band along its top, at least as wide as its title, and wider
/// by the title and 24 points (at most 240) where a relation crosses into it, so that the title can sit beside the line;
/// an empty namespace a box at least 80 points wide around its title; each class in its namespace's box, an interface
/// in its class's and a note at the top level; each relation between two different nodes.
struct ClassDiagramClusterGraph {
    /// Pele's `GROUP_PAD`.
    static let padding: CGFloat = 20
    /// Between the title's band and the box's content: Pele's 16 below a title.
    static let titleRoom: CGFloat = 16
    /// How much narrower than its title and two paddings a box may be.
    static let titleWidthAllowance: CGFloat = 12
    /// Where a relation crosses into a namespace, the box is wider by its title and this, up to `crossedWidthLimit`.
    static let crossedExtraWidth: CGFloat = 24
    static let crossedWidthLimit: CGFloat = 240
    /// The narrowest an empty namespace's box is.
    static let emptyMinimumWidth: CGFloat = 80

    let graph: LayeredClusterGraph
    /// The measurement's edges laid out, in the order of `graph.edges`.
    let layoutEdgeIndices: [Int]
    /// Each namespace's title, measured, or nil for one without.
    let titles: [DiagramTextBlock?]
    /// How many namespace boxes each namespace's box is inside.
    let depths: [Int]

    init<Measurer: DiagramTextMeasuring>(tree: ClassDiagramNamespaceTree, measured: ClassDiagramMeasurement, layoutSizes: [CGSize],
                                         direction: FlowchartDirection, titleText: Measurer, edgeTextRoom: CGSize) {
        let measuredTitles = tree.namespaces.map { namespace in
            let title = DiagramTextBlock(label: namespace.title, measurer: titleText, maximumWidth: .greatestFiniteMagnitude)
            return title.lines.isEmpty ? nil : title
        }
        titles = measuredTitles
        let nodeClusters = Self.nodeClusters(tree: tree, measured: measured)
        let crossed = Self.crossedNamespaces(tree: tree, measured: measured, nodeClusters: nodeClusters)
        var holdsSomething = [Bool](repeating: false, count: tree.namespaces.count)
        for cluster in nodeClusters.compactMap({ cluster in cluster }) { holdsSomething[cluster] = true }
        for namespace in tree.namespaces { if let parent = namespace.parent { holdsSomething[parent] = true } }
        let clusters = tree.namespaces.indices.map { index in
            Self.cluster(parent: tree.namespaces[index].parent, title: measuredTitles[index], isEmpty: !holdsSomething[index], isCrossed: crossed[index])
        }
        var depths = [Int](repeating: 0, count: tree.namespaces.count)
        // A namespace is made before the namespaces inside it, so its depth is known first.
        for (index, namespace) in tree.namespaces.enumerated() { depths[index] = namespace.parent.map { depths[$0] + 1 } ?? 0 }
        self.depths = depths
        var edges: [LayeredClusterEdge] = []
        var layoutEdgeIndices: [Int] = []
        for (edgeIndex, edge) in measured.edges.enumerated() where !edge.isSelfLoop {
            let labelSize = edge.text.map { text in CGSize(width: text.size.width + edgeTextRoom.width, height: text.size.height + edgeTextRoom.height) }
            edges.append(LayeredClusterEdge(source: .node(edge.source), target: .node(edge.target), minimumRankSpan: 1, labelSize: labelSize))
            layoutEdgeIndices.append(edgeIndex)
        }
        self.layoutEdgeIndices = layoutEdgeIndices
        graph = LayeredClusterGraph(nodeSizes: layoutSizes, nodeClusters: nodeClusters, clusters: clusters, edges: edges, direction: direction.layeredDirection)
    }

    /// The box each node sits in: a class's namespace, an interface its class's, a note none.
    private static func nodeClusters(tree: ClassDiagramNamespaceTree, measured: ClassDiagramMeasurement) -> [Int?] {
        var clusters = measured.nodes.map { kind -> Int? in
            guard case .classBox(let boxIndex) = kind, boxIndex < tree.classNamespaces.count else { return nil }
            return tree.classNamespaces[boxIndex]
        }
        // An interface stays beside the class at the relation's other end.
        for edge in measured.edges {
            if case .interface = measured.nodes[edge.target] { clusters[edge.target] = clusters[edge.source] }
            if case .interface = measured.nodes[edge.source] { clusters[edge.source] = clusters[edge.target] }
        }
        return clusters
    }

    /// The namespaces a relation crosses into: every box around either end, up to the first both share.
    private static func crossedNamespaces(tree: ClassDiagramNamespaceTree, measured: ClassDiagramMeasurement, nodeClusters: [Int?]) -> [Bool] {
        var crossed = [Bool](repeating: false, count: tree.namespaces.count)
        for edge in measured.edges where !edge.isSelfLoop && nodeClusters[edge.source] != nodeClusters[edge.target] {
            for start in [nodeClusters[edge.source], nodeClusters[edge.target]] {
                var current = start
                while let namespace = current, !crossed[namespace] {
                    crossed[namespace] = true
                    current = tree.namespaces[namespace].parent
                }
            }
        }
        return crossed
    }

    private static func cluster(parent: Int?, title: DiagramTextBlock?, isEmpty: Bool, isCrossed: Bool) -> LayeredCluster {
        let titleSize = title?.size ?? .zero
        guard !isEmpty else {
            // Pele draws an empty namespace as a node of its own: its title with 20 points around it, 80 points wide at least.
            return LayeredCluster(parent: parent, direction: nil,
                                  padding: LayeredClusterPadding(side: padding, top: titleSize.height + padding, bottom: padding),
                                  minimumWidth: max(titleSize.width + 2 * padding, emptyMinimumWidth))
        }
        let top = title == nil ? padding : titleSize.height + titleRoom
        let crossedWidth = isCrossed ? min(titleSize.width + crossedExtraWidth, crossedWidthLimit) : 0
        return LayeredCluster(parent: parent, direction: nil, padding: LayeredClusterPadding(side: padding, top: top, bottom: padding),
                              minimumWidth: titleSize.width + 2 * padding - titleWidthAllowance + crossedWidth)
    }
}
