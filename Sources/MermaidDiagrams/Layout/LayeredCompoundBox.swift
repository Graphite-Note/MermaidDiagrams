/**
 * File: LayeredCompoundBox.swift
 * ------------------------------
 * Layer: Core
 * Description: A level of Pele's compound layout as a box: its size around its content and its turn onto the page.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
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

    func route(_ points: [CGPoint]) -> [LayeredRoutePoint] {
        points.map { point in LayeredRoutePoint(point: pagePoint(point), runsHorizontally: !direction.runsVertically) }
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
    /// A port on the side the flow starts or ends at: its edge's route in the level runs on to the border.
    mutating func placeBorderPort(_ portIndex: Int, of levelIndex: Int, route: [LayeredRoutePoint], box: LayeredCompoundBox) {
        var route = route
        let port = levels[levelIndex].ports[portIndex]
        let end = port.isOutgoing ? route[route.count - 1] : route[0]
        let border = box.borderPoint(on: port.side, from: end.point)
        let borderPoint = LayeredRoutePoint(point: border, runsHorizontally: !box.direction.runsVertically)
        if port.isOutgoing { route.append(borderPoint) } else { route.insert(borderPoint, at: 0) }
        levels[levelIndex].ports[portIndex].borderPoint = border
        levels[levelIndex].ports[portIndex].route = route
    }

    /// A port on a side across the flow: straight from its item's side, or from the port of the group its edge passes
    /// into, to the border.
    mutating func placeSidePort(_ portIndex: Int, of levelIndex: Int, box: LayeredCompoundBox) {
        let port = levels[levelIndex].ports[portIndex]
        let item = nodes[port.inner]
        var inner = CGPoint(x: item.x, y: item.y)
        if item.isGroup && endsBelow(port.inner, edge: port.edgeIndex, isOutgoing: port.isOutgoing),
           let innerPort = levels[levelOfGroup[port.inner]].port(edge: port.edgeIndex, isOutgoing: port.isOutgoing) {
            inner.x += innerPort.borderPoint.x - item.width / 2
            inner.y += innerPort.borderPoint.y - item.height / 2
        } else {
            switch port.side {
            case .top: inner.y -= item.height / 2
            case .bottom: inner.y += item.height / 2
            case .left: inner.x -= item.width / 2
            case .right: inner.x += item.width / 2
            }
        }
        let border = box.borderPoint(on: port.side, from: inner)
        let runsHorizontally = !port.side.isHorizontal
        let innerPoint = LayeredRoutePoint(point: inner, runsHorizontally: runsHorizontally)
        let borderPoint = LayeredRoutePoint(point: border, runsHorizontally: runsHorizontally)
        levels[levelIndex].ports[portIndex].borderPoint = border
        levels[levelIndex].ports[portIndex].route = port.isOutgoing ? [innerPoint, borderPoint] : [borderPoint, innerPoint]
    }
}
