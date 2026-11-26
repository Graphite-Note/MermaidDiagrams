/**
 * File: EntityRelationshipClusterGraph.swift
 * ------------------------------------------
 * Layer: Core
 * Description: An entity relationship diagram with groups as a graph of nested boxes to lay out, as Pele's renderer makes it,
 *              written into the compound layout's spans, and where each entity and group sits among the groups, read from
 *              the model's records into spans of the thread's arena.
 *
 * Authors: Bahey Shalash
 * Version: 0.5
 * Date: 26/11/2026
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
    /// For each entity, its node in `graph`, or -1 for an entity that stands for a group.
    let layoutNodeIndices: ScratchSpan<Int32>
    /// The relationships laid out, in the order of `graph.edges`.
    let layoutRelationshipIndices: ScratchSpan<Int>
    /// Each group's title, measured, or nil for one without.
    let titles: [DiagramTextBlock?]

    /// - Parameters:
    ///   - layoutSizes: Each entity's size in its rank.
    ///   - measured: The relationships' labels, whose room the edges take.
    init<Measurer: DiagramTextMeasuring>(model: EntityRelationshipModel, direction: FlowchartDirection, nesting: EntityRelationshipNesting,
                                         titleText: Measurer, layoutSizes: ScratchSpan<CGSize>, measured: EntityRelationshipMeasurement,
                                         arena: DiagramScratchArena) {
        let measuredTitles = model.groups.map { group in
            let title = DiagramTextBlock(label: model.labels[Int(group.title)], measurer: titleText, maximumWidth: .greatestFiniteMagnitude)
            return title.lineCount == 0 ? nil : title
        }
        titles = measuredTitles
        var nodeCount = 0
        for entity in 0..<model.entities.count where nesting.representedSubgraphs[entity] < 0 { nodeCount += 1 }
        let nodes: ScratchSpan<LayeredCompoundNode> = arena.uninitializedSpan(count: nodeCount + model.groups.count)
        layoutNodeIndices = Self.writeNodes(model: model, nesting: nesting, titles: measuredTitles, layoutSizes: layoutSizes, nodeCount: nodeCount,
                                            into: nodes, arena: arena)
        var edges = arena.list(capacity: model.relationships.count, of: LayeredCompoundSpanEdge.self)
        var relationshipIndices = arena.list(capacity: model.relationships.count, of: Int.self)
        let layoutNodeIndices = layoutNodeIndices
        for (index, relationship) in model.relationships.enumerated() {
            let source = Self.end(of: Int(relationship.firstEntityIndex), nesting: nesting, layoutNodeIndices: layoutNodeIndices, nodeCount: nodeCount)
            let target = Self.end(of: Int(relationship.secondEntityIndex), nesting: nesting, layoutNodeIndices: layoutNodeIndices, nodeCount: nodeCount)
            guard source != target else { continue }
            let labelSize = measured.labelSize(of: index).map { size in
                CGSize(width: size.width + EntityRelationshipLayoutEngine.labelRoom.width, height: size.height + EntityRelationshipLayoutEngine.labelRoom.height)
            }
            edges.append(LayeredCompoundSpanEdge(source: source, target: target, minimumRankSpan: 1, labelSize: labelSize))
            relationshipIndices.append(index)
        }
        layoutRelationshipIndices = relationshipIndices.elements
        graph = LayeredCompoundGraph(nodes: nodes, edges: edges.elements, nodeCount: nodeCount, direction: direction.layeredDirection)
    }

    /// The entities that stand for no group, in order, then the groups' boxes, written into `nodes`; returns each
    /// entity's node, -1 for one that stands for a group.
    private static func writeNodes(model: EntityRelationshipModel, nesting: EntityRelationshipNesting, titles: [DiagramTextBlock?],
                                   layoutSizes: ScratchSpan<CGSize>, nodeCount: Int, into nodes: ScratchSpan<LayeredCompoundNode>,
                                   arena: DiagramScratchArena) -> ScratchSpan<Int32> {
        let layoutNodeIndices: ScratchSpan<Int32> = arena.uninitializedSpan(count: model.entities.count)
        var layoutNode = 0
        for entity in 0..<model.entities.count {
            guard nesting.representedSubgraphs[entity] < 0 else {
                layoutNodeIndices[entity] = -1
                continue
            }
            layoutNodeIndices[entity] = Int32(layoutNode)
            let box = nesting.entitySubgraphs[entity]
            nodes[layoutNode] = .member(size: layoutSizes[entity], box: box >= 0 ? Int(box) : nil, nodeCount: nodeCount, sequence: layoutNode)
            layoutNode += 1
        }
        for index in model.groups.indices {
            let parent = nesting.subgraphParents[index]
            nodes[nodeCount + index] = box(parent: parent >= 0 ? Int(parent) : nil, direction: model.groups[index].direction, title: titles[index],
                                           nodeCount: nodeCount, sequence: CGFloat(nodeCount + index))
        }
        return layoutNodeIndices
    }

    /// The node a relationship's end meets: its entity's, or the box of the group it stands for, after the `nodeCount`
    /// nodes. A relationship from an entity or a group to itself loops beside its box and is not laid out.
    private static func end(of entity: Int, nesting: EntityRelationshipNesting, layoutNodeIndices: ScratchSpan<Int32>, nodeCount: Int) -> Int {
        let subgraph = nesting.representedSubgraphs[entity]
        if subgraph >= 0 { return nodeCount + Int(subgraph) }
        return max(Int(layoutNodeIndices[entity]), 0)
    }

    private static func box(parent: Int?, direction: FlowchartDirection?, title: DiagramTextBlock?, nodeCount: Int, sequence: CGFloat) -> LayeredCompoundNode {
        let titleSize = title?.size ?? .zero
        let top = title == nil ? padding : titleSize.height + titleRoom
        return .box(parent: parent, nodeCount: nodeCount, direction: direction?.layeredDirection, padding: LayeredClusterPadding(side: padding, top: top, bottom: padding),
                    minimumWidth: max(titleSize.width + 2 * padding - titleWidthAllowance, EntityRelationshipBoxMeasurement.minimumWidth), sequence: sequence)
    }
}

/// Where each entity and group of an entity relationship diagram sits among its groups, and which way each box runs:
/// spans of the thread's arena, -1 for none.
struct EntityRelationshipNesting {
    /// For each entity, the group directly holding it.
    let entitySubgraphs: ScratchSpan<Int32>
    /// For each entity, the group whose identifier is its name.
    let representedSubgraphs: ScratchSpan<Int32>
    /// For each group, the group directly holding it.
    let subgraphParents: ScratchSpan<Int32>
    let depths: ScratchSpan<Int>
    /// For each entity, whether its loops leave its box's bottom: the box it sits in runs across, and it stands for no
    /// group, whose loops leave its right side whichever way it runs, as Pele hangs them.
    let loopsLeaveBelow: ScratchSpan<Bool>

    init(model: EntityRelationshipModel, direction: FlowchartDirection, arena: DiagramScratchArena) {
        let entitySubgraphs = arena.span(count: model.entities.count, repeating: Int32(-1))
        let subgraphParents = arena.span(count: model.groups.count, repeating: Int32(-1))
        for (index, group) in model.groups.enumerated() {
            for position in group.entityIndices where entitySubgraphs[Int(model.members[position])] < 0 {
                entitySubgraphs[Int(model.members[position])] = Int32(index)
            }
            for position in group.childIndices where subgraphParents[Int(model.members[position])] < 0 {
                subgraphParents[Int(model.members[position])] = Int32(index)
            }
        }
        self.entitySubgraphs = entitySubgraphs
        self.subgraphParents = subgraphParents
        let representedSubgraphs = arena.span(count: model.entities.count, repeating: Int32(-1))
        for entity in 0..<min(model.entities.count, model.representedGroups.count) { representedSubgraphs[entity] = model.representedGroups[entity] }
        self.representedSubgraphs = representedSubgraphs
        depths = Self.depths(of: model, parents: subgraphParents, arena: arena)
        let loopsLeaveBelow = Self.loopsLeaveBelow(model: model, direction: direction, entitySubgraphs: entitySubgraphs, parents: subgraphParents,
                                                   representedSubgraphs: representedSubgraphs, arena: arena)
        self.loopsLeaveBelow = loopsLeaveBelow
    }

    /// How many group boxes each group's box is inside. Groups can hold each other; each walk up is bounded by the number
    /// of groups.
    private static func depths(of model: EntityRelationshipModel, parents: ScratchSpan<Int32>, arena: DiagramScratchArena) -> ScratchSpan<Int> {
        let depths: ScratchSpan<Int> = arena.uninitializedSpan(count: model.groups.count)
        for index in 0..<model.groups.count {
            var length = 0
            var current = Int32(index)
            while current >= 0, length <= model.groups.count {
                length += 1
                current = parents[Int(current)]
            }
            depths[index] = length - 1
        }
        return depths
    }

    /// For each entity, whether the box it sits in (its nearest group's that sets a direction, else the diagram's) runs
    /// across, and it stands for no group.
    private static func loopsLeaveBelow(model: EntityRelationshipModel, direction: FlowchartDirection, entitySubgraphs: ScratchSpan<Int32>,
                                        parents: ScratchSpan<Int32>, representedSubgraphs: ScratchSpan<Int32>, arena: DiagramScratchArena) -> ScratchSpan<Bool> {
        let loopsLeaveBelow: ScratchSpan<Bool> = arena.uninitializedSpan(count: model.entities.count)
        for entity in 0..<model.entities.count {
            var boxDirection = direction
            var current = entitySubgraphs[entity]
            var length = 0
            while current >= 0, length <= model.groups.count {
                if let groupDirection = model.groups[Int(current)].direction {
                    boxDirection = groupDirection
                    break
                }
                length += 1
                current = parents[Int(current)]
            }
            loopsLeaveBelow[entity] = representedSubgraphs[entity] < 0 && boxDirection.runsAcross
        }
        return loopsLeaveBelow
    }
}
