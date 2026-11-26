/**
 * File: RequirementLayoutEngine.swift
 * -----------------------------------
 * Layer: Core
 * Description: Lays a requirement diagram out in Pele's style: boxes in ranks along its direction, relations as S curves
 *              between their boxes' sides with their marks and texts, loops beside their boxes, the title above.
 *
 * Authors: Bahey Shalash
 * Version: 0.6
 * Date: 26/11/2026
 */

import CoreGraphics

/// Lays a requirement diagram out as Pele's requirement renderer does: each box sized around its stereotype, name and
/// fields (`RequirementMeasurement`); the boxes in ranks along the diagram's direction (`LayeredFlatLayout`), 40 points apart
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
        var measured = RequirementMeasurement(diagram: diagram, measurers: measurers)
        let title = diagram.title.map { title in
            DiagramFlatTextMeasuring.measure(DiagramLabel(title), measurer: DiagramFlatMeasurer(titleText), maximumWidth: RequirementMeasurement.unwrapped,
                                             into: &measured.lines)
        }
        let flowAxes = FlowchartFlowAxes(direction: diagram.direction, alongExtent: 0)
        let placed = DiagramScratchArena.withCurrentThread { arena in
            rankedPage(diagram, measured: measured, flowAxes: flowAxes, maximumPointCount: limits.maximumLayoutPointCount, arena: arena)
        }
        guard let (page, extent) = placed else { throw .tooManyLayoutPoints(limit: limits.maximumLayoutPointCount) }
        return page.finished(extent: flowAxes.flowIsVertical ? extent : CGSize(width: extent.height, height: extent.width), font: font, title: title)
    }

    /// The boxes and the relations between two different boxes as one flat layered graph written straight into the flat
    /// layout's spans, the placed spans read on the page, with the layout's extent in flow space; nil when the graph would
    /// need more than `maximumPointCount` nodes and passing points.
    private static func rankedPage(_ diagram: RequirementDiagram, measured: RequirementMeasurement, flowAxes: FlowchartFlowAxes, maximumPointCount: Int,
                                   arena: DiagramScratchArena) -> (page: RequirementPageAssembly, extent: CGSize)? {
        let layoutSizes = measured.layoutSizes(flowIsVertical: flowAxes.flowIsVertical)
        let nodes: ScratchSpan<LayeredFlatNode> = arena.uninitializedSpan(count: layoutSizes.count)
        for node in 0..<layoutSizes.count {
            let size = flowAxes.flowSize(of: layoutSizes[node])
            nodes[node] = LayeredFlatNode(width: Double(size.across), height: Double(size.along))
        }
        var layered = arena.list(capacity: measured.edges.count, of: Int.self)
        for edgeIndex in measured.edges.indices where !measured.edges[edgeIndex].isSelfLoop { layered.append(edgeIndex) }
        let edges: ScratchSpan<LayeredSpanEdge> = arena.uninitializedSpan(count: layered.count)
        for layeredIndex in 0..<layered.count {
            let edge = measured.edges[layered[layeredIndex]]
            let room = RequirementMeasurement.edgeTextRoom
            let labelSize = flowAxes.flowSize(of: CGSize(width: edge.text.size.width + room.width, height: edge.text.size.height + room.height))
            edges[layeredIndex] = LayeredSpanEdge(tail: edge.source, head: edge.target, minimumLength: 1, labelWidth: Double(labelSize.across),
                                                  labelHeight: Double(labelSize.along), tailOffset: 0, headOffset: 0)
        }
        #if DEBUG
        LayeredLayoutRecording.recordPlacement(nodes: nodes, edges: edges, spacing: spacing, maximumPointCount: maximumPointCount)
        #endif
        var points = arena.list(capacity: 4 * edges.count, of: CGPoint.self)
        guard let size = LayeredFlatLayout.layout(nodes: nodes, edges: edges, points: &points, options: LayeredFlatOptions(spacing),
                                                  maximumVertexCount: maximumPointCount, arena: arena) else {
            return nil
        }
        var page = RequirementPageAssembly(measured: measured, axes: FlowchartFlowAxes(direction: diagram.direction, alongExtent: CGFloat(size.height)),
                                           flowNodes: nodes)
        page.placeRelations(layeredEdgeIndices: layered.elements, nodes: nodes, edges: edges, points: points.elements)
        page.placeSelfLoops()
        return (page, CGSize(width: size.width, height: size.height))
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
    private var relations: [RequirementPlacedRelation?]

    init(measured: RequirementMeasurement, axes: FlowchartFlowAxes, flowNodes: ScratchSpan<LayeredFlatNode>) {
        self.measured = measured
        self.axes = axes
        var centers: [CGPoint] = []
        centers.reserveCapacity(flowNodes.count)
        for node in flowNodes { centers.append(axes.pagePoint(CGPoint(x: node.x, y: node.y))) }
        self.centers = centers
        relations = Array(repeating: nil, count: measured.edges.count)
    }

    /// The relations between two boxes, along their routes; `layeredEdgeIndices[i]` is the edge of the flat layout's
    /// `i`-th edge, whose route runs from its source's center to its target's through its path's inner points.
    mutating func placeRelations(layeredEdgeIndices: ScratchSpan<Int>, nodes: ScratchSpan<LayeredFlatNode>, edges laidOut: ScratchSpan<LayeredSpanEdge>,
                                 points: ScratchSpan<CGPoint>) {
        let routes = RankedRoutes(nodes: nodes, edges: laidOut, points: points, axes: axes)
        var ends: [RequirementEdgePorts.End] = []
        ends.reserveCapacity(2 * layeredEdgeIndices.count)
        for layeredIndex in 0..<layeredEdgeIndices.count {
            let edgeIndex = layeredEdgeIndices[layeredIndex]
            let count = routes.count(of: layeredIndex)
            let edge = measured.edges[edgeIndex]
            ends.append(end(of: edgeIndex, isSourceEnd: true, box: edge.source, at: routes.point(0, count: count, of: layeredIndex),
                            next: routes.point(1, count: count, of: layeredIndex)))
            ends.append(end(of: edgeIndex, isSourceEnd: false, box: edge.target, at: routes.point(count - 1, count: count, of: layeredIndex),
                            next: routes.point(count - 2, count: count, of: layeredIndex)))
        }
        var sizes: [CGSize] = []
        sizes.reserveCapacity(measured.boxes.count)
        for box in measured.boxes { sizes.append(box.size) }
        let ports = RequirementEdgePorts(ends: ends, edgeCount: measured.edges.count, centers: centers, sizes: sizes)
        for layeredIndex in 0..<layeredEdgeIndices.count {
            let edgeIndex = layeredEdgeIndices[layeredIndex]
            guard let sourcePort = ports.sourcePoints[edgeIndex], let targetPort = ports.targetPoints[edgeIndex] else { continue }
            let count = routes.count(of: layeredIndex)
            var routePoints: [CGPoint] = []
            routePoints.reserveCapacity(count)
            routePoints.append(sourcePort)
            for index in 1..<(count - 1) { routePoints.append(routes.point(index, count: count, of: layeredIndex)) }
            routePoints.append(targetPort)
            let edge = measured.edges[edgeIndex]
            let drawn = DiagramRouteDrawing.path(through: routePoints, flowIsVertical: axes.flowIsVertical,
                                                 startTrim: edge.isContainment ? 2 * RequirementLayoutEngine.containmentRadius : 0, endTrim: 0)
            let mark: RequirementRelationMark = edge.isContainment
                ? .containment(point: sourcePort, towardBox: CGVector(dx: -drawn.startDirection.dx, dy: -drawn.startDirection.dy))
                : .arrow(tip: targetPort, direction: drawn.endDirection)
            let laidOutEdge = laidOut[layeredIndex]
            let textCenter = laidOutEdge.labelWidth > 0 ? axes.pagePoint(laidOutEdge.labelCenter)
                : CGPoint(x: (sourcePort.x + targetPort.x) / 2, y: (sourcePort.y + targetPort.y) / 2)
            relations[edgeIndex] = RequirementPlacedRelation(kind: edge.kind, path: drawn.path, mark: mark, text: edge.text.centered(at: textCenter))
        }
    }

    /// The flat layout's routes on the page, each from its source's center to its target's through its path's inner points.
    private struct RankedRoutes {
        let nodes: ScratchSpan<LayeredFlatNode>
        let edges: ScratchSpan<LayeredSpanEdge>
        let points: ScratchSpan<CGPoint>
        let axes: FlowchartFlowAxes

        func count(of layeredIndex: Int) -> Int {
            let edge = edges[layeredIndex]
            return edge.pointStart >= 0 && edge.pointCount > 2 ? edge.pointCount : 2
        }

        /// The route's point `index` on the page, of `count`: the centers at its ends, the path's inner points between.
        func point(_ index: Int, count: Int, of layeredIndex: Int) -> CGPoint {
            let edge = edges[layeredIndex]
            let node = index == 0 ? edge.tail : index == count - 1 ? edge.head : -1
            return axes.pagePoint(node >= 0 ? CGPoint(x: nodes[node].x, y: nodes[node].y) : points[edge.pointStart + index])
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
                relations[edgeIndex] = RequirementPlacedRelation(kind: edge.kind, path: loop.path, mark: mark, text: edge.text.centered(at: loop.textCenter))
            }
        }
    }

    /// The finished layout: the layout's `extent` moved 8 points inside the page, below the title and centered under it
    /// when the title is wider, as Pele frames it.
    func finished(extent: CGSize, font: DiagramFont, title: DiagramMeasuredText?) -> RequirementLayout {
        let padding = RequirementLayoutEngine.padding
        let titleSize = title?.size ?? .zero
        let titleHeight = titleSize.height > 0 ? titleSize.height + RequirementLayoutEngine.titleGap : 0
        let innerWidth = max(extent.width, titleSize.width)
        let offset = CGVector(dx: padding + (innerWidth - extent.width) / 2, dy: padding + titleHeight)
        let size = CGSize(width: (innerWidth + 2 * padding).rounded(.up), height: (extent.height + titleHeight + 2 * padding).rounded(.up))
        let placedTitle = title.flatMap { title in title.lineCount == 0 ? nil : title.centered(at: CGPoint(x: size.width / 2, y: padding + titleSize.height / 2)) }
        var boxes: [RequirementPlacedBox] = []
        boxes.reserveCapacity(measured.boxes.count)
        var fieldTexts: [DiagramMeasuredText] = []
        fieldTexts.reserveCapacity(2 * measured.rows.count)
        for box in measured.boxes.indices { boxes.append(placedBox(measured.boxes[box], at: centers[box], offset: offset, fieldTexts: &fieldTexts)) }
        var placedRelations: [RequirementPlacedRelation] = []
        placedRelations.reserveCapacity(relations.count)
        for relation in relations {
            guard var placed = relation else { continue }
            placed.translate(by: offset)
            placedRelations.append(placed)
        }
        return RequirementLayout(size: size, font: font, lines: measured.lines, placedBoxes: boxes, fieldTexts: fieldTexts, placedRelations: placedRelations,
                                 placedTitle: placedTitle, unappliedStatementCount: measured.unappliedStatementCount)
    }

    /// A box with its texts placed around `center`, then moved by `offset`: each place found around `center` and moved as
    /// `translated(by:)` moves it; its fields' lines appended to `fieldTexts`, the names' then the values'.
    private func placedBox(_ box: RequirementMeasuredBox, at center: CGPoint, offset: CGVector, fieldTexts: inout [DiagramMeasuredText]) -> RequirementPlacedBox {
        let frame = CGRect(x: center.x - box.size.width / 2, y: center.y - box.size.height / 2, width: box.size.width, height: box.size.height)
        let headTop = frame.minY + RequirementMeasurement.paddingAlong
        let stereotype = box.stereotype.centered(at: CGPoint(x: center.x, y: headTop + box.stereotype.size.height / 2).translated(by: offset))
        let name = box.name.centered(at: CGPoint(x: center.x, y: headTop + box.stereotype.size.height + box.name.size.height / 2).translated(by: offset))
        let movedFrame = frame.offsetBy(dx: offset.dx, dy: offset.dy)
        guard box.rowCount > 0 else {
            return RequirementPlacedBox(frame: movedFrame, isRequirement: box.isRequirement, stereotype: stereotype, name: name, dividerY: nil,
                                        fieldNames: fieldTexts.count..<fieldTexts.count, fieldValues: fieldTexts.count..<fieldTexts.count, style: box.style)
        }
        let divider = frame.minY + box.headHeight
        let keyLeft = frame.minX + RequirementMeasurement.paddingAcross
        let valueLeft = keyLeft + box.keyWidth + RequirementMeasurement.columnGap
        // A field's name or value of several lines is drawn as a text for each line.
        let namesStart = fieldTexts.count
        var rowTop = divider + RequirementMeasurement.paddingAlong
        for row in box.rowIndices {
            appendStartingAt(measured.rows[row].key, left: keyLeft, top: rowTop, offset: offset, to: &fieldTexts)
            rowTop += measured.rows[row].height + RequirementMeasurement.rowGap
        }
        let valuesStart = fieldTexts.count
        rowTop = divider + RequirementMeasurement.paddingAlong
        for row in box.rowIndices {
            appendStartingAt(measured.rows[row].value, left: valueLeft, top: rowTop, offset: offset, to: &fieldTexts)
            rowTop += measured.rows[row].height + RequirementMeasurement.rowGap
        }
        return RequirementPlacedBox(frame: movedFrame, isRequirement: box.isRequirement, stereotype: stereotype, name: name, dividerY: divider + offset.dy,
                                    fieldNames: namesStart..<valuesStart, fieldValues: valuesStart..<fieldTexts.count, style: box.style)
    }

    /// The text's lines, each starting at `left`, the first line's box starting at `top`, as Pele writes a field, moved by
    /// `offset` (as `DiagramTextBlock.lineBlock(at:center:)` cuts a block of several lines, each line's place then moved).
    private func appendStartingAt(_ text: DiagramMeasuredText, left: CGFloat, top: CGFloat, offset: CGVector, to texts: inout [DiagramMeasuredText]) {
        let placed = text.centered(at: CGPoint(x: left + text.size.width / 2, y: top + text.size.height / 2))
        guard placed.lineCount > 1 else { return texts.append(placed.translated(by: offset)) }
        let lineLeft = placed.center.x - placed.size.width / 2
        let lineTop = placed.center.y - placed.size.height / 2
        for index in 0..<Int(placed.lineCount) {
            let lineWidth = measured.lines[Int(placed.firstLine) + index].width
            let center = CGPoint(x: lineLeft + lineWidth / 2, y: lineTop + (CGFloat(index) + 0.5) * placed.lineHeight)
            let line = DiagramMeasuredText(firstLine: placed.firstLine + Int32(index), lineCount: 1, width: lineWidth, height: placed.lineHeight,
                                           lineHeight: placed.lineHeight, fontSize: placed.fontSize, hasEmphasis: placed.hasEmphasis, center: center)
            texts.append(line.translated(by: offset))
        }
    }
}
