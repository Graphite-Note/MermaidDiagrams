/**
 * File: RequirementLayoutEngine.swift
 * -----------------------------------
 * Layer: Core
 * Description: Lays a requirement diagram out in Pele's style: boxes in ranks along its direction, relations as S curves
 *              between their boxes' sides with their marks and texts, loops beside their boxes, the title above.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

import CoreGraphics

/// Lays a requirement diagram out as Pele's requirement renderer does: each box sized around its stereotype, name and
/// fields (`RequirementMeasurement`); the boxes in ranks along the diagram's direction (`LayeredLayout`), 40 points apart
/// in a rank and 56 points between ranks, a relation's text in a rank of its own; relations from the middle of a side,
/// spread along it where several share it (`RequirementEdgePorts`), as S curves; relations from a box to itself looped
/// beside it (`RequirementSelfLoops`); and the title above, 12 points over the diagram, all 8 points inside the page.
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
        let measured = RequirementMeasurement(diagram: diagram, measurers: measurers)
        let flowAxes = FlowchartFlowAxes(direction: diagram.direction, alongExtent: 0)
        let layeredEdgeIndices = measured.edges.indices.filter { edgeIndex in !measured.edges[edgeIndex].isSelfLoop }
        let graph = LayeredGraph(nodeSizes: measured.layoutSizes(flowIsVertical: flowAxes.flowIsVertical).map(flowAxes.flowSize(of:)),
                                 edges: layeredEdgeIndices.map { edgeIndex in
                                     let edge = measured.edges[edgeIndex]
                                     let room = RequirementMeasurement.edgeTextRoom
                                     let labelSize = flowAxes.flowSize(of: CGSize(width: edge.text.size.width + room.width,
                                                                                  height: edge.text.size.height + room.height))
                                     return LayeredEdge(source: edge.source, target: edge.target, minimumRankSpan: 1, labelSize: labelSize)
                                 })
        guard let placement = LayeredLayout.place(graph, spacing: spacing, maximumPointCount: limits.maximumLayoutPointCount) else {
            throw .tooManyLayoutPoints(limit: limits.maximumLayoutPointCount)
        }
        var page = RequirementPageAssembly(measured: measured,
                                           axes: FlowchartFlowAxes(direction: diagram.direction, alongExtent: placement.extent.height),
                                           flowCenters: placement.nodeCenters)
        page.placeRelations(layeredEdgeIndices: layeredEdgeIndices, placement: placement)
        page.placeSelfLoops()
        let title = diagram.title.map { title in DiagramTextBlock(label: DiagramLabel(title), measurer: titleText, maximumWidth: RequirementMeasurement.unwrapped) }
        let extent = flowAxes.flowIsVertical ? placement.extent : CGSize(width: placement.extent.height, height: placement.extent.width)
        return page.finished(extent: extent, font: font, title: title)
    }
}

/// Puts a placed requirement diagram on the page: the boxes at their centers, the relations from side to side through
/// their passing points with their marks and texts, the loops beside their boxes, then everything moved inside the
/// padding below the title.
struct RequirementPageAssembly {
    let measured: RequirementMeasurement
    let axes: FlowchartFlowAxes
    let centers: [CGPoint]
    /// By the measurement's edge index; nil until placed.
    private var relations: [RequirementLayoutRelation?]

    init(measured: RequirementMeasurement, axes: FlowchartFlowAxes, flowCenters: [CGPoint]) {
        self.measured = measured
        self.axes = axes
        centers = flowCenters.map(axes.pagePoint)
        relations = Array(repeating: nil, count: measured.edges.count)
    }

    /// The relations between two boxes, along their routes; `layeredEdgeIndices[i]` is the edge of the `i`-th route.
    mutating func placeRelations(layeredEdgeIndices: [Int], placement: LayeredPlacement) {
        var ends: [RequirementEdgePorts.End] = []
        for (layeredIndex, edgeIndex) in layeredEdgeIndices.enumerated() {
            let route = placement.edgeRoutes[layeredIndex].map(axes.pagePoint)
            let edge = measured.edges[edgeIndex]
            ends.append(end(of: edgeIndex, isSourceEnd: true, box: edge.source, at: route[0], next: route[1]))
            ends.append(end(of: edgeIndex, isSourceEnd: false, box: edge.target, at: route[route.count - 1], next: route[route.count - 2]))
        }
        let ports = RequirementEdgePorts(ends: ends, edgeCount: measured.edges.count, centers: centers, sizes: measured.boxes.map(\.size))
        for (layeredIndex, edgeIndex) in layeredEdgeIndices.enumerated() {
            guard let sourcePort = ports.sourcePoints[edgeIndex], let targetPort = ports.targetPoints[edgeIndex] else { continue }
            let route = placement.edgeRoutes[layeredIndex].map(axes.pagePoint)
            let edge = measured.edges[edgeIndex]
            let drawn = DiagramRouteDrawing.path(through: [sourcePort] + route.dropFirst().dropLast() + [targetPort], flowIsVertical: axes.flowIsVertical,
                                                 startTrim: edge.isContainment ? 2 * RequirementLayoutEngine.containmentRadius : 0, endTrim: 0)
            let mark: RequirementRelationMark = edge.isContainment
                ? .containment(point: sourcePort, towardBox: CGVector(dx: -drawn.startDirection.dx, dy: -drawn.startDirection.dy))
                : .arrow(tip: targetPort, direction: drawn.endDirection)
            let textCenter = placement.edgeLabelCenters[layeredIndex].map(axes.pagePoint)
                ?? CGPoint(x: (sourcePort.x + targetPort.x) / 2, y: (sourcePort.y + targetPort.y) / 2)
            relations[edgeIndex] = RequirementLayoutRelation(kind: edge.kind, path: drawn.path, mark: mark, text: Self.centered(edge.text, at: textCenter))
        }
    }

    /// An end of a route on the side of its box that faces the route's next point along the flow, at the side's middle.
    private func end(of edgeIndex: Int, isSourceEnd: Bool, box: Int, at point: CGPoint, next: CGPoint) -> RequirementEdgePorts.End {
        let side: DiagramSide = axes.flowIsVertical ? (next.y > point.y ? .bottom : .top) : (next.x > point.x ? .right : .left)
        return RequirementEdgePorts.End(edgeIndex: edgeIndex, isSourceEnd: isSourceEnd, box: box, side: side, toward: side.isHorizontal ? next.x : next.y)
    }

    /// The loops of every box that has relations to itself.
    mutating func placeSelfLoops() {
        for (box, loopEdgeIndices) in measured.selfLoopEdgeIndices.enumerated() {
            for (loopIndex, edgeIndex) in loopEdgeIndices.enumerated() {
                let edge = measured.edges[edgeIndex]
                let loop = RequirementSelfLoops.loop(center: centers[box], boxSize: measured.boxes[box].size, loopIndex: loopIndex,
                                                     flowIsVertical: axes.flowIsVertical,
                                                     startTrim: edge.isContainment ? 2 * RequirementLayoutEngine.containmentRadius : 0, textSize: edge.text.size)
                let mark: RequirementRelationMark = edge.isContainment ? .containment(point: loop.leave, towardBox: loop.intoBox)
                                                                       : .arrow(tip: loop.back, direction: loop.intoBox)
                relations[edgeIndex] = RequirementLayoutRelation(kind: edge.kind, path: loop.path, mark: mark, text: Self.centered(edge.text, at: loop.textCenter))
            }
        }
    }

    /// The finished layout: the layout's `extent` moved 8 points inside the page, below the title and centered under it
    /// when the title is wider, as Pele frames it.
    func finished(extent: CGSize, font: DiagramFont, title: DiagramTextBlock?) -> RequirementLayout {
        let padding = RequirementLayoutEngine.padding
        let titleSize = title?.size ?? .zero
        let titleHeight = titleSize.height > 0 ? titleSize.height + RequirementLayoutEngine.titleGap : 0
        let innerWidth = max(extent.width, titleSize.width)
        let offset = CGVector(dx: padding + (innerWidth - extent.width) / 2, dy: padding + titleHeight)
        let size = CGSize(width: (innerWidth + 2 * padding).rounded(.up), height: (extent.height + titleHeight + 2 * padding).rounded(.up))
        var placedTitle = title.flatMap { title in title.lineCount == 0 ? nil : title }
        placedTitle?.center = CGPoint(x: size.width / 2, y: padding + titleSize.height / 2)
        let boxes = measured.boxes.indices.map { box in Self.placedBox(measured.boxes[box], at: centers[box]).translated(by: offset) }
        return RequirementLayout(size: size, font: font, boxes: boxes, relations: relations.compactMap { relation in relation?.translated(by: offset) },
                                 title: placedTitle)
    }

    /// A box with its texts placed around `center`.
    private static func placedBox(_ box: RequirementMeasuredBox, at center: CGPoint) -> RequirementLayoutBox {
        let frame = CGRect(x: center.x - box.size.width / 2, y: center.y - box.size.height / 2, width: box.size.width, height: box.size.height)
        let headTop = frame.minY + RequirementMeasurement.paddingAlong
        let stereotype = centered(box.stereotype, at: CGPoint(x: center.x, y: headTop + box.stereotype.size.height / 2))
        let name = centered(box.name, at: CGPoint(x: center.x, y: headTop + box.stereotype.size.height + box.name.size.height / 2))
        guard !box.rows.isEmpty else {
            return RequirementLayoutBox(frame: frame, isRequirement: box.isRequirement, stereotype: stereotype, name: name, dividerY: nil, fieldNames: [],
                                        fieldValues: [], style: box.style)
        }
        let divider = frame.minY + box.headHeight
        var rowTop = divider + RequirementMeasurement.paddingAlong
        var fieldNames: [DiagramTextBlock] = []
        var fieldValues: [DiagramTextBlock] = []
        let keyLeft = frame.minX + RequirementMeasurement.paddingAcross
        for row in box.rows {
            fieldNames += startingAt(row.key, left: keyLeft, top: rowTop)
            fieldValues += startingAt(row.value, left: keyLeft + box.keyWidth + RequirementMeasurement.columnGap, top: rowTop)
            rowTop += row.height + RequirementMeasurement.rowGap
        }
        return RequirementLayoutBox(frame: frame, isRequirement: box.isRequirement, stereotype: stereotype, name: name, dividerY: divider,
                                    fieldNames: fieldNames, fieldValues: fieldValues, style: box.style)
    }

    /// The text's lines, each starting at `left`, the first line's box starting at `top`, as Pele writes a field.
    private static func startingAt(_ text: DiagramTextBlock, left: CGFloat, top: CGFloat) -> [DiagramTextBlock] {
        centered(text, at: CGPoint(x: left + text.size.width / 2, y: top + text.size.height / 2)).leftAlignedLines()
    }

    private static func centered(_ text: DiagramTextBlock, at center: CGPoint) -> DiagramTextBlock {
        var placed = text
        placed.center = center
        return placed
    }
}
