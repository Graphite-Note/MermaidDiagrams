/**
 * File: ReferenceLanePlacedPass.swift
 * -----------------------------------
 * Layer: Tests
 * Description: The 0.7.0 LanePlacedPass kept as the reference the lane layout on the scratch arena is checked against:
 *              a lane layout pass put on the page: the boxes at their ranks and places, the lanes the length of the
 *              diagram, the groups inside lanes around what they hold, and the edges' routes through the ranks or
 *              straight to a group's border.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// A route on the page as Pele's lane layout keeps it: points, each with the axis of the flow the segment arriving at it
/// follows (0 for a vertical flow, 1 for a horizontal one).
struct ReferenceLaneRoutePoint: Equatable {
    var point: CGPoint
    var axis: Int
}

/// A pass of the lane layout on the page: where Pele's `place` leaves its nodes and edges.
struct ReferenceLanePlacedPass {
    let pass: ReferenceLanePass
    let bands: ReferenceLaneBands
    private(set) var frames: [CGRect]
    /// By the graph's edges; empty for an edge from a box to itself.
    var routes: [[ReferenceLaneRoutePoint]]
    var labelCenters: [CGPoint]

    init(pass: ReferenceLanePass, bands: ReferenceLaneBands) {
        self.pass = pass
        self.bands = bands
        let graph = pass.setup.graph
        frames = graph.boxes.map { box in CGRect(origin: .zero, size: box.size) }
        routes = Array(repeating: [], count: graph.edges.count)
        labelCenters = Array(repeating: .zero, count: graph.edges.count)
        placeItems()
        placeLanes()
        placeGroups()
        routeRankedEdges()
        routeGroupEdges()
    }

    var runsAcross: Bool { pass.setup.runsAcross }
    var axis: Int { runsAcross ? 1 : 0 }

    /// A point of flow space (across, along) on the page, the flow mirrored after the lanes' titles where it runs up or left.
    func pagePoint(across: CGFloat, along: CGFloat) -> CGPoint {
        let flowed = pass.setup.isFlipped ? pass.titleDepth + bands.length - along : along
        return runsAcross ? CGPoint(x: flowed, y: across) : CGPoint(x: across, y: flowed)
    }

    /// The middle of an item's or a passing point's band along the flow.
    func bandMiddle(of vertex: Int) -> CGFloat {
        (bands.starts[pass.rank[vertex]] + bands.ends[pass.rank[vertex]]) / 2
    }

    private mutating func placeItems() {
        for (item, box) in pass.setup.items.enumerated() {
            let center = pagePoint(across: pass.centers[item], along: bandMiddle(of: item))
            frames[box] = CGRect(x: center.x - frames[box].width / 2, y: center.y - frames[box].height / 2, width: frames[box].width, height: frames[box].height)
        }
    }

    /// Each lane a band across the flow the length of the diagram.
    private mutating func placeLanes() {
        for (slot, box) in pass.setup.lanes.enumerated() {
            let start = pass.laneStarts[slot]
            let breadth = pass.laneStarts[slot + 1] - start
            frames[box] = runsAcross ? CGRect(x: 0, y: start, width: bands.length, height: breadth) : CGRect(x: start, y: 0, width: breadth, height: bands.length)
        }
    }

    /// The groups inside lanes around their members, the deepest first, each its padding around what it holds and at least
    /// its least width.
    private mutating func placeGroups() {
        let boxes = pass.setup.graph.boxes
        var depth = [Int](repeating: 0, count: boxes.count)
        var inner: [Int] = []
        for box in boxes.indices where boxes[box].isGroup && pass.setup.laneSlots[box] == nil && pass.setup.itemOfBox[box] == nil {
            var parent = boxes[box].parent
            while let current = parent, depth[box] < ReferenceLaneLayoutItems.maximumHops {
                depth[box] += 1
                parent = boxes[current].parent
            }
            inner.append(box)
        }
        inner.sort { first, second in (depth[second], first) < (depth[first], second) }
        var held = [CGRect?](repeating: nil, count: boxes.count)
        func grow(_ group: Int?, by frame: CGRect) {
            guard let group, pass.setup.laneSlots[group] == nil else { return }
            held[group] = held[group].map { box in box.union(frame) } ?? frame
        }
        for box in pass.setup.items { grow(boxes[box].parent, by: frames[box]) }
        for group in inner {
            guard let content = held[group] else { continue }
            let padding = boxes[group].padding
            let width = max(content.width + 2 * padding.side, boxes[group].minimumWidth)
            frames[group] = CGRect(x: content.midX - width / 2, y: content.minY - padding.top, width: width,
                                   height: content.height + padding.top + padding.bottom)
            grow(boxes[group].parent, by: frames[group])
        }
    }
}

extension ReferenceLanePlacedPass {
    /// Each ranked edge from the end of its upper item's box through its passing points to the start of its lower item's,
    /// in its own direction; its text at its passing point's band, or halfway.
    private mutating func routeRankedEdges() {
        for (edgeIndex, edge) in pass.setup.edges.enumerated() {
            let upper = edge.upper
            let lower = edge.lower
            var points = [(pass.centers[upper], bands.ends[pass.rank[upper]] - (bands.ends[pass.rank[upper]] - bands.starts[pass.rank[upper]] - pass.along[upper]) / 2)]
            if let first = pass.firstPassingPoint[edgeIndex] {
                for vertex in first..<(first + pass.spans[edgeIndex] - 1) {
                    points.append((pass.centers[vertex], bands.starts[pass.rank[vertex]]))
                    if bands.ends[pass.rank[vertex]] > bands.starts[pass.rank[vertex]] { points.append((pass.centers[vertex], bands.ends[pass.rank[vertex]])) }
                }
            }
            points.append((pass.centers[lower], bands.starts[pass.rank[lower]] + (bands.ends[pass.rank[lower]] - bands.starts[pass.rank[lower]] - pass.along[lower]) / 2))
            var route = points.map { across, along in ReferenceLaneRoutePoint(point: pagePoint(across: across, along: along), axis: axis) }
            if edge.isReversed { route.reverse() }
            routes[edge.edgeIndex] = route
            if let label = pass.labelVertex[edgeIndex] {
                labelCenters[edge.edgeIndex] = pagePoint(across: pass.centers[label], along: bandMiddle(of: label))
            } else {
                labelCenters[edge.edgeIndex] = Self.midpoint(route[0].point, route[route.count - 1].point)
            }
        }
    }

    /// An edge that starts or ends at a lane or a group runs straight to its border.
    private mutating func routeGroupEdges() {
        for (edgeIndex, edge) in pass.setup.graph.edges.enumerated() where routes[edgeIndex].isEmpty && edge.source != edge.target {
            let start = Self.border(of: frames[edge.source], toward: frames[edge.target])
            let end = Self.border(of: frames[edge.target], toward: frames[edge.source])
            let flatAxis = abs(end.x - start.x) > abs(end.y - start.y) ? 1 : 0
            routes[edgeIndex] = [ReferenceLaneRoutePoint(point: start, axis: flatAxis), ReferenceLaneRoutePoint(point: end, axis: flatAxis)]
            labelCenters[edgeIndex] = Self.midpoint(start, end)
        }
    }

    static func midpoint(_ first: CGPoint, _ second: CGPoint) -> CGPoint {
        CGPoint(x: (first.x + second.x) / 2, y: (first.y + second.y) / 2)
    }

    /// Where the line from one box's center to another's leaves the first box; when the other center is inside the box, the
    /// point on the nearest side instead, as Pele's `border` finds it.
    static func border(of from: CGRect, toward to: CGRect) -> CGPoint {
        let deltaX = to.midX - from.midX
        let deltaY = to.midY - from.midY
        let halfWidth = max(from.width / 2, 0.5)
        let halfHeight = max(from.height / 2, 0.5)
        if abs(deltaX) < halfWidth, abs(deltaY) < halfHeight {
            return halfWidth - abs(deltaX) < halfHeight - abs(deltaY) ? CGPoint(x: from.midX + (deltaX < 0 ? -halfWidth : halfWidth), y: to.midY)
                                                                     : CGPoint(x: to.midX, y: from.midY + (deltaY < 0 ? -halfHeight : halfHeight))
        }
        let scale = min(deltaX != 0 ? halfWidth / abs(deltaX) : .infinity, deltaY != 0 ? halfHeight / abs(deltaY) : .infinity)
        return CGPoint(x: from.midX + deltaX * scale, y: from.midY + deltaY * scale)
    }
}
