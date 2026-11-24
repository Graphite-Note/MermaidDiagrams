/**
 * File: ReferenceFlowchartLayoutEngine.swift
 * ------------------------------------------
 * Layer: Tests
 * Description: The 0.7.0 FlowchartLayoutEngine kept as the reference the 0.8.0 flowchart layout is checked against:
 *              lays a flowchart out in Pele's style, its groups as nested boxes and its collapsed groups as single
 *              nodes, and for a narrow container turned to run down and tightened as Pele fits it.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// Lays a flowchart out in Pele's style: each node's shape sized around its text, wrapped at 200 points; the nodes in
/// ranks along the diagram's direction, 40 points apart in a rank and 48 points between ranks; edges as S curves
/// that spread along the sides they meet; edges to a node itself as loops beside it; and the title above.
enum ReferenceFlowchartLayoutEngine {
    /// Pele's gaps; a border point of a box is 20 points from the rank next to it.
    static let spacing = LayeredSpacing(nodeSeparation: 40, edgeSeparation: 16, rankSeparation: 48, borderSeparation: 20,
                                        routing: LayeredRouting(headRoom: DiagramEdgeMark.arrowLength - 1))
    /// Pele's tight gaps (`DiagramSpacing.compact`, flowchart/render.ts `draw` with `tight`): half the nodes'
    /// separation and three quarters of the ranks'; the edges' and the border points' stay.
    static let compactSpacing = LayeredSpacing(nodeSeparation: 20, edgeSeparation: 16, rankSeparation: 36, borderSeparation: 20,
                                               routing: LayeredRouting(headRoom: DiagramEdgeMark.arrowLength - 1))
    /// Around the whole diagram.
    static let padding: CGFloat = 8
    /// The widest a line of text is before it wraps.
    static let wrappingWidth: CGFloat = 200
    /// The room an edge's text takes beyond its lines, for the patch drawn behind it.
    static let edgeTextRoom = CGSize(width: 12, height: 4)
    /// Between the title and the diagram.
    static let titleGap: CGFloat = 12

    /// `spacing` `.compact` lays it out with Pele's tight gaps and its groups' tighter padding, its title unwrapped.
    static func layout(_ diagram: FlowchartDiagram, typography: DiagramTypography, limits: MermaidDiagramLimits,
                              spacing diagramSpacing: DiagramSpacing = .standard) throws(FlowchartLayoutError) -> FlowchartLayout {
        try layout(diagram, nodeText: typography.nodeText, edgeText: typography.edgeText, font: typography.font, limits: limits, spacing: diagramSpacing)
    }

    /// The flowchart for a container `availableWidth` wide (nil for none), as Pele fits it (flowchart/render.ts): one
    /// whose own direction runs across is turned to run down (its groups keep theirs) when it does not fit a container
    /// under 640 points and turned is narrower (`turnToFit`); either way it is laid out with the tight gaps, its title
    /// wrapped to the container, when it does not fit and tight is narrower (`tighten`).
    static func layout(_ diagram: FlowchartDiagram, typography: DiagramTypography, limits: MermaidDiagramLimits,
                              availableWidth: CGFloat?) throws(FlowchartLayoutError) -> FlowchartLayout {
        func fitted(_ diagram: FlowchartDiagram) throws(FlowchartLayoutError) -> FlowchartLayout {
            try ReferenceDiagramWidthFitting.tighten(availableWidth: availableWidth, width: { (layout: FlowchartLayout) in layout.size.width }) { isTight throws(FlowchartLayoutError) in
                try layout(diagram, nodeText: typography.nodeText, edgeText: typography.edgeText, font: typography.font, limits: limits,
                           spacing: isTight ? .compact : .standard,
                           titleWidth: isTight ? ReferenceDiagramWidthFitting.titleRoom(availableWidth: availableWidth) : .greatestFiniteMagnitude)
            }
        }
        guard let turned = diagram.rootTurnedToRunDown else { return try fitted(diagram) }
        return try ReferenceDiagramWidthFitting.turnToFit(availableWidth: availableWidth, width: { (layout: FlowchartLayout) in layout.size.width }) { isDown throws(FlowchartLayoutError) in
            try fitted(isDown ? turned : diagram)
        }
    }

    /// `titleWidth`: the width the title wraps at.
    static func layout<Measurer: DiagramTextMeasuring>(_ written: FlowchartDiagram, nodeText: Measurer, edgeText: Measurer, font: DiagramFont,
                                                       limits: MermaidDiagramLimits, spacing diagramSpacing: DiagramSpacing = .standard,
                                                       titleWidth: CGFloat = .greatestFiniteMagnitude) throws(FlowchartLayoutError) -> FlowchartLayout {
        // A collapsed group is drawn as one node, what it holds left out (`ReferenceFlowchartCollapsedGroups`).
        let diagram = ReferenceFlowchartCollapsedGroups.collapsing(written)
        let isTight = diagramSpacing == .compact
        let measured = ReferenceFlowchartMeasurement(diagram: diagram, nodeText: nodeText, edgeText: edgeText, wrappingWidth: wrappingWidth)
        return try layout(diagram, measured: measured, nodeText: nodeText, font: font, limits: limits, spacing: isTight ? compactSpacing : spacing,
                          groupPadding: isTight ? ReferenceFlowchartClusterGraph.tightClusterPadding : ReferenceFlowchartClusterGraph.clusterPadding, titleWidth: titleWidth)
    }

    /// A flowchart already measured, its collapsed groups folded, laid out with `spacing`: in ranks, or in boxes when it
    /// has subgraphs. A diagram drawn as a flowchart (an agent flow) measures its nodes its own way and is laid out here.
    /// `groupPadding`: the room inside a group's box on its sides and below (Pele's `groupPad`); `titleWidth`: the width
    /// the title wraps at.
    static func layout<Measurer: DiagramTextMeasuring>(_ diagram: FlowchartDiagram, measured: ReferenceFlowchartMeasurement, nodeText: Measurer,
                                                       font: DiagramFont, limits: MermaidDiagramLimits, spacing: LayeredSpacing,
                                                       groupPadding: CGFloat = ReferenceFlowchartClusterGraph.clusterPadding,
                                                       titleWidth: CGFloat = .greatestFiniteMagnitude) throws(FlowchartLayoutError) -> FlowchartLayout {
        let title = diagram.title.map { title in DiagramTextBlock(label: DiagramLabel(title), measurer: nodeText, maximumWidth: titleWidth) }
        guard diagram.subgraphCount == 0 else {
            return try layoutInBoxes(diagram, measured: measured, nodeText: nodeText, font: font, limits: limits, spacing: spacing,
                                     groupPadding: groupPadding, title: title)
        }
        let flowAxes = ReferenceFlowchartFlowAxes(direction: diagram.direction, alongExtent: 0)
        let layeredEdgeIndices = (0..<diagram.edgeCount).filter { edgeIndex in diagram.edgeEnds(at: edgeIndex).source != diagram.edgeEnds(at: edgeIndex).target }
        let spanSide: DiagramSide = diagram.direction.layeredDirection.runsVertically ? .top : .left
        let graph = LayeredGraph(nodeSizes: measured.layoutSizes(loopSide: flowAxes.loopSide).map(flowAxes.flowSize(of:)),
                                 edges: layeredEdgeIndices.map { edgeIndex in
                                     let (source, target) = diagram.edgeEnds(at: edgeIndex)
                                     let labelSize = measured.edgeTexts[edgeIndex].map { text in
                                         flowAxes.flowSize(of: CGSize(width: text.size.width + edgeTextRoom.width,
                                                                      height: text.size.height + edgeTextRoom.height))
                                     }
                                     return LayeredEdge(source: source, target: target, minimumRankSpan: diagram.edgeMinimumRankSpan(at: edgeIndex),
                                                        labelSize: labelSize)
                                 },
                                 nodeSideSpans: (0..<diagram.nodeCount).map { node in measured.sideSpan(of: node, shape: diagram.nodeShape(at: node), side: spanSide) })
        guard let placement = ReferenceLayeredLayout.place(graph, spacing: spacing, maximumPointCount: limits.maximumLayoutPointCount) else {
            throw .tooManyLayoutPoints(limit: limits.maximumLayoutPointCount)
        }
        var page = ReferenceFlowchartPageAssembly(diagram: diagram, measured: measured,
                                         axes: ReferenceFlowchartFlowAxes(direction: diagram.direction, alongExtent: placement.extent.height))
        page.placeNodes(flowCenters: placement.nodeCenters)
        page.placeEdges(layeredEdgeIndices: layeredEdgeIndices, placement: placement)
        page.placeSelfLoops()
        let extent = flowAxes.flowIsVertical ? placement.extent : CGSize(width: placement.extent.height, height: placement.extent.width)
        return page.finished(font: font, title: title, padding: padding, titleGap: titleGap, extent: extent)
    }

    /// A flowchart with subgraphs: each group a box laid out on its own and placed in the box around it, as Pele does
    /// (`ReferenceFlowchartClusterGraph`, `ReferenceLayeredClusterLayout`).
    private static func layoutInBoxes<Measurer: DiagramTextMeasuring>(_ diagram: FlowchartDiagram, measured: ReferenceFlowchartMeasurement, nodeText: Measurer,
                                                                      font: DiagramFont, limits: MermaidDiagramLimits, spacing: LayeredSpacing,
                                                                      groupPadding: CGFloat,
                                                                      title: DiagramTextBlock?) throws(FlowchartLayoutError) -> FlowchartLayout {
        let clustered = ReferenceFlowchartClusterGraph(diagram: diagram, measured: measured, titleText: nodeText, edgeTextRoom: edgeTextRoom,
                                              groupPadding: groupPadding)
        let placement: LayeredClusterPlacement
        do {
            placement = try ReferenceLayeredClusterLayout.place(clustered.graph, spacing: spacing, maximumPointCount: limits.maximumLayoutPointCount)
        } catch {
            throw .tooManyLayoutPoints(limit: limits.maximumLayoutPointCount)
        }
        var page = ReferenceFlowchartPageAssembly(diagram: diagram, measured: measured, axes: ReferenceFlowchartFlowAxes(direction: diagram.direction, alongExtent: 0))
        page.placeNodes(clustered: clustered, placement: placement)
        page.placeEdges(clustered: clustered, placement: placement)
        page.placeSelfLoops()
        page.placeClusters(clustered: clustered, placement: placement)
        return page.finished(font: font, title: title, padding: padding, titleGap: titleGap, extent: placement.size)
    }
}
