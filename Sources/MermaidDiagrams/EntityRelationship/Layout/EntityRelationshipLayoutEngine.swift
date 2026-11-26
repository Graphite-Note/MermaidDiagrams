/**
 * File: EntityRelationshipLayoutEngine.swift
 * ------------------------------------------
 * Layer: Core
 * Description: Lays an entity relationship diagram out in Pele's style, its groups as nested boxes, from its model's
 *              records, every list it works in a list of the thread's scratch arena.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.8
 * Date: 26/11/2026
 */

import CoreGraphics

/// Lays an entity relationship diagram out in Pele's style: each entity a box sized around its name and attribute
/// table; the boxes in ranks along the diagram's direction, from the entity written first in a relationship to the
/// one written second, 48 points apart in a rank and 64 points between ranks; relationships as lines that leave
/// and meet the boxes straight and curve between, spread along the sides they meet, with a label wrapped at 200
/// points on its own rank; relationships of an entity with itself as loops beside it; and the title above. The
/// measuring and the placing work in the calling thread's arena; only the layout's own lists are made.
public enum EntityRelationshipLayoutEngine {
    /// Pele's gaps; a border point of a group's box is 24 points from the rank next to it (er/render.ts `portSep`).
    static let spacing = LayeredSpacing(nodeSeparation: 48, edgeSeparation: 20, rankSeparation: 64, borderSeparation: 24)
    /// Around the whole diagram.
    static let padding: CGFloat = 8
    /// The room a label takes beyond its lines, for the patch drawn behind it.
    static let labelRoom = CGSize(width: 12, height: 4)
    /// Between the title and the diagram.
    static let titleGap: CGFloat = 12

    public static func layout(_ diagram: EntityRelationshipDiagram, typography: DiagramTypography,
                              limits: MermaidDiagramLimits) throws(EntityRelationshipLayoutError) -> EntityRelationshipLayout {
        try layout(diagram, nameText: typography.nodeText, rowText: typography.edgeText, font: typography.font, limits: limits)
    }

    /// - Parameters:
    ///   - nameText: Measures the entities' names and the title.
    ///   - rowText: Measures the attribute rows and the labels; keys are measured from it at their own size.
    static func layout<Measurer: DiagramTextMeasuring>(_ diagram: EntityRelationshipDiagram, nameText: Measurer, rowText: Measurer, font: DiagramFont,
                                                       limits: MermaidDiagramLimits) throws(EntityRelationshipLayoutError) -> EntityRelationshipLayout {
        let measurers = EntityRelationshipTextMeasurers(name: nameText, row: rowText)
        let laidOut = DiagramScratchArena.withCurrentThread { arena -> EntityRelationshipLayout? in
            let page = diagram.model.groups.isEmpty
                ? rankedPage(diagram, measurers: measurers, maximumPointCount: limits.maximumLayoutPointCount, arena: arena)
                : pageInBoxes(diagram, measurers: measurers, titleText: nameText, maximumPointCount: limits.maximumLayoutPointCount, arena: arena)
            guard var page else { return nil }
            return page.finished(font: font, title: page.measured.title, padding: padding, titleGap: titleGap, source: diagram.model.text)
        }
        guard let laidOut else { throw .tooManyLayoutPoints(limit: limits.maximumLayoutPointCount) }
        return laidOut
    }

    /// The page of a diagram without groups: its entities and the relationships between two different entities as one
    /// flat layered graph written straight into the flat layout's spans, the placed spans read on the page; nil when the
    /// graph would need more than `maximumPointCount` nodes and passing points.
    private static func rankedPage<Measurer>(_ diagram: EntityRelationshipDiagram, measurers: EntityRelationshipTextMeasurers<Measurer>,
                                             maximumPointCount: Int, arena: DiagramScratchArena) -> EntityRelationshipPageAssembly? {
        let model = diagram.model
        let flowAxes = FlowchartFlowAxes(direction: diagram.direction, alongExtent: 0)
        let measured = EntityRelationshipMeasurement(model: model, measurers: measurers,
                                                     loopsLeaveBelow: arena.span(count: model.entities.count, repeating: !flowAxes.flowIsVertical),
                                                     title: diagram.title, arena: arena)
        let layoutSizes = measured.layoutSizes(arena: arena)
        let nodes: ScratchSpan<LayeredFlatNode> = arena.uninitializedSpan(count: layoutSizes.count)
        for node in 0..<layoutSizes.count {
            let size = flowAxes.flowSize(of: layoutSizes[node])
            nodes[node] = LayeredFlatNode(width: Double(size.across), height: Double(size.along))
        }
        let (layered, edges) = layeredEdges(of: model, measured: measured, flowAxes: flowAxes, arena: arena)
        #if DEBUG
        LayeredLayoutRecording.recordPlacement(nodes: nodes, edges: edges, spacing: spacing, maximumPointCount: maximumPointCount)
        #endif
        var points = arena.list(capacity: 4 * edges.count, of: CGPoint.self)
        guard let size = LayeredFlatLayout.layout(nodes: nodes, edges: edges, points: &points, options: LayeredFlatOptions(spacing),
                                                  maximumVertexCount: maximumPointCount, arena: arena) else {
            return nil
        }
        var page = EntityRelationshipPageAssembly(model: model, measured: measured,
                                                  axes: FlowchartFlowAxes(direction: diagram.direction, alongExtent: CGFloat(size.height)), arena: arena)
        page.placeBoxes(flowNodes: nodes)
        page.placeRelationships(layeredIndices: layered.elements, nodes: nodes, edges: edges, points: points.elements)
        page.placeSelfRelationships()
        return page
    }

    /// The relationships between two different entities, by index, and their flat layout's edges with their labels' room.
    private static func layeredEdges(of model: EntityRelationshipModel, measured: EntityRelationshipMeasurement, flowAxes: FlowchartFlowAxes,
                                     arena: DiagramScratchArena) -> (indices: ScratchList<Int>, edges: ScratchSpan<LayeredSpanEdge>) {
        var layered = arena.list(capacity: model.relationships.count, of: Int.self)
        for (index, relationship) in model.relationships.enumerated() where relationship.firstEntityIndex != relationship.secondEntityIndex {
            layered.append(index)
        }
        let edges: ScratchSpan<LayeredSpanEdge> = arena.uninitializedSpan(count: layered.count)
        for layeredIndex in 0..<layered.count {
            let index = layered[layeredIndex]
            let relationship = model.relationships[index]
            let labelSize = measured.labelSize(of: index).map { size in
                flowAxes.flowSize(of: CGSize(width: size.width + labelRoom.width, height: size.height + labelRoom.height))
            }
            edges[layeredIndex] = LayeredSpanEdge(tail: Int(relationship.firstEntityIndex), head: Int(relationship.secondEntityIndex), minimumLength: 1,
                                                  labelWidth: Double(labelSize?.across ?? 0), labelHeight: Double(labelSize?.along ?? 0),
                                                  tailOffset: 0, headOffset: 0)
        }
        return (layered, edges)
    }

    /// A diagram with groups: each a box laid out on its own and placed in the box around it, as Pele's renderer does
    /// (`EntityRelationshipClusterGraph`, `LayeredCompoundLayout`), the compound layout read where it stands in the
    /// calling thread's arena.
    private static func pageInBoxes<Measurer: DiagramTextMeasuring>(_ diagram: EntityRelationshipDiagram, measurers: EntityRelationshipTextMeasurers<Measurer>,
                                                                    titleText: Measurer, maximumPointCount: Int,
                                                                    arena: DiagramScratchArena) -> EntityRelationshipPageAssembly? {
        let model = diagram.model
        let nesting = EntityRelationshipNesting(model: model, direction: diagram.direction, arena: arena)
        let measured = EntityRelationshipMeasurement(model: model, measurers: measurers, loopsLeaveBelow: nesting.loopsLeaveBelow, title: diagram.title,
                                                     arena: arena)
        let clustered = EntityRelationshipClusterGraph(model: model, direction: diagram.direction, nesting: nesting, titleText: titleText,
                                                       layoutSizes: measured.layoutSizes(arena: arena), measured: measured, arena: arena)
        guard let compound = clustered.graph.laidOut(spacing: spacing, maximumPointCount: maximumPointCount, arena: arena) else { return nil }
        var page = EntityRelationshipPageAssembly(model: model, measured: measured, axes: FlowchartFlowAxes(direction: diagram.direction, alongExtent: 0),
                                                  arena: arena)
        page.placeBoxes(clustered: clustered, nesting: nesting, compound: compound)
        page.placeRelationships(clustered: clustered, compound: compound)
        page.placeSelfRelationships()
        page.placeSubgraphs(clustered: clustered, nesting: nesting, compound: compound)
        return page
    }
}
