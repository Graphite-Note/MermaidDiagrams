/**
 * File: LanePlacedPass.swift
 * --------------------------
 * Layer: Core
 * Description: A lane layout pass put on the page, on spans of the thread's scratch arena: the boxes at their ranks and
 *              places, the lanes the length of the diagram, the groups inside lanes around what they hold, and the
 *              edges' routes through the ranks or straight to a group's border, every route a range of one list.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

import CoreGraphics

/// A route on the page as Pele's lane layout keeps it: points, each with the axis of the flow the segment arriving at it
/// follows (0 for a vertical flow, 1 for a horizontal one).
struct LaneRoutePoint: Equatable {
    var point: CGPoint
    var axis: Int
}

/// A point in flow space: across the flow and along it.
struct LaneFlowPoint {
    var across: CGFloat
    var along: CGFloat
}

/// A pass of the lane layout on the page: where Pele's `place` leaves its nodes and edges. Each graph edge's route is
/// `routeCounts[edge]` points from `routeStarts[edge]` of `routePoints`, none for an edge from a box to itself; a route
/// replaced later is written again at the list's end.
struct LanePlacedPass {
    let pass: LanePass
    let bands: LaneBands
    let frames: ScratchSpan<CGRect>
    var routePoints: ScratchList<LaneRoutePoint>
    let routeStarts: ScratchSpan<Int>
    let routeCounts: ScratchSpan<Int>
    let labelCenters: ScratchSpan<CGPoint>

    init(pass: LanePass, bands: LaneBands, arena: DiagramScratchArena) {
        self.pass = pass
        self.bands = bands
        let boxes = pass.setup.boxes
        let frames: ScratchSpan<CGRect> = arena.uninitializedSpan(count: boxes.count)
        for box in 0..<boxes.count { frames[box] = CGRect(origin: .zero, size: boxes[box].size) }
        self.frames = frames
        let edgeCount = pass.setup.graphEdges.count
        routePoints = arena.list(capacity: 2 * edgeCount + pass.vertexCount, of: LaneRoutePoint.self)
        routeStarts = arena.span(count: edgeCount, repeating: 0)
        routeCounts = arena.span(count: edgeCount, repeating: 0)
        labelCenters = arena.span(count: edgeCount, repeating: CGPoint.zero)
        placeItems()
        placeLanes()
        placeGroups(arena: arena)
        routeRankedEdges()
        routeGroupEdges()
    }

    var runsAcross: Bool { pass.setup.runsAcross }
    var axis: Int { runsAcross ? 1 : 0 }

    /// A point of flow space (across, along) on the page, the flow mirrored after the lanes' titles where it runs up or left.
    @inline(__always)
    func pagePoint(across: CGFloat, along: CGFloat) -> CGPoint {
        let flowed = pass.setup.isFlipped ? pass.titleDepth + bands.length - along : along
        return runsAcross ? CGPoint(x: flowed, y: across) : CGPoint(x: across, y: flowed)
    }

    /// The middle of an item's or a passing point's band along the flow.
    @inline(__always)
    func bandMiddle(of vertex: Int) -> CGFloat {
        (bands.starts[pass.rank[vertex]] + bands.ends[pass.rank[vertex]]) / 2
    }

    /// The route of graph edge `edgeIndex`, as a span of the points list: valid until the list next grows.
    @inline(__always)
    func route(of edgeIndex: Int) -> ScratchSpan<LaneRoutePoint> {
        routePoints.elements.part(routeStarts[edgeIndex]..<(routeStarts[edgeIndex] + routeCounts[edgeIndex]))
    }

    private func placeItems() {
        for (item, box) in pass.setup.items.enumerated() {
            let center = pagePoint(across: pass.centers[item], along: bandMiddle(of: item))
            frames[box] = CGRect(x: center.x - frames[box].width / 2, y: center.y - frames[box].height / 2, width: frames[box].width, height: frames[box].height)
        }
    }

    /// Each lane a band across the flow the length of the diagram.
    private func placeLanes() {
        for (slot, box) in pass.setup.lanes.enumerated() {
            let start = pass.laneStarts[slot]
            let breadth = pass.laneStarts[slot + 1] - start
            frames[box] = runsAcross ? CGRect(x: 0, y: start, width: bands.length, height: breadth) : CGRect(x: start, y: 0, width: breadth, height: bands.length)
        }
    }

    /// The groups inside lanes around their members, the deepest first, each its padding around what it holds and at least
    /// its least width.
    private func placeGroups(arena: DiagramScratchArena) {
        let setup = pass.setup
        let boxes = setup.boxes
        let mark = arena.mark()
        defer { arena.release(to: mark) }
        let depth = arena.span(count: boxes.count, repeating: 0)
        var inner = arena.list(capacity: 8, of: Int.self)
        for box in 0..<boxes.count where boxes[box].isGroup && setup.laneSlots[box] == -1 && setup.itemOfBox[box] == -1 {
            var parent = boxes[box].parent
            while let current = parent, depth[box] < LaneLayoutItems.maximumHops {
                depth[box] += 1
                parent = boxes[current].parent
            }
            inner.append(box)
        }
        guard !inner.isEmpty else { return }
        inner.sortStably(in: arena) { first, second in (depth[second], first) < (depth[first], second) }
        let held: ScratchSpan<CGRect> = arena.uninitializedSpan(count: boxes.count)
        let holds = arena.span(count: boxes.count, repeating: false)
        func grow(_ group: Int?, by frame: CGRect) {
            guard let group, setup.laneSlots[group] == -1 else { return }
            held[group] = holds[group] ? held[group].union(frame) : frame
            holds[group] = true
        }
        for box in setup.items { grow(boxes[box].parent, by: frames[box]) }
        for group in inner {
            guard holds[group] else { continue }
            let content = held[group]
            let padding = boxes[group].padding
            let width = max(content.width + 2 * padding.side, boxes[group].minimumWidth)
            frames[group] = CGRect(x: content.midX - width / 2, y: content.minY - padding.top, width: width,
                                   height: content.height + padding.top + padding.bottom)
            grow(boxes[group].parent, by: frames[group])
        }
    }
}

extension LanePlacedPass {
    /// Each ranked edge from the end of its upper item's box through its passing points to the start of its lower item's,
    /// in its own direction; its text at its passing point's band, or halfway.
    private mutating func routeRankedEdges() {
        let edges = pass.setup.edges
        for edgeIndex in 0..<edges.count {
            let edge = edges[edgeIndex]
            let upper = edge.upper
            let lower = edge.lower
            let start = routePoints.count
            let upperRank = pass.rank[upper]
            appendPoint(across: pass.centers[upper], along: bands.ends[upperRank] - (bands.ends[upperRank] - bands.starts[upperRank] - pass.along[upper]) / 2)
            let first = pass.firstPassingPoint[edgeIndex]
            if first >= 0 {
                for vertex in first..<(first + pass.spans[edgeIndex] - 1) {
                    let vertexRank = pass.rank[vertex]
                    appendPoint(across: pass.centers[vertex], along: bands.starts[vertexRank])
                    if bands.ends[vertexRank] > bands.starts[vertexRank] { appendPoint(across: pass.centers[vertex], along: bands.ends[vertexRank]) }
                }
            }
            let lowerRank = pass.rank[lower]
            appendPoint(across: pass.centers[lower], along: bands.starts[lowerRank] + (bands.ends[lowerRank] - bands.starts[lowerRank] - pass.along[lower]) / 2)
            let count = routePoints.count - start
            if edge.isReversed { routePoints.elements.reverse(start..<(start + count)) }
            routeStarts[edge.edgeIndex] = start
            routeCounts[edge.edgeIndex] = count
            let label = pass.labelVertex[edgeIndex]
            if label >= 0 {
                labelCenters[edge.edgeIndex] = pagePoint(across: pass.centers[label], along: bandMiddle(of: label))
            } else {
                labelCenters[edge.edgeIndex] = Self.midpoint(routePoints[start].point, routePoints[start + count - 1].point)
            }
        }
    }

    @inline(__always)
    private mutating func appendPoint(across: CGFloat, along: CGFloat) {
        routePoints.append(LaneRoutePoint(point: pagePoint(across: across, along: along), axis: axis))
    }

    /// An edge that starts or ends at a lane or a group runs straight to its border.
    private mutating func routeGroupEdges() {
        let edges = pass.setup.graphEdges
        for edgeIndex in 0..<edges.count where routeCounts[edgeIndex] == 0 && edges[edgeIndex].source != edges[edgeIndex].target {
            let edge = edges[edgeIndex]
            let start = Self.border(of: frames[edge.source], toward: frames[edge.target])
            let end = Self.border(of: frames[edge.target], toward: frames[edge.source])
            let flatAxis = abs(end.x - start.x) > abs(end.y - start.y) ? 1 : 0
            routeStarts[edgeIndex] = routePoints.count
            routeCounts[edgeIndex] = 2
            routePoints.append(LaneRoutePoint(point: start, axis: flatAxis))
            routePoints.append(LaneRoutePoint(point: end, axis: flatAxis))
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
