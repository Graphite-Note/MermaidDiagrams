/**
 * File: EntityRelationshipClusterGraph.swift
 * ------------------------------------------
 * Layer: Core
 * Description: An entity relationship diagram with groups as a graph of nested boxes to lay out, as Pele's renderer makes it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// An entity relationship diagram with `subgraph` groups as a graph of nested boxes to lay out (`LayeredClusterLayout`),
/// as Pele's entity relationship renderer gives them to its compound layout (`er/render.ts`): each group a box with 20
/// points of room on its sides and below and its title in a band along its top, at least as wide as its title and
/// never narrower than an entity's box, running in its own direction or in that of the box around it; each entity in
/// the box of the group that holds it; an entity whose name is a group's identifier standing for the group, so that a
/// relationship to it meets the group's box; each relationship between two different ends.
struct EntityRelationshipClusterGraph {
    /// Pele's `GROUP_PAD`.
    static let padding: CGFloat = 20
    /// Between a title's band and the box's content.
    static let titleRoom: CGFloat = 16
    /// How much narrower than its title and two paddings a box may be.
    static let titleWidthAllowance: CGFloat = 12

    let graph: LayeredClusterGraph
    /// For each entity, its node in `graph`, or nil for an entity that stands for a group.
    let layoutNodeIndices: [Int?]
    /// For each entity, the group it stands for, or nil.
    let representedSubgraphs: [Int?]
    /// The relationships laid out, in the order of `graph.edges`.
    let layoutRelationshipIndices: [Int]
    /// Each group's title, measured, or nil for one without.
    let titles: [DiagramTextBlock?]
    /// How many group boxes each group's box is inside.
    let depths: [Int]
    /// For each entity, whether the box it sits in runs across, where its loops leave its box's bottom.
    let entityRunsAcross: [Bool]

    /// Fails for a relationship from a group to itself, whose loop outside the box is not drawn yet.
    init<Measurer: DiagramTextMeasuring>(diagram: EntityRelationshipDiagram, titleText: Measurer) throws(EntityRelationshipLayoutError) {
        let nesting = EntityRelationshipNesting(diagram: diagram)
        representedSubgraphs = nesting.representedSubgraphs
        depths = nesting.depths
        entityRunsAcross = nesting.entityDirections.map(\.runsAcross)
        let measuredTitles = diagram.subgraphs.map { subgraph in
            let title = DiagramTextBlock(label: subgraph.title, measurer: titleText, maximumWidth: .greatestFiniteMagnitude)
            return title.lines.isEmpty ? nil : title
        }
        titles = measuredTitles
        var layoutNodeIndices: [Int?] = []
        var nodeClusters: [Int?] = []
        for entity in diagram.entities.indices {
            guard nesting.representedSubgraphs[entity] == nil else {
                layoutNodeIndices.append(nil)
                continue
            }
            layoutNodeIndices.append(nodeClusters.count)
            nodeClusters.append(nesting.entitySubgraphs[entity])
        }
        self.layoutNodeIndices = layoutNodeIndices
        let clusters = diagram.subgraphs.indices.map { index in
            Self.cluster(parent: nesting.subgraphParents[index], direction: diagram.subgraphs[index].direction, title: measuredTitles[index])
        }
        let edges = try Self.edges(of: diagram, representedSubgraphs: nesting.representedSubgraphs, layoutNodeIndices: layoutNodeIndices)
        layoutRelationshipIndices = edges.relationshipIndices
        graph = LayeredClusterGraph(nodeSizes: [], nodeClusters: nodeClusters, clusters: clusters, edges: edges.layout,
                                    direction: diagram.direction.layeredDirection)
    }

    /// The relationships between two different ends; one from a group to itself fails, one from an entity to itself loops
    /// beside it and is not laid out.
    private static func edges(of diagram: EntityRelationshipDiagram, representedSubgraphs: [Int?],
                              layoutNodeIndices: [Int?]) throws(EntityRelationshipLayoutError) -> (layout: [LayeredClusterEdge], relationshipIndices: [Int]) {
        func end(of entity: Int) -> LayeredClusterEnd {
            if let subgraph = representedSubgraphs[entity] { return .cluster(subgraph) }
            return .node(layoutNodeIndices[entity] ?? 0)
        }
        var edges: [LayeredClusterEdge] = []
        var relationshipIndices: [Int] = []
        for (index, relationship) in diagram.relationships.enumerated() {
            let source = end(of: relationship.firstEntityIndex)
            let target = end(of: relationship.secondEntityIndex)
            guard source != target else {
                if case .cluster = source { throw .subgraphsNotLaidOut }
                continue
            }
            edges.append(LayeredClusterEdge(source: source, target: target, minimumRankSpan: 1, labelSize: nil))
            relationshipIndices.append(index)
        }
        return (edges, relationshipIndices)
    }

    /// The graph with each entity's size in its rank and each relationship's label's room.
    func sized(nodeSizes: [CGSize], labelSizes: [CGSize?]) -> LayeredClusterGraph {
        var sized = graph
        sized.nodeSizes = nodeSizes
        for (position, index) in layoutRelationshipIndices.enumerated() { sized.edges[position].labelSize = labelSizes[index] }
        return sized
    }

    private static func cluster(parent: Int?, direction: FlowchartDirection?, title: DiagramTextBlock?) -> LayeredCluster {
        let titleSize = title?.size ?? .zero
        let top = title == nil ? padding : titleSize.height + titleRoom
        return LayeredCluster(parent: parent, direction: direction?.layeredDirection, padding: LayeredClusterPadding(side: padding, top: top, bottom: padding),
                              minimumWidth: max(titleSize.width + 2 * padding - titleWidthAllowance, EntityRelationshipBoxMeasurement.minimumWidth))
    }
}

/// Where each entity and group of an entity relationship diagram sits among its groups, and which way each box runs.
struct EntityRelationshipNesting {
    /// For each entity, the group directly holding it, or nil.
    let entitySubgraphs: [Int?]
    /// For each entity, the group whose identifier is its name, or nil.
    let representedSubgraphs: [Int?]
    /// For each group, the group directly holding it, or nil.
    let subgraphParents: [Int?]
    let depths: [Int]
    /// For each entity, the direction of the box it is in: its nearest group's that sets one, else the diagram's.
    let entityDirections: [FlowchartDirection]

    init(diagram: EntityRelationshipDiagram) {
        var entitySubgraphs = [Int?](repeating: nil, count: diagram.entities.count)
        var subgraphParents = [Int?](repeating: nil, count: diagram.subgraphs.count)
        var indexByIdentifier: [String: Int] = [:]
        for (index, subgraph) in diagram.subgraphs.enumerated() {
            for entity in subgraph.entityIndices where entitySubgraphs[entity] == nil { entitySubgraphs[entity] = index }
            for child in subgraph.childSubgraphIndices where subgraphParents[child] == nil { subgraphParents[child] = index }
            if indexByIdentifier[subgraph.identifier] == nil { indexByIdentifier[subgraph.identifier] = index }
        }
        self.entitySubgraphs = entitySubgraphs
        self.subgraphParents = subgraphParents
        representedSubgraphs = diagram.entities.map { entity in indexByIdentifier[entity.identifier] }
        // Groups can hold each other; each walk up is bounded by the number of groups.
        func ancestors(of subgraph: Int?) -> [Int] {
            var chain: [Int] = []
            var current = subgraph
            while let index = current, chain.count <= diagram.subgraphs.count {
                chain.append(index)
                current = subgraphParents[index]
            }
            return chain
        }
        depths = diagram.subgraphs.indices.map { index in ancestors(of: index).count - 1 }
        entityDirections = entitySubgraphs.map { subgraph in
            ancestors(of: subgraph).lazy.compactMap { index in diagram.subgraphs[index].direction }.first ?? diagram.direction
        }
    }
}
