/**
 * File: RequirementLayoutEngine.swift
 * -----------------------------------
 * Layer: Core
 * Description: Lays a requirement diagram out in Pele's style: boxes in ranks along its direction, relations as S curves
 *              between their boxes' sides with their marks and texts, loops beside their boxes, the title above, every
 *              list it works in a list of the thread's scratch arena.
 *
 * Authors: Bahey Shalash
 * Version: 0.7
 * Date: 26/11/2026
 */

import CoreGraphics

/// Lays a requirement diagram out as Pele's requirement renderer does: each box sized around its stereotype, name and
/// fields (`RequirementMeasurement`); the boxes in ranks along the diagram's direction (`LayeredFlatLayout`), 40 points apart
/// in a rank and 56 points between ranks, a relation's text in a rank of its own; relations from the middle of a side,
/// spread along it where several share it (`RequirementEdgePorts`), as S curves; relations from a box to itself looped
/// beside it (`RequirementSelfLoops`); and the title above, 12 points over the diagram, all 8 points inside the page.
/// The measuring and the placing work in the calling thread's arena; only the layout's own lists are made.
public enum RequirementLayoutEngine {
    static let spacing = LayeredSpacing(nodeSeparation: 40, edgeSeparation: 16, rankSeparation: 56)
    static let padding: CGFloat = 8
    static let titleGap: CGFloat = 12
    /// A containment mark's radius: its line starts past the circle, two radii from the box.
    static let containmentRadius: CGFloat = 6

    public static func layout(_ diagram: RequirementDiagram, typography: DiagramTypography,
                              limits: MermaidDiagramLimits) throws(RequirementLayoutError) -> RequirementLayout {
        try layout(diagram, measurers: RequirementTextMeasurers(names: typography.boldNodeText, body: typography.edgeText),
                   titleText: typography.boldNodeText, font: typography.font, limits: limits)
    }

    static func layout<Measurer: DiagramTextMeasuring>(_ diagram: RequirementDiagram, measurers: RequirementTextMeasurers<Measurer>, titleText: Measurer,
                                                       font: DiagramFont, limits: MermaidDiagramLimits) throws(RequirementLayoutError) -> RequirementLayout {
        let laidOut = DiagramScratchArena.withCurrentThread { arena -> RequirementLayout? in
            var measured = RequirementMeasurement(diagram: diagram, measurers: measurers, arena: arena)
            let title = diagram.title.map { title in
                DiagramFlatTextMeasuring.measure(DiagramLabel(title), measurer: DiagramFlatMeasurer(titleText), maximumWidth: RequirementMeasurement.unwrapped,
                                                 into: &measured.lines)
            }
            return rankedLayout(diagram, measured: measured, title: title, font: font, maximumPointCount: limits.maximumLayoutPointCount, arena: arena)
        }
        guard let laidOut else { throw .tooManyLayoutPoints(limit: limits.maximumLayoutPointCount) }
        return laidOut
    }

    /// The boxes and the relations between two different boxes as one flat layered graph written straight into the flat
    /// layout's spans, the placed spans read on the page; nil when the graph would need more than `maximumPointCount` nodes
    /// and passing points.
    private static func rankedLayout(_ diagram: RequirementDiagram, measured: RequirementMeasurement, title: DiagramMeasuredText?, font: DiagramFont,
                                     maximumPointCount: Int, arena: DiagramScratchArena) -> RequirementLayout? {
        let flowAxes = FlowchartFlowAxes(direction: diagram.direction, alongExtent: 0)
        let layoutSizes = measured.layoutSizes(flowIsVertical: flowAxes.flowIsVertical, arena: arena)
        let nodes: ScratchSpan<LayeredFlatNode> = arena.uninitializedSpan(count: layoutSizes.count)
        for node in 0..<layoutSizes.count {
            let size = flowAxes.flowSize(of: layoutSizes[node])
            nodes[node] = LayeredFlatNode(width: Double(size.across), height: Double(size.along))
        }
        var layered = arena.list(capacity: measured.edges.count, of: Int.self)
        for edgeIndex in 0..<measured.edges.count where !measured.edges[edgeIndex].isSelfLoop { layered.append(edgeIndex) }
        let edges: ScratchSpan<LayeredSpanEdge> = arena.uninitializedSpan(count: layered.count)
        for layeredIndex in 0..<layered.count {
            let edge = measured.edges[layered[layeredIndex]]
            let room = RequirementMeasurement.edgeTextRoom
            let labelSize = flowAxes.flowSize(of: CGSize(width: edge.text.size.width + room.width, height: edge.text.size.height + room.height))
            edges[layeredIndex] = LayeredSpanEdge(tail: Int(edge.source), head: Int(edge.target), minimumLength: 1, labelWidth: Double(labelSize.across),
                                                  labelHeight: Double(labelSize.along), tailOffset: 0, headOffset: 0)
        }
        #if DEBUG
        LayeredLayoutRecording.recordPlacement(nodes: nodes, edges: edges, spacing: spacing, maximumPointCount: maximumPointCount)
        #endif
        var points = arena.list(capacity: 4 * edges.count, of: CGPoint.self)
        guard let placed = LayeredFlatLayout.layout(nodes: nodes, edges: edges, points: &points, options: LayeredFlatOptions(spacing),
                                                    maximumVertexCount: maximumPointCount, arena: arena) else {
            return nil
        }
        let extent = flowAxes.flowIsVertical ? CGSize(width: placed.width, height: placed.height) : CGSize(width: placed.height, height: placed.width)
        var page = RequirementPageAssembly(measured: measured, axes: FlowchartFlowAxes(direction: diagram.direction, alongExtent: CGFloat(placed.height)),
                                           flowNodes: nodes, frame: RequirementPageFrame(extent: extent, title: title), arena: arena)
        page.placeRelations(layeredEdgeIndices: layered.elements, nodes: nodes, edges: edges, points: points.elements, arena: arena)
        page.placeSelfLoops()
        return page.finished(font: font, title: title, source: diagram.model.text)
    }
}

/// Where a requirement diagram's drawing goes on its page: its layout's extent moved 8 points inside the page, below the
/// title and centered under it when the title is wider, as Pele frames it.
struct RequirementPageFrame {
    /// What every place found around the layout's origin is moved by.
    let offset: CGVector
    let size: CGSize
    let titleSize: CGSize

    init(extent: CGSize, title: DiagramMeasuredText?) {
        let padding = RequirementLayoutEngine.padding
        titleSize = title?.size ?? .zero
        let titleHeight = titleSize.height > 0 ? titleSize.height + RequirementLayoutEngine.titleGap : 0
        let innerWidth = max(extent.width, titleSize.width)
        offset = CGVector(dx: padding + (innerWidth - extent.width) / 2, dy: padding + titleHeight)
        size = CGSize(width: (innerWidth + 2 * padding).rounded(.up), height: (extent.height + titleHeight + 2 * padding).rounded(.up))
    }

    /// The title placed, or nil without one or for a title of no line.
    func placedTitle(_ title: DiagramMeasuredText?) -> DiagramMeasuredText? {
        title.flatMap { title in
            title.lineCount == 0 ? nil : title.centered(at: CGPoint(x: size.width / 2, y: RequirementLayoutEngine.padding + titleSize.height / 2))
        }
    }
}
