/**
 * File: LayeredCompoundBox.swift
 * ------------------------------
 * Layer: Core
 * Description: A level of Pele's compound layout as a box: its size around its content and its turn onto the page.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 24/11/2026
 */

import CoreGraphics

/// The box a level's content is laid out in: the content's flow space turned onto the page in the level's direction
/// (flipped for bottom-to-top and right-to-left), centred across inside the group's padding, below its top padding.
struct LayeredCompoundBox {
    let direction: LayeredDirection
    let contentSize: LayeredFlatResult
    let width: Double
    let height: Double
    private let offsetX: Double
    private let offsetY: Double

    init(direction: LayeredDirection, size: LayeredFlatResult, group: LayeredCompoundNode?) {
        self.direction = direction
        contentSize = size
        let isVertical = direction.runsVertically
        let contentWidth = isVertical ? size.width : size.height
        let contentHeight = isVertical ? size.height : size.width
        width = max(contentWidth + 2 * (group?.paddingSide ?? 0), group?.minimumWidth ?? 0)
        height = contentHeight + (group?.paddingTop ?? 0) + (group?.paddingBottom ?? 0)
        offsetX = (width - contentWidth) / 2
        offsetY = group?.paddingTop ?? 0
    }

    func pagePoint(_ flow: CGPoint) -> CGPoint {
        let isVertical = direction.runsVertically
        let along = direction.flips ? contentSize.height - flow.y : flow.y
        return CGPoint(x: offsetX + (isVertical ? flow.x : along), y: offsetY + (isVertical ? along : flow.x))
    }

    /// `points` turned onto the page, each run into along the level's flow, appended to `route`.
    func appendRoute(_ points: ScratchSpan<CGPoint>, to route: inout [LayeredRoutePoint]) {
        route.reserveCapacity(route.count + points.count)
        for point in points { route.append(LayeredRoutePoint(point: pagePoint(point), runsHorizontally: !direction.runsVertically)) }
    }

    /// The point on `side` of the box in line with `point`.
    func borderPoint(on side: DiagramSide, from point: CGPoint) -> CGPoint {
        switch side {
        case .top: CGPoint(x: point.x, y: 0)
        case .bottom: CGPoint(x: point.x, y: height)
        case .left: CGPoint(x: 0, y: point.y)
        case .right: CGPoint(x: width, y: point.y)
        }
    }
}

extension LayeredCompoundLayout {
    /// A port on the side the flow starts or ends at: its edge's route in the level (`flowRoute`, in flow space) runs on
    /// to the border.
    mutating func placeBorderPort(_ port: Int, route flowRoute: ScratchSpan<CGPoint>, box: LayeredCompoundBox) {
        let isOutgoing = ports[port].isOutgoing
        let end = box.pagePoint(isOutgoing ? flowRoute[flowRoute.count - 1] : flowRoute[0])
        let border = box.borderPoint(on: ports[port].side, from: end)
        let borderPoint = LayeredRoutePoint(point: border, runsHorizontally: !box.direction.runsVertically)
        let start = routePoints.count
        if !isOutgoing { routePoints.append(borderPoint) }
        box.appendRoute(flowRoute, to: &routePoints)
        if isOutgoing { routePoints.append(borderPoint) }
        ports[port].borderPoint = border
        ports[port].routeStart = start
        ports[port].routeCount = routePoints.count - start
    }

    /// A port on a side across the flow: straight from its item's side, or from the port of the group its edge passes
    /// into, to the border.
    mutating func placeSidePort(_ port: Int, box: LayeredCompoundBox) {
        let record = ports[port]
        let item = nodes[record.inner]
        var inner = CGPoint(x: item.x, y: item.y)
        let innerPort = item.isGroup && endsBelow(record.inner, edge: record.edgeIndex, isOutgoing: record.isOutgoing)
            ? self.port(in: levelOfGroup[record.inner], edge: record.edgeIndex, isOutgoing: record.isOutgoing) : -1
        if innerPort >= 0 {
            inner.x += ports[innerPort].borderPoint.x - item.width / 2
            inner.y += ports[innerPort].borderPoint.y - item.height / 2
        } else {
            switch record.side {
            case .top: inner.y -= item.height / 2
            case .bottom: inner.y += item.height / 2
            case .left: inner.x -= item.width / 2
            case .right: inner.x += item.width / 2
            }
        }
        let border = box.borderPoint(on: record.side, from: inner)
        let runsHorizontally = !record.side.isHorizontal
        let innerPoint = LayeredRoutePoint(point: inner, runsHorizontally: runsHorizontally)
        let borderPoint = LayeredRoutePoint(point: border, runsHorizontally: runsHorizontally)
        ports[port].borderPoint = border
        ports[port].routeStart = routePoints.count
        ports[port].routeCount = 2
        routePoints.append(record.isOutgoing ? innerPoint : borderPoint)
        routePoints.append(record.isOutgoing ? borderPoint : innerPoint)
    }
}
