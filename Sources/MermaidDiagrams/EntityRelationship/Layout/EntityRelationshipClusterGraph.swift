/**
 * File: EntityRelationshipClusterGraph.swift
 * ------------------------------------------
 * Layer: Core
 * Description: An entity relationship diagram with groups as a graph of nested boxes to lay out, as Pele's renderer makes it,
 *              written into the compound layout's spans.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 25/11/2026
 */

import CoreGraphics

/// An entity relationship diagram with `subgraph` groups as a graph of nested boxes to lay out (`LayeredCompoundGraph`),
/// as Pele's entity relationship renderer gives them to its compound layout (`er/render.ts`): each group a box with 20
/// points of room on its sides and below and its title in a band along its top, at least as wide as its title and
/// never narrower than an entity's box, running in its own direction or in that of the box around it; each entity in
/// the box of the group that holds it; an entity whose name is a group's identifier standing for the group, so that a
/// relationship to it meets the group's box; each relationship between two different ends. The nodes, boxes and edges
/// are written once, straight into the calling thread's arena.
struct EntityRelationshipClusterGraph {
    /// Pele's `GROUP_PAD`.
    static let padding: CGFloat = 20
    /// Between a title's band and the box's content.
    static let titleRoom: CGFloat = 16
    /// How much narrower than its title and two paddings a box may be.
    static let titleWidthAllowance: CGFloat = 12

    /// The entities that do not stand for a group, then the groups' boxes in group order, and the relationships laid out.
    let graph: LayeredCompoundGraph
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

    /// - Parameters:
    ///   - layoutSizes: Each entity's size in its rank.
    ///   - labelSizes: By relationship, its label's room, or nil for one without a label.
    init<Measurer: DiagramTextMeasuring>(diagram: EntityRelationshipDiagram, nesting: EntityRelationshipNesting, titleText: Measurer,
                                         layoutSizes: [CGSize], labelSizes: [CGSize?], arena: DiagramScratchArena) {
        representedSubgraphs = nesting.representedSubgraphs
        depths = nesting.depths
        let measuredTitles = diagram.subgraphs.map { subgraph in
            let title = DiagramTextBlock(label: subgraph.title, measurer: titleText, maximumWidth: .greatestFiniteMagnitude)
            return title.lineCount == 0 ? nil : title
        }
        titles = measuredTitles
        var nodeCount = 0
        for entity in diagram.entities.indices where nesting.representedSubgraphs[entity] == nil { nodeCount += 1 }
        let nodes: ScratchSpan<LayeredCompoundNode> = arena.uninitializedSpan(count: nodeCount + diagram.subgraphs.count)
        var layoutNodeIndices: [Int?] = []
        layoutNodeIndices.reserveCapacity(diagram.entities.count)
        var layoutNode = 0
        for entity in diagram.entities.indices {
            guard nesting.representedSubgraphs[entity] == nil else {
                layoutNodeIndices.append(nil)
                continue
            }
            layoutNodeIndices.append(layoutNode)
            nodes[layoutNode] = .member(size: layoutSizes[entity], box: nesting.entitySubgraphs[entity], nodeCount: nodeCount, sequence: layoutNode)
            layoutNode += 1
        }
        self.layoutNodeIndices = layoutNodeIndices
        for index in diagram.subgraphs.indices {
            nodes[nodeCount + index] = Self.box(parent: nesting.subgraphParents[index], direction: diagram.subgraphs[index].direction,
                                                title: measuredTitles[index], nodeCount: nodeCount, sequence: CGFloat(nodeCount + index))
        }
        var edges = arena.list(capacity: diagram.relationships.count, of: LayeredCompoundSpanEdge.self)
        layoutRelationshipIndices = Self.edges(of: diagram, representedSubgraphs: nesting.representedSubgraphs, layoutNodeIndices: layoutNodeIndices,
                                               labelSizes: labelSizes, nodeCount: nodeCount, into: &edges)
        graph = LayeredCompoundGraph(nodes: nodes, edges: edges.elements, nodeCount: nodeCount, direction: diagram.direction.layeredDirection)
    }

    /// For each entity, whether the box it sits in runs across, where its loops leave its box's bottom; a group's loops
    /// leave its right side whichever way it runs, as Pele hangs them.
    static func entityRunsAcross(_ nesting: EntityRelationshipNesting) -> [Bool] {
        zip(nesting.entityDirections, nesting.representedSubgraphs).map { direction, subgraph in subgraph == nil && direction.runsAcross }
    }

    /// The relationships between two different ends, with their labels' room, appended to `edges`, a group's end at its
    /// box's node after the `nodeCount` nodes; one from an entity or a group to itself loops beside its box and is not laid
    /// out. Returns the index of each relationship appended.
    private static func edges(of diagram: EntityRelationshipDiagram, representedSubgraphs: [Int?], layoutNodeIndices: [Int?], labelSizes: [CGSize?],
                              nodeCount: Int, into edges: inout ScratchList<LayeredCompoundSpanEdge>) -> [Int] {
        func end(of entity: Int) -> Int {
            if let subgraph = representedSubgraphs[entity] { return nodeCount + subgraph }
            return layoutNodeIndices[entity] ?? 0
        }
        var relationshipIndices: [Int] = []
        for (index, relationship) in diagram.relationships.enumerated() {
            let source = end(of: relationship.firstEntityIndex)
            let target = end(of: relationship.secondEntityIndex)
            guard source != target else { continue }
            edges.append(LayeredCompoundSpanEdge(source: source, target: target, minimumRankSpan: 1, labelSize: labelSizes[index]))
            relationshipIndices.append(index)
        }
        return relationshipIndices
    }

    private static func box(parent: Int?, direction: FlowchartDirection?, title: DiagramTextBlock?, nodeCount: Int, sequence: CGFloat) -> LayeredCompoundNode {
        let titleSize = title?.size ?? .zero
        let top = title == nil ? padding : titleSize.height + titleRoom
        return .box(parent: parent, nodeCount: nodeCount, direction: direction?.layeredDirection, padding: LayeredClusterPadding(side: padding, top: top, bottom: padding),
                    minimumWidth: max(titleSize.width + 2 * padding - titleWidthAllowance, EntityRelationshipBoxMeasurement.minimumWidth), sequence: sequence)
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
