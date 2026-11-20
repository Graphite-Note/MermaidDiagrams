/**
 * File: UseCaseLayoutEngine.swift
 * -------------------------------
 * Layer: Core
 * Description: Lays a use case diagram out as Pele's renderUsecase does: its nodes measured, its system boundaries as
 *              boxes of the layered cluster layout, loops grown into their nodes' boxes, then the page assembled.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// Lays a use case diagram out in Pele's way: actors as figures, use cases as ovals or boxes, notes and JSON tables as
/// boxes, in ranks along the diagram's direction 32 points apart in a rank and 72 between ranks (or the options'
/// spacing), each system boundary a box of its own around what it holds, and the title above.
public enum UseCaseLayoutEngine {
    static let nodeSeparation: CGFloat = 32
    static let edgeSeparation: CGFloat = 16
    static let rankSeparation: CGFloat = 72
    /// Between a border point of a boundary and the rank next to it: Pele's `portSep`.
    static let borderSeparation: CGFloat = 20
    /// Around the whole diagram.
    static let padding: CGFloat = 8
    /// Between the title and the diagram.
    static let titleGap: CGFloat = 12
    /// The room an edge's label takes beyond its lines in the layout, and its patch beyond its text.
    static let edgeLabelRoom = CGSize(width: 12, height: 4)
    static let edgeLabelPatchWidening: CGFloat = 8
    /// The widest an edge's label is before it wraps.
    static let edgeLabelRoomWidth: CGFloat = 200

    public static func layout(_ diagram: UseCaseDiagram, typography: DiagramTypography,
                              limits: MermaidDiagramLimits = .standard) throws(UseCaseLayoutError) -> UseCaseLayout {
        var measurers = UseCaseTextMeasurers(typography: typography)
        return try layout(diagram, measurers: &measurers, limits: limits)
    }

    /// The diagram laid out for a container `width` wide, as Pele's `turnToFit` draws it: across as written, and turned
    /// to run down when it runs across, the container is narrower than it and than 640 points, and down is narrower.
    public static func layout(_ diagram: UseCaseDiagram, typography: DiagramTypography, limits: MermaidDiagramLimits = .standard,
                              fittingWidth width: CGFloat?) throws(UseCaseLayoutError) -> UseCaseLayout {
        guard let turned = diagram.turnedToRunDown else { return try layout(diagram, typography: typography, limits: limits) }
        return try DiagramWidthFitting.turnToFit(availableWidth: width, width: { layout in layout.size.width }) { (down: Bool) throws(UseCaseLayoutError) in
            try layout(down ? turned : diagram, typography: typography, limits: limits)
        }
    }

    static func layout<Measurer>(_ diagram: UseCaseDiagram, measurers: inout UseCaseTextMeasurers<Measurer>,
                                 limits: MermaidDiagramLimits) throws(UseCaseLayoutError) -> UseCaseLayout {
        var pass = UseCaseLayoutPass(diagram: diagram, measurers: &measurers)
        let spacing = LayeredSpacing(nodeSeparation: diagram.nodeSpacing.map { CGFloat($0) } ?? nodeSeparation, edgeSeparation: edgeSeparation,
                                     rankSeparation: diagram.rankSpacing.map { CGFloat($0) } ?? rankSeparation, borderSeparation: borderSeparation)
        let placement: LayeredClusterPlacement
        do {
            placement = try LayeredClusterLayout.place(pass.clusterGraph(), spacing: spacing, maximumPointCount: limits.maximumLayoutPointCount)
        } catch {
            throw .tooManyLayoutPoints(limit: limits.maximumLayoutPointCount)
        }
        return pass.assembled(placement, measurers: &measurers)
    }

    /// The way ranks follow each other in the layout.
    static func layeredDirection(of direction: UseCaseDirection) -> LayeredDirection {
        switch direction {
        case .topToBottom: .topToBottom
        case .bottomToTop: .bottomToTop
        case .leftToRight: .leftToRight
        case .rightToLeft: .rightToLeft
        }
    }
}

/// One layout of a use case diagram: its nodes measured, its edges' labels measured and its loops counted, then what
/// the cluster layout placed put on the page.
struct UseCaseLayoutPass {
    let diagram: UseCaseDiagram
    let graph: UseCaseGraph
    let fontSize: CGFloat
    let font: DiagramFont
    let isSideways: Bool
    var views: [UseCaseNodeView] = []
    /// By node, its size in the layout: what is drawn, grown to hold its loops.
    var layoutSizes: [CGSize] = []
    /// The edges drawn (both ends known), by their place in the graph, with their ends' nodes and labels.
    var drawnEdges: [(edge: Int, source: Int, target: Int, label: DiagramTextBlock)] = []
    /// For each node, its place among the layout's nodes, or among its clusters for a boundary.
    var layoutPlaces: [Int] = []

    init<Measurer>(diagram: UseCaseDiagram, measurers: inout UseCaseTextMeasurers<Measurer>) {
        self.diagram = diagram
        graph = UseCaseGraph(diagram)
        font = measurers.font
        fontSize = measurers.font.size
        isSideways = diagram.direction == .leftToRight || diagram.direction == .rightToLeft
        views = graph.nodes.map { node in UseCaseNodeMeasurement.view(of: node, size: fontSize, measurers: &measurers) }
        layoutSizes = views.map(\.size)
        measureEdges(measurers: &measurers)
    }

    /// Each edge's label, and each loop grown into its node's box: across the flow, by the loop and its label.
    private mutating func measureEdges<Measurer>(measurers: inout UseCaseTextMeasurers<Measurer>) {
        var places: [String: Int] = [:]
        for (place, node) in graph.nodes.enumerated() where places[node.identifier] == nil { places[node.identifier] = place }
        let labelMeasurer = measurers.measurer(size: UseCaseNodeMeasurement.smallSize(fontSize))
        for (place, edge) in graph.edges.enumerated() {
            guard let source = places[edge.start], let target = places[edge.end] else { continue }
            let written = edge.isSemantic ? edge.label.map { label in "«\(label)»" } : edge.label
            let label = UseCaseTextLabel.block(written, labelType: edge.labelType ?? .text, measurer: labelMeasurer,
                                               room: UseCaseLayoutEngine.edgeLabelRoomWidth)
            if source == target {
                views[source].loopCount += 1
                let size = label.size
                if isSideways {
                    layoutSizes[source].height += 2 * (UseCaseSelfLoops.reach + (size.height > 0 ? size.height + 8 : 0))
                } else {
                    layoutSizes[source].width += 2 * (UseCaseSelfLoops.reach + (size.width > 0 ? size.width + 12 : 0))
                }
            }
            drawnEdges.append((place, source, target, label))
        }
    }

    /// The boundaries as clusters, every other node in the cluster of its boundary, and the edges between two nodes.
    mutating func clusterGraph() -> LayeredClusterGraph {
        var clusterPlaces: [String: Int] = [:]
        var clusters: [LayeredCluster] = []
        var nodeSizes: [CGSize] = []
        layoutPlaces = []
        for (place, view) in views.enumerated() {
            if view.node.isGroup {
                clusterPlaces[view.node.identifier] = clusters.count
                layoutPlaces.append(clusters.count)
                clusters.append(LayeredCluster(parent: nil, direction: nil, padding: view.clusterPadding, minimumWidth: view.clusterMinimumWidth))
            } else {
                layoutPlaces.append(nodeSizes.count)
                nodeSizes.append(layoutSizes[place])
            }
        }
        let nodeClusters = views.filter { view in !view.node.isGroup }.map { view in view.node.parentIdentifier.flatMap { parent in clusterPlaces[parent] } }
        let edges = laidOutEdges.map { drawn in
            let labelSize = drawn.label.size.width > 0
                ? CGSize(width: drawn.label.size.width + UseCaseLayoutEngine.edgeLabelRoom.width, height: drawn.label.size.height + UseCaseLayoutEngine.edgeLabelRoom.height)
                : nil
            return LayeredClusterEdge(source: .node(layoutPlaces[drawn.source]), target: .node(layoutPlaces[drawn.target]),
                                      minimumRankSpan: graph.edges[drawn.edge].minimumLength, labelSize: labelSize)
        }
        return LayeredClusterGraph(nodeSizes: nodeSizes, nodeClusters: nodeClusters, clusters: clusters, edges: edges,
                                   direction: UseCaseLayoutEngine.layeredDirection(of: diagram.direction))
    }

    /// The drawn edges between two different nodes, which the layout routes, in the order drawn.
    var laidOutEdges: [(edge: Int, source: Int, target: Int, label: DiagramTextBlock)] {
        drawnEdges.filter { drawn in drawn.source != drawn.target }
    }
}
