/**
 * File: ClassDiagramLayoutEngine.swift
 * ------------------------------------
 * Layer: Core
 * Description: Lays a class diagram out in Pele's style, its namespaces as nested boxes, and for a narrow container
 *              turned, tightened and its unjoined parts set in rows as Pele fits it.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.4
 * Date: 23/11/2026
 */

import CoreGraphics

/// Lays a class diagram out in Pele's style: each class a box of compartments sized around its text, notes and
/// lollipop interfaces beside them; the nodes in ranks along the diagram's direction, 40 points apart in a rank and
/// 56 points between ranks (72 when a relation has a cardinality); relations as S curves that spread along the
/// sides they meet, with their marks, text and cardinalities; relations from a class to itself as loops beside it;
/// and the title above.
public enum ClassDiagramLayoutEngine {
    /// Pele's gaps; the class diagram sets the ends of relations on one side of a box apart itself, so two relations between
    /// the same boxes need no bend (class/render.ts `apart`).
    static let spacing = LayeredSpacing(nodeSeparation: 40, edgeSeparation: 16, rankSeparation: 56, routing: LayeredRouting(keepsTwinsApart: true))
    /// Between ranks when any relation has a cardinality, which needs room at both ends.
    static let rankSeparationWithCardinalities: CGFloat = 72
    /// Around the whole diagram.
    static let padding: CGFloat = 8
    /// The room a relation's text takes beyond its lines, for the patch drawn behind it.
    static let edgeTextRoom = CGSize(width: 12, height: 4)
    /// Between the title and the diagram.
    static let titleGap: CGFloat = 12

    public static func layout(_ diagram: ClassDiagram, typography: DiagramTypography,
                              limits: MermaidDiagramLimits) throws(ClassDiagramLayoutError) -> ClassDiagramLayout {
        try layout(diagram, measurers: ClassDiagramTextMeasurers(names: typography.boldNodeText, members: typography.edgeText, marks: typography.smallText,
                                                                 namespaceTitles: typography.nodeText),
                   font: typography.font, limits: limits)
    }

    /// The diagram for a container `availableWidth` wide (nil for none), as Pele fits it (class/render.ts): one that runs
    /// across is laid out from the top down when it does not fit a container under 640 points and that is narrower
    /// (`turnToFit`); either way, tightly (a namespace a relation crosses into not widened for its title) when it does
    /// not fit and tight is narrower (`tighten`); and each drawing wider than the container has its parts that nothing
    /// joins set in rows (`ClassDiagramComponentRows`).
    public static func layout(_ diagram: ClassDiagram, typography: DiagramTypography, limits: MermaidDiagramLimits,
                              availableWidth: CGFloat?) throws(ClassDiagramLayoutError) -> ClassDiagramLayout {
        let measurers = ClassDiagramTextMeasurers(names: typography.boldNodeText, members: typography.edgeText, marks: typography.smallText,
                                                  namespaceTitles: typography.nodeText)
        func fitted(_ diagram: ClassDiagram) throws(ClassDiagramLayoutError) -> ClassDiagramLayout {
            try DiagramWidthFitting.tighten(availableWidth: availableWidth, width: { (layout: ClassDiagramLayout) in layout.size.width }) { isTight throws(ClassDiagramLayoutError) in
                try layout(diagram, measurers: measurers, font: typography.font, limits: limits, isTight: isTight, availableWidth: availableWidth)
            }
        }
        guard let turned = diagram.turnedTopToBottom else { return try fitted(diagram) }
        return try DiagramWidthFitting.turnToFit(availableWidth: availableWidth, width: { (layout: ClassDiagramLayout) in layout.size.width }) { isDown throws(ClassDiagramLayoutError) in
            try fitted(isDown ? turned : diagram)
        }
    }

    /// `isTight`: Pele's tight layout; `availableWidth`: the container's width, past which the parts are set in rows.
    static func layout<Measurer: DiagramTextMeasuring>(_ diagram: ClassDiagram, measurers: ClassDiagramTextMeasurers<Measurer>, font: DiagramFont,
                                                       limits: MermaidDiagramLimits, isTight: Bool = false,
                                                       availableWidth: CGFloat? = nil) throws(ClassDiagramLayoutError) -> ClassDiagramLayout {
        var measured = ClassDiagramMeasurement(diagram: diagram, measurers: measurers)
        let flowAxes = FlowchartFlowAxes(direction: diagram.direction, alongExtent: 0)
        if flowAxes.flowIsVertical { measured.widenCrowdedClasses() }
        let selfLoops = measured.selfLoopEdgeIndices
        guard diagram.namespaces.isEmpty else {
            return try layoutInBoxes(diagram, measured: measured, selfLoops: selfLoops, measurers: measurers, font: font, limits: limits, isTight: isTight,
                                     availableWidth: availableWidth)
        }
        let layeredEdgeIndices = measured.edges.indices.filter { edgeIndex in !measured.edges[edgeIndex].isSelfLoop }
        let graph = LayeredGraph(nodeSizes: measured.layoutSizes(selfLoops: selfLoops).map(flowAxes.flowSize(of:)),
                                 edges: layeredEdgeIndices.map { edgeIndex in
                                     let edge = measured.edges[edgeIndex]
                                     let labelSize = edge.text.map { text in
                                         flowAxes.flowSize(of: CGSize(width: text.size.width + edgeTextRoom.width,
                                                                      height: text.size.height + edgeTextRoom.height))
                                     }
                                     return LayeredEdge(source: edge.source, target: edge.target, minimumRankSpan: 1, labelSize: labelSize)
                                 })
        guard let placement = LayeredLayout.place(graph, spacing: spacing(for: measured), maximumPointCount: limits.maximumLayoutPointCount) else {
            throw .tooManyLayoutPoints(limit: limits.maximumLayoutPointCount)
        }
        var page = ClassDiagramPageAssembly(measured: measured, markRowHeight: measurers.markRowHeight,
                                            axes: FlowchartFlowAxes(direction: diagram.direction, alongExtent: placement.extent.height))
        page.placeNodes(flowCenters: placement.nodeCenters)
        page.placeEdges(layeredEdgeIndices: layeredEdgeIndices, placement: placement)
        page.placeSelfLoops(selfLoops)
        let title = diagram.title.map { title in
            DiagramTextBlock(label: DiagramLabel(title), measurer: measurers.names, maximumWidth: .greatestFiniteMagnitude)
        }
        return finished(page, font: font, title: title, availableWidth: availableWidth)
    }

    /// The page finished; for a container `availableWidth` wide that the drawing (its title aside) is wider than, with
    /// its parts that nothing joins set in rows that fit it, when that makes it narrower.
    private static func finished(_ page: ClassDiagramPageAssembly, font: DiagramFont, title: DiagramTextBlock?,
                                 availableWidth: CGFloat?) -> ClassDiagramLayout {
        guard let available = DiagramWidthFitting.limit(availableWidth),
              page.finished(font: font, title: nil, padding: padding, titleGap: titleGap).size.width > available,
              let wrapped = page.wrappedInRows(rowWidth: max(1, available - 2 * padding), gap: spacing.nodeSeparation) else {
            return page.finished(font: font, title: title, padding: padding, titleGap: titleGap)
        }
        return wrapped.page.finished(font: font, title: title, padding: padding, titleGap: titleGap, drawingBounds: CGRect(origin: .zero, size: wrapped.size))
    }

    /// A diagram with namespaces: each a box laid out on its own and placed in the box around it, as Pele's class
    /// renderer does (`ClassDiagramNamespaceTree`, `ClassDiagramClusterGraph`, `LayeredClusterLayout`).
    private static func layoutInBoxes<Measurer: DiagramTextMeasuring>(_ diagram: ClassDiagram, measured: ClassDiagramMeasurement, selfLoops: [[Int]],
                                                                      measurers: ClassDiagramTextMeasurers<Measurer>, font: DiagramFont,
                                                                      limits: MermaidDiagramLimits, isTight: Bool,
                                                                      availableWidth: CGFloat?) throws(ClassDiagramLayoutError) -> ClassDiagramLayout {
        let clustered = ClassDiagramClusterGraph(tree: ClassDiagramNamespaceTree(diagram: diagram), measured: measured,
                                                 layoutSizes: measured.layoutSizes(selfLoops: selfLoops), direction: diagram.direction,
                                                 titleText: measurers.namespaceTitles, edgeTextRoom: edgeTextRoom, isTight: isTight)
        var clusterSpacing = spacing(for: measured)
        clusterSpacing.borderSeparation = ClassDiagramClusterGraph.padding
        let placement: LayeredClusterPlacement
        do {
            placement = try LayeredClusterLayout.place(clustered.graph, spacing: clusterSpacing, maximumPointCount: limits.maximumLayoutPointCount)
        } catch {
            throw .tooManyLayoutPoints(limit: limits.maximumLayoutPointCount)
        }
        var page = ClassDiagramPageAssembly(measured: measured, markRowHeight: measurers.markRowHeight,
                                            axes: FlowchartFlowAxes(direction: diagram.direction, alongExtent: 0))
        page.placeNodes(pageCenters: placement.nodeCenters)
        page.placeEdges(clustered: clustered, placement: placement)
        page.placeSelfLoops(selfLoops)
        page.placeNamespaces(clustered: clustered, placement: placement)
        let title = diagram.title.map { title in
            DiagramTextBlock(label: DiagramLabel(title), measurer: measurers.names, maximumWidth: .greatestFiniteMagnitude)
        }
        return finished(page, font: font, title: title, availableWidth: availableWidth)
    }

    /// Pele's gaps, with ranks farther apart when any relation has a cardinality.
    private static func spacing(for measured: ClassDiagramMeasurement) -> LayeredSpacing {
        var spacing = Self.spacing
        if measured.edges.contains(where: { edge in edge.sourceCardinality != nil || edge.targetCardinality != nil }) {
            spacing.rankSeparation = rankSeparationWithCardinalities
        }
        return spacing
    }
}
