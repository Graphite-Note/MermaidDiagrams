/**
 * File: UseCasePageAssembly.swift
 * -------------------------------
 * Layer: Core
 * Description: Puts a placed use case diagram on the page as Pele's renderUsecase does: everything moved inside the
 *              padding below the title, the boundaries' titles clear of the lines, the lines' ends on the outlines,
 *              loops beside their nodes, and each node's texts placed.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

extension UseCaseLayoutPass {
    func assembled<Measurer>(_ placement: LayeredClusterPlacement, measurers: inout UseCaseTextMeasurers<Measurer>) -> UseCaseLayout {
        let padding = UseCaseLayoutEngine.padding
        let titleMeasurer = measurers.measurer(size: fontSize, isBold: true)
        var title = diagram.title.flatMap { title in UseCaseTextLabel.titleBlock(title, measurer: titleMeasurer, room: UseCaseNodeMeasurement.titleRoom) }
        let titleSize = title?.size ?? .zero
        let titleHeight = titleSize.height > 0 ? titleSize.height + UseCaseLayoutEngine.titleGap : 0
        let inner = max(placement.size.width, titleSize.width)
        let offset = CGVector(dx: padding + (inner - placement.size.width) / 2, dy: padding + titleHeight)
        let size = CGSize(width: (inner + 2 * padding).rounded(.up), height: (placement.size.height + titleHeight + 2 * padding).rounded(.up))
        title?.center = CGPoint(x: size.width / 2, y: padding + titleSize.height / 2)
        let centers = views.indices.map { place in
            views[place].node.isGroup ? CGPoint.zero : placement.nodeCenters[layoutPlaces[place]].translated(by: offset)
        }
        let frames = placement.clusterFrames.map { frame in frame.offsetBy(dx: offset.dx, dy: offset.dy) }
        var routes = placement.edgeRoutes.map { route in
            LayeredClusterRoute(points: route.points.map { point in point.translated(by: offset) }, segmentsRunVertically: route.segmentsRunVertically)
        }
        let crossings = UseCaseBoundaryTitles.crossings(of: routes)
        let laidOut = laidOutEdges
        UseCaseEdgeEnds.attach(&routes, sources: laidOut.map(\.source), targets: laidOut.map(\.target), centers: centers, views: views)
        let labelCenters = placement.edgeLabelCenters.map { center in center?.translated(by: offset) }
        let boundaries = views.indices.filter { place in views[place].node.isGroup }.map { place in
            UseCaseBoundaryTitles.boundary(views[place], frame: frames[layoutPlaces[place]], crossings: crossings)
        }
        let edges = placedEdges(routes: routes, labelCenters: labelCenters, centers: centers, boundaries: boundaries)
        let nodes = views.indices.filter { place in !views[place].node.isGroup }.map { place in placedNode(views[place], center: centers[place]) }
        return UseCaseLayout(size: size, font: font, title: title, boundaries: boundaries, edges: edges, nodes: nodes)
    }

    /// The edges in the order drawn: each routed one along its route, each loop beside its node.
    private func placedEdges(routes: [LayeredClusterRoute], labelCenters: [CGPoint?], centers: [CGPoint],
                             boundaries: [UseCaseLayoutBoundary]) -> [UseCaseLayoutEdge] {
        let fills = boundaries.filter { boundary in boundary.look.paintsFill }
        var routeIndex = 0
        var loopsSeen: [Int: Int] = [:]
        var edges: [UseCaseLayoutEdge] = []
        for drawn in drawnEdges {
            let edge = graph.edges[drawn.edge]
            let startTrim = Self.trim(of: edge.startMarker)
            let endTrim = Self.trim(of: edge.endMarker)
            var line: UseCaseEdgeLine
            if drawn.source == drawn.target {
                let loopIndex = loopsSeen[drawn.source, default: 0]
                loopsSeen[drawn.source] = loopIndex + 1
                let loop = UseCaseSelfLoops.loop(of: views[drawn.source], center: centers[drawn.source], loopIndex: loopIndex, isSideways: isSideways,
                                                 labelSize: drawn.label.size, startTrim: startTrim, endTrim: endTrim)
                line = UseCaseEdgeLine(path: loop.path, startTip: loop.startTip, startDirection: loop.startDirection, endTip: loop.endTip,
                                       endDirection: loop.endDirection, labelCenter: loop.labelCenter)
            } else {
                let route = routes[routeIndex]
                let labelCenter = labelCenters[routeIndex]
                routeIndex += 1
                guard route.points.count >= 2 else { continue }
                let path = DiagramRouteDrawing.path(through: route.points, segmentsRunVertically: route.segmentsRunVertically, startTrim: startTrim, endTrim: endTrim)
                let first = route.points[0]
                let last = route.points[route.points.count - 1]
                line = UseCaseEdgeLine(path: path.path, startTip: first, startDirection: CGVector(dx: -path.startDirection.dx, dy: -path.startDirection.dy),
                                       endTip: last, endDirection: path.endDirection,
                                       labelCenter: labelCenter ?? CGPoint(x: (first.x + last.x) / 2, y: (first.y + last.y) / 2))
            }
            edges.append(line.edge(edge, label: drawn.label, fills: fills))
        }
        return edges
    }

    /// How much of a line its mark takes: Pele's `markerTrim`, and a generalization's triangle its length.
    static func trim(of marker: UseCaseMarker) -> CGFloat {
        switch marker {
        case .none: 0
        case .point: DiagramEdgeMark.arrowLength - 1
        case .circle: DiagramEdgeMark.arrowLength
        case .cross: 4
        case .hollowTriangle: UseCaseEdgeLine.extensionLength
        }
    }

    /// A node with its texts placed around its center, as Pele draws them.
    private func placedNode(_ view: UseCaseNodeView, center: CGPoint) -> UseCaseLayoutNode {
        let height = view.size.height
        var label = view.label
        var stereotype = view.stereotype
        var rows: [UseCaseLayoutJSONRow] = []
        switch view.form {
        case .actor:
            let top = center.y - height / 2
            stereotype.center = CGPoint(x: center.x, y: top + UseCaseNodeMeasurement.figureHeight + UseCaseNodeMeasurement.figureGap + stereotype.size.height / 2)
            label.center = CGPoint(x: center.x, y: center.y + height / 2 - label.size.height / 2)
        case .json:
            label.center = CGPoint(x: center.x, y: center.y - height / 2 + view.headHeight / 2)
            let left = center.x - view.size.width / 2
            var top = center.y - height / 2 + view.headHeight
            for (key, value, rowHeight) in view.rows {
                var placedKey = key
                placedKey.center = CGPoint(x: left + UseCaseNodeMeasurement.cellPadding + key.size.width / 2, y: top + rowHeight / 2)
                let valueTop = top + rowHeight / 2 - value.size.height / 2
                rows.append(UseCaseLayoutJSONRow(key: placedKey, valueLines: value.placedLines(left: left + view.keyColumnWidth + UseCaseNodeMeasurement.cellPadding,
                                                                                              top: valueTop)))
                top += rowHeight
            }
        default:
            stereotype.center = CGPoint(x: center.x, y: center.y - label.size.height / 2)
            label.center = CGPoint(x: center.x, y: center.y + stereotype.size.height / 2)
        }
        return UseCaseLayoutNode(identifier: view.node.identifier, form: Self.form(of: view), center: center, size: view.size, label: label,
                                 stereotype: stereotype, rows: rows, headHeight: view.headHeight, keyColumnWidth: view.keyColumnWidth, look: view.look)
    }

    private static func form(of view: UseCaseNodeView) -> UseCaseLayoutNodeForm {
        switch view.node.shape {
        case .actor, .hollowActor, .awesomeActor, .iconActor: .actor(view.node.actorType ?? .normal, isBusiness: view.node.isBusiness)
        case .ellipse, .businessEllipse: .ellipse(isBusiness: view.node.isBusiness)
        case .note: .note
        case .jsonTable: .jsonTable
        case .rectangle, .systemBoundary: .rectangle
        }
    }
}
