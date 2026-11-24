/**
 * File: ReferenceEntityRelationshipLayoutEngine.swift
 * ---------------------------------------------------
 * Layer: Tests
 * Description: The 0.7.0 EntityRelationshipLayoutEngine kept as the reference the 0.8.0 layout is checked against:
 *              lays an entity relationship diagram out in Pele's style, its groups as nested boxes.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// Lays an entity relationship diagram out in Pele's style: each entity a box sized around its name and attribute
/// table; the boxes in ranks along the diagram's direction, from the entity written first in a relationship to the
/// one written second, 48 points apart in a rank and 64 points between ranks; relationships as lines that leave
/// and meet the boxes straight and curve between, spread along the sides they meet, with a label wrapped at 200
/// points on its own rank; relationships of an entity with itself as loops beside it; and the title above.
enum ReferenceEntityRelationshipLayoutEngine {
    /// Pele's gaps; a border point of a group's box is 24 points from the rank next to it (er/render.ts `portSep`).
    static let spacing = LayeredSpacing(nodeSeparation: 48, edgeSeparation: 20, rankSeparation: 64, borderSeparation: 24)
    /// Around the whole diagram.
    static let padding: CGFloat = 8
    /// The room a label takes beyond its lines, for the patch drawn behind it.
    static let labelRoom = CGSize(width: 12, height: 4)
    /// Between the title and the diagram.
    static let titleGap: CGFloat = 12

    static func layout(_ diagram: EntityRelationshipDiagram, typography: DiagramTypography,
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
        let measured = ReferenceEntityRelationshipMeasurement(diagram: diagram, measurers: ReferenceEntityRelationshipTextMeasurers(name: nameText, row: rowText),
                                                     loopsLeaveBelow: Array(repeating: !flowAxes.flowIsVertical, count: diagram.entities.count))
        let layeredIndices = diagram.relationships.indices.filter { index in
            diagram.relationships[index].firstEntityIndex != diagram.relationships[index].secondEntityIndex
        }
        let graph = LayeredGraph(nodeSizes: measured.layoutSizes().map(flowAxes.flowSize(of:)), edges: layeredIndices.map { index in
            let relationship = diagram.relationships[index]
            let labelSize = measured.labels[index].map { label in
                flowAxes.flowSize(of: CGSize(width: label.size.width + labelRoom.width, height: label.size.height + labelRoom.height))
            }
            return LayeredEdge(source: relationship.firstEntityIndex, target: relationship.secondEntityIndex, minimumRankSpan: 1, labelSize: labelSize)
        })
        guard let placement = LayeredLayout.place(graph, spacing: spacing, maximumPointCount: limits.maximumLayoutPointCount) else {
            throw .tooManyLayoutPoints(limit: limits.maximumLayoutPointCount)
        }
        var page = ReferenceEntityRelationshipPageAssembly(diagram: diagram, measured: measured,
                                                  axes: FlowchartFlowAxes(direction: diagram.direction, alongExtent: placement.extent.height))
        page.placeBoxes(flowCenters: placement.nodeCenters)
        page.placeRelationships(layeredIndices: layeredIndices, placement: placement)
        page.placeSelfRelationships()
        let title = diagram.title.map { title in DiagramTextBlock(label: DiagramLabel(title), measurer: nameText, maximumWidth: .greatestFiniteMagnitude) }
        return page.finished(font: font, title: title, padding: padding, titleGap: titleGap)
    }

    /// A diagram with groups: each a box laid out on its own and placed in the box around it, as Pele's renderer does
    /// (`ReferenceEntityRelationshipClusterGraph`, `LayeredClusterLayout`).
    private static func layoutInBoxes<Measurer: DiagramTextMeasuring>(_ diagram: EntityRelationshipDiagram, nameText: Measurer, rowText: Measurer,
                                                                      font: DiagramFont,
                                                                      limits: MermaidDiagramLimits) throws(EntityRelationshipLayoutError) -> EntityRelationshipLayout {
        let clustered = ReferenceEntityRelationshipClusterGraph(diagram: diagram, titleText: nameText)
        let measured = ReferenceEntityRelationshipMeasurement(diagram: diagram, measurers: ReferenceEntityRelationshipTextMeasurers(name: nameText, row: rowText),
                                                     loopsLeaveBelow: clustered.entityRunsAcross)
        let sizes = measured.layoutSizes()
        let nodeSizes = diagram.entities.indices.compactMap { entity in clustered.layoutNodeIndices[entity].map { _ in sizes[entity] } }
        let labelSizes = measured.labels.map { label in
            label.map { label in CGSize(width: label.size.width + labelRoom.width, height: label.size.height + labelRoom.height) }
        }
        let placement: LayeredClusterPlacement
        do {
            placement = try LayeredClusterLayout.place(clustered.sized(nodeSizes: nodeSizes, labelSizes: labelSizes), spacing: spacing,
                                                       maximumPointCount: limits.maximumLayoutPointCount)
        } catch {
            throw .tooManyLayoutPoints(limit: limits.maximumLayoutPointCount)
        }
        var page = ReferenceEntityRelationshipPageAssembly(diagram: diagram, measured: measured, axes: FlowchartFlowAxes(direction: diagram.direction, alongExtent: 0))
        page.placeBoxes(clustered: clustered, placement: placement)
        page.placeRelationships(clustered: clustered, placement: placement)
        page.placeSelfRelationships()
        page.placeSubgraphs(clustered: clustered, placement: placement)
        let title = diagram.title.map { title in DiagramTextBlock(label: DiagramLabel(title), measurer: nameText, maximumWidth: .greatestFiniteMagnitude) }
        return page.finished(font: font, title: title, padding: padding, titleGap: titleGap)
    }
}
