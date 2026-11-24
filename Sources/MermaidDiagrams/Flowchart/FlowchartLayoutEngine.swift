/**
 * File: FlowchartLayoutEngine.swift
 * ---------------------------------
 * Layer: Core
 * Description: Lays a flowchart out in Pele's style, its groups as nested boxes and its collapsed groups as single nodes,
 *              and for a narrow container turned to run down and tightened as Pele fits it.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.7
 * Date: 24/11/2026
 */

import CoreGraphics

/// Lays a flowchart out in Pele's style: each node's shape sized around its text, wrapped at 200 points; the nodes in
/// ranks along the diagram's direction, 40 points apart in a rank and 48 points between ranks; edges as S curves
/// that spread along the sides they meet; edges to a node itself as loops beside it; and the title above.
public enum FlowchartLayoutEngine {
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
    public static func layout(_ diagram: FlowchartDiagram, typography: DiagramTypography, limits: MermaidDiagramLimits,
                              spacing diagramSpacing: DiagramSpacing = .standard) throws(FlowchartLayoutError) -> FlowchartLayout {
        try layout(diagram, nodeText: typography.nodeText, edgeText: typography.edgeText, font: typography.font, limits: limits, spacing: diagramSpacing)
    }

    /// The flowchart for a container `availableWidth` wide (nil for none), as Pele fits it (flowchart/render.ts): one
    /// whose own direction runs across is turned to run down (its groups keep theirs) when it does not fit a container
    /// under 640 points and turned is narrower (`turnToFit`); either way it is laid out with the tight gaps, its title
    /// wrapped to the container, when it does not fit and tight is narrower (`tighten`). Its collapsed groups are folded
    /// and its text measured once for every layout tried, as turning and tightening change neither.
    public static func layout(_ diagram: FlowchartDiagram, typography: DiagramTypography, limits: MermaidDiagramLimits,
                              availableWidth: CGFloat?) throws(FlowchartLayoutError) -> FlowchartLayout {
        let folded = diagram.hasCollapsedSubgraph ? FlowchartCollapsedGroups.collapsing(diagram) : diagram
        let measured = FlowchartMeasurement(diagram: folded, nodeText: typography.nodeText, edgeText: typography.edgeText, wrappingWidth: wrappingWidth)
        func fitted(_ diagram: FlowchartDiagram) throws(FlowchartLayoutError) -> FlowchartLayout {
            try DiagramWidthFitting.tighten(availableWidth: availableWidth, width: { (layout: FlowchartLayout) in layout.size.width }) { isTight throws(FlowchartLayoutError) in
                try layout(diagram, measured: measured, nodeText: typography.nodeText, font: typography.font, limits: limits,
                           spacing: isTight ? compactSpacing : spacing,
                           groupPadding: isTight ? FlowchartClusterGraph.tightClusterPadding : FlowchartClusterGraph.clusterPadding,
                           titleWidth: isTight ? DiagramWidthFitting.titleRoom(availableWidth: availableWidth) : .greatestFiniteMagnitude)
            }
        }
        guard let turned = folded.rootTurnedToRunDown else { return try fitted(folded) }
        return try DiagramWidthFitting.turnToFit(availableWidth: availableWidth, width: { (layout: FlowchartLayout) in layout.size.width }) { isDown throws(FlowchartLayoutError) in
            try fitted(isDown ? turned : folded)
        }
    }

    /// `titleWidth`: the width the title wraps at.
    static func layout<Measurer: DiagramTextMeasuring>(_ written: FlowchartDiagram, nodeText: Measurer, edgeText: Measurer, font: DiagramFont,
                                                       limits: MermaidDiagramLimits, spacing diagramSpacing: DiagramSpacing = .standard,
                                                       titleWidth: CGFloat = .greatestFiniteMagnitude) throws(FlowchartLayoutError) -> FlowchartLayout {
        // A collapsed group is drawn as one node, what it holds left out (`FlowchartCollapsedGroups`); a flowchart without
        // one is laid out as it is, not copied.
        guard written.hasCollapsedSubgraph else {
            return try measuredLayout(written, nodeText: nodeText, edgeText: edgeText, font: font, limits: limits, spacing: diagramSpacing,
                                      titleWidth: titleWidth)
        }
        return try measuredLayout(FlowchartCollapsedGroups.collapsing(written), nodeText: nodeText, edgeText: edgeText, font: font, limits: limits,
                                  spacing: diagramSpacing, titleWidth: titleWidth)
    }

    /// `diagram`, its collapsed groups folded, measured and laid out.
    private static func measuredLayout<Measurer: DiagramTextMeasuring>(_ diagram: FlowchartDiagram, nodeText: Measurer, edgeText: Measurer,
                                                                        font: DiagramFont, limits: MermaidDiagramLimits, spacing diagramSpacing: DiagramSpacing,
                                                                        titleWidth: CGFloat) throws(FlowchartLayoutError) -> FlowchartLayout {
        let isTight = diagramSpacing == .compact
        let measured = FlowchartMeasurement(diagram: diagram, nodeText: nodeText, edgeText: edgeText, wrappingWidth: wrappingWidth)
        return try layout(diagram, measured: measured, nodeText: nodeText, font: font, limits: limits, spacing: isTight ? compactSpacing : spacing,
                          groupPadding: isTight ? FlowchartClusterGraph.tightClusterPadding : FlowchartClusterGraph.clusterPadding, titleWidth: titleWidth)
    }

    /// A flowchart already measured, its collapsed groups folded, laid out with `spacing`: in ranks, or in boxes when it
    /// has subgraphs. A diagram drawn as a flowchart (an agent flow) measures its nodes its own way and is laid out here.
    /// `groupPadding`: the room inside a group's box on its sides and below (Pele's `groupPad`); `titleWidth`: the width
    /// the title wraps at.
    static func layout<Measurer: DiagramTextMeasuring>(_ diagram: FlowchartDiagram, measured: FlowchartMeasurement, nodeText: Measurer,
                                                       font: DiagramFont, limits: MermaidDiagramLimits, spacing: LayeredSpacing,
                                                       groupPadding: CGFloat = FlowchartClusterGraph.clusterPadding,
                                                       titleWidth: CGFloat = .greatestFiniteMagnitude) throws(FlowchartLayoutError) -> FlowchartLayout {
        let title = diagram.title.map { title in DiagramTextBlock(label: DiagramLabel(title), measurer: nodeText, maximumWidth: titleWidth) }
        guard diagram.subgraphCount == 0 else {
            return try layoutInBoxes(diagram, measured: measured, nodeText: nodeText, font: font, limits: limits, spacing: spacing,
                                     groupPadding: groupPadding, title: title)
        }
        let laidOut = DiagramScratchArena.withCurrentThread { arena in
            FlowchartRankedLayout.layout(diagram, measured: measured, font: font, spacing: spacing, maximumPointCount: limits.maximumLayoutPointCount,
                                         title: title, arena: arena)
        }
        guard let laidOut else { throw .tooManyLayoutPoints(limit: limits.maximumLayoutPointCount) }
        return laidOut
    }

    /// A flowchart with subgraphs: each group a box laid out on its own and placed in the box around it, as Pele does
    /// (`FlowchartClusterGraph`, `LayeredCompoundLayout`, `FlowchartBoxedLayout`).
    private static func layoutInBoxes<Measurer: DiagramTextMeasuring>(_ diagram: FlowchartDiagram, measured: FlowchartMeasurement, nodeText: Measurer,
                                                                      font: DiagramFont, limits: MermaidDiagramLimits, spacing: LayeredSpacing,
                                                                      groupPadding: CGFloat,
                                                                      title: DiagramTextBlock?) throws(FlowchartLayoutError) -> FlowchartLayout {
        let laidOut = DiagramScratchArena.withCurrentThread { arena in
            FlowchartBoxedLayout.layout(diagram, measured: measured, titleText: nodeText, font: font, spacing: spacing, groupPadding: groupPadding,
                                        maximumPointCount: limits.maximumLayoutPointCount, title: title, arena: arena)
        }
        guard let laidOut else { throw .tooManyLayoutPoints(limit: limits.maximumLayoutPointCount) }
        return laidOut
    }
}
