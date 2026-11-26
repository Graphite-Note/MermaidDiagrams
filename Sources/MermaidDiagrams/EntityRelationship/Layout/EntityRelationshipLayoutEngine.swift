/**
 * File: EntityRelationshipLayoutEngine.swift
 * ------------------------------------------
 * Layer: Core
 * Description: Lays an entity relationship diagram out in Pele's style, its groups as nested boxes.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.7
 * Date: 25/11/2026
 */

import CoreGraphics

/// Lays an entity relationship diagram out in Pele's style: each entity a box sized around its name and attribute
/// table; the boxes in ranks along the diagram's direction, from the entity written first in a relationship to the
/// one written second, 48 points apart in a rank and 64 points between ranks; relationships as lines that leave
/// and meet the boxes straight and curve between, spread along the sides they meet, with a label wrapped at 200
/// points on its own rank; relationships of an entity with itself as loops beside it; and the title above.
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
        let flowAxes = FlowchartFlowAxes(direction: diagram.direction, alongExtent: 0)
        guard diagram.subgraphs.isEmpty else {
            return try layoutInBoxes(diagram, nameText: nameText, rowText: rowText, font: font, limits: limits)
        }
        let measured = EntityRelationshipMeasurement(diagram: diagram, measurers: EntityRelationshipTextMeasurers(name: nameText, row: rowText),
                                                     loopsLeaveBelow: Array(repeating: !flowAxes.flowIsVertical, count: diagram.entities.count))
        let page = DiagramScratchArena.withCurrentThread { arena in
            rankedPage(diagram, measured: measured, flowAxes: flowAxes, maximumPointCount: limits.maximumLayoutPointCount, arena: arena)
        }
        guard var page else { throw .tooManyLayoutPoints(limit: limits.maximumLayoutPointCount) }
        let title = diagram.title.map { title in DiagramTextBlock(label: DiagramLabel(title), measurer: nameText, maximumWidth: .greatestFiniteMagnitude) }
        return page.finished(font: font, title: title, padding: padding, titleGap: titleGap)
    }

    /// The page of a diagram without groups: its entities and the relationships between two different entities as one
    /// flat layered graph written straight into the flat layout's spans, the placed spans read on the page; nil when the
    /// graph would need more than `maximumPointCount` nodes and passing points.
    private static func rankedPage(_ diagram: EntityRelationshipDiagram, measured: EntityRelationshipMeasurement, flowAxes: FlowchartFlowAxes,
                                   maximumPointCount: Int, arena: DiagramScratchArena) -> EntityRelationshipPageAssembly? {
        let layoutSizes = measured.layoutSizes()
        let nodes: ScratchSpan<LayeredFlatNode> = arena.uninitializedSpan(count: layoutSizes.count)
        for node in 0..<layoutSizes.count {
            let size = flowAxes.flowSize(of: layoutSizes[node])
            nodes[node] = LayeredFlatNode(width: Double(size.across), height: Double(size.along))
        }
        var layered = arena.list(capacity: diagram.relationships.count, of: Int.self)
        for (index, relationship) in diagram.relationships.enumerated() where relationship.firstEntityIndex != relationship.secondEntityIndex {
            layered.append(index)
        }
        let edges: ScratchSpan<LayeredSpanEdge> = arena.uninitializedSpan(count: layered.count)
        for layeredIndex in 0..<layered.count {
            let index = layered[layeredIndex]
            let relationship = diagram.relationships[index]
            let labelSize = measured.labels[index].map { label in
                flowAxes.flowSize(of: CGSize(width: label.size.width + labelRoom.width, height: label.size.height + labelRoom.height))
            }
            edges[layeredIndex] = LayeredSpanEdge(tail: relationship.firstEntityIndex, head: relationship.secondEntityIndex, minimumLength: 1,
                                                  labelWidth: Double(labelSize?.across ?? 0), labelHeight: Double(labelSize?.along ?? 0),
                                                  tailOffset: 0, headOffset: 0)
        }
        #if DEBUG
        LayeredLayoutRecording.recordPlacement(nodes: nodes, edges: edges, spacing: spacing, maximumPointCount: maximumPointCount)
        #endif
        var points = arena.list(capacity: 4 * edges.count, of: CGPoint.self)
        guard let size = LayeredFlatLayout.layout(nodes: nodes, edges: edges, points: &points, options: LayeredFlatOptions(spacing),
                                                  maximumVertexCount: maximumPointCount, arena: arena) else {
            return nil
        }
        var page = EntityRelationshipPageAssembly(diagram: diagram, measured: measured,
                                                  axes: FlowchartFlowAxes(direction: diagram.direction, alongExtent: CGFloat(size.height)))
        page.placeBoxes(flowNodes: nodes)
        page.placeRelationships(layeredIndices: layered.elements, nodes: nodes, edges: edges, points: points.elements)
        page.placeSelfRelationships()
        return page
    }

    /// A diagram with groups: each a box laid out on its own and placed in the box around it, as Pele's renderer does
    /// (`EntityRelationshipClusterGraph`, `LayeredCompoundLayout`), the compound layout read where it stands in the
    /// calling thread's arena.
    private static func layoutInBoxes<Measurer: DiagramTextMeasuring>(_ diagram: EntityRelationshipDiagram, nameText: Measurer, rowText: Measurer,
                                                                      font: DiagramFont,
                                                                      limits: MermaidDiagramLimits) throws(EntityRelationshipLayoutError) -> EntityRelationshipLayout {
        let nesting = EntityRelationshipNesting(diagram: diagram)
        let measured = EntityRelationshipMeasurement(diagram: diagram, measurers: EntityRelationshipTextMeasurers(name: nameText, row: rowText),
                                                     loopsLeaveBelow: EntityRelationshipClusterGraph.entityRunsAcross(nesting))
        let labelSizes = measured.labels.map { label in
            label.map { label in CGSize(width: label.size.width + labelRoom.width, height: label.size.height + labelRoom.height) }
        }
        let page = DiagramScratchArena.withCurrentThread { arena -> EntityRelationshipPageAssembly? in
            let clustered = EntityRelationshipClusterGraph(diagram: diagram, nesting: nesting, titleText: nameText, layoutSizes: measured.layoutSizes(),
                                                           labelSizes: labelSizes, arena: arena)
            guard let compound = clustered.graph.laidOut(spacing: spacing, maximumPointCount: limits.maximumLayoutPointCount, arena: arena) else {
                return nil
            }
            var page = EntityRelationshipPageAssembly(diagram: diagram, measured: measured, axes: FlowchartFlowAxes(direction: diagram.direction, alongExtent: 0))
            page.placeBoxes(clustered: clustered, compound: compound)
            page.placeRelationships(clustered: clustered, compound: compound)
            page.placeSelfRelationships()
            page.placeSubgraphs(clustered: clustered, compound: compound)
            return page
        }
        guard var page else { throw .tooManyLayoutPoints(limit: limits.maximumLayoutPointCount) }
        let title = diagram.title.map { title in DiagramTextBlock(label: DiagramLabel(title), measurer: nameText, maximumWidth: .greatestFiniteMagnitude) }
        return page.finished(font: font, title: title, padding: padding, titleGap: titleGap)
    }
}
