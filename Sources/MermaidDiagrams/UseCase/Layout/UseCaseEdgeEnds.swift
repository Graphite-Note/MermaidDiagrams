/**
 * File: UseCaseEdgeEnds.swift
 * ---------------------------
 * Layer: Core
 * Description: Where a use case diagram's lines meet its nodes, as Pele's attachEnds puts them: the ends on one side of
 *              a node spread along it in the order they fan out, each on the node's outline, an actor's at its figure;
 *              the routes an array of the cluster layout's or a use case layout's in a scratch arena.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 25/11/2026
 */

import CoreGraphics

/// The layout brings every edge that ends on one side of a node to that side. These spread them along the side, at
/// most 14 points apart, in the order they fan out, and put each on the node's outline.
enum UseCaseEdgeEnds {
    static let portGap: CGFloat = 14

    /// A route's end: which route, its first or last point, where the route goes next across the side it meets, and
    /// its place among the ends of that side in the order they were found.
    private struct End {
        /// The node's place times 4 and the side's number.
        let key: Int32
        let route: Int32
        let isFirst: Bool
        let toward: CGFloat
        var place: Int32
    }

    /// Each route's first and last points moved onto the outlines of `sources[route]` and `targets[route]`.
    static func attach(_ routes: inout [LayeredClusterRoute], sources: [Int], targets: [Int], centers: [CGPoint], views: [UseCaseNodeView]) {
        DiagramScratchArena.withCurrentThread { arena in attach(&routes, sources: sources, targets: targets, centers: centers, views: views, arena: arena) }
    }

    /// `attach` of routes kept in a scratch arena, with the nodes' places and centers in spans of it.
    static func attach(_ routes: inout UseCaseRoutes, sources: ScratchSpan<Int>, targets: ScratchSpan<Int>, centers: ScratchSpan<CGPoint>,
                       views: [UseCaseNodeView]) {
        DiagramScratchArena.withCurrentThread { arena in attach(&routes, sources: sources, targets: targets, centers: centers, views: views, arena: arena) }
    }

    /// `attach` with its lists in `arena`: the ends grouped by node and side, the groups in the order their first end was
    /// found, each group's ends in the order found, then each group sorted as a list of its ends would be.
    private static func attach<Routes: UseCaseAttachedRoutes, Places: RandomAccessCollection<Int>, Centers: RandomAccessCollection<CGPoint>>(
        _ routes: inout Routes, sources: Places, targets: Places, centers: Centers, views: [UseCaseNodeView], arena: DiagramScratchArena
    ) where Places.Index == Int, Centers.Index == Int {
        let (grouped, groupStarts) = groupedEnds(of: routes, sources: sources, targets: targets, nodeCount: views.count, arena: arena)
        for group in 0..<(groupStarts.count - 1) {
            var ends = UnsafeMutableBufferPointer(rebasing: grouped.buffer[groupStarts[group]..<groupStarts[group + 1]])
            let key = Int(ends[0].key)
            let node = key / 4
            let side = DiagramSide.allCases[key % 4]
            let step = ends.count > 1 ? min(portGap, sideLength(of: views[node], side: side) / CGFloat(ends.count - 1)) : 0
            // The same comparison, on the same ends in the same order, as a list of them sorted.
            ends.sort { first, second in first.toward != second.toward ? first.toward < second.toward : first.place < second.place }
            for (place, end) in ends.enumerated() {
                let along = (CGFloat(place) - CGFloat(ends.count - 1) / 2) * step
                let point = anchor(of: views[node], center: centers[node], side: side, along: along)
                let route = Int(end.route)
                routes.setPoint(point, at: end.isFirst ? 0 : routes.pointCount(ofRoute: route) - 1, ofRoute: route)
            }
        }
    }

    /// Every end of every route of two points or more, grouped by node and side: the groups one after the other in the
    /// order their first end was found, each group's ends in the order found, and where each group starts (one more
    /// start for the end of the last).
    private static func groupedEnds<Routes: UseCaseAttachedRoutes, Places: RandomAccessCollection<Int>>(
        of routes: Routes, sources: Places, targets: Places, nodeCount: Int, arena: DiagramScratchArena
    ) -> (ends: ScratchSpan<End>, groupStarts: ScratchSpan<Int>) where Places.Index == Int {
        let groupOfKey = arena.span(count: 4 * nodeCount, repeating: Int32(-1))
        var groupCounts = arena.list(capacity: 2 * routes.routeCount, of: Int32.self)
        var found = arena.list(capacity: 2 * routes.routeCount, of: End.self)
        for route in 0..<routes.routeCount where routes.pointCount(ofRoute: route) >= 2 {
            for endNumber in 0..<2 {
                let isFirst = endNumber == 0
                let (side, toward) = Self.side(of: route, in: routes, isFirst: isFirst)
                let key = (isFirst ? sources[route] : targets[route]) * 4 + Self.number(of: side)
                var group = groupOfKey[key]
                if group < 0 {
                    group = Int32(groupCounts.count)
                    groupOfKey[key] = group
                    groupCounts.append(0)
                }
                found.append(End(key: Int32(key), route: Int32(route), isFirst: isFirst, toward: toward, place: groupCounts[Int(group)]))
                groupCounts[Int(group)] += 1
            }
        }
        let groupStarts: ScratchSpan<Int> = arena.uninitializedSpan(count: groupCounts.count + 1)
        groupStarts[0] = 0
        for group in 0..<groupCounts.count { groupStarts[group + 1] = groupStarts[group] + Int(groupCounts[group]) }
        let grouped: ScratchSpan<End> = arena.uninitializedSpan(count: found.count)
        for index in 0..<found.count {
            let end = found[index]
            grouped[groupStarts[Int(groupOfKey[Int(end.key)])] + Int(end.place)] = end
        }
        return (grouped, groupStarts)
    }

    /// The side a route leaves its source by or arrives at its target from, along its end segment's flow, and where it
    /// goes next across that side.
    private static func side<Routes: UseCaseAttachedRoutes>(of route: Int, in routes: Routes, isFirst: Bool) -> (DiagramSide, CGFloat) {
        let count = routes.pointCount(ofRoute: route)
        let end = routes.point(isFirst ? 0 : count - 1, ofRoute: route)
        let next = routes.point(isFirst ? 1 : count - 2, ofRoute: route)
        let runsVertically = routes.segmentRunsVertically(isFirst ? 0 : count - 2, ofRoute: route)
        let side: DiagramSide = runsVertically ? (next.y > end.y ? .bottom : .top) : (next.x > end.x ? .right : .left)
        return (side, side.isHorizontal ? next.x : next.y)
    }

    private static func number(of side: DiagramSide) -> Int {
        DiagramSide.allCases.firstIndex(of: side) ?? 0
    }

    /// The point of a node's outline on `side`, `along` away from the middle of that side. Lines meet an actor at its
    /// figure, not at its label.
    static func anchor(of view: UseCaseNodeView, center: CGPoint, side: DiagramSide, along: CGFloat) -> CGPoint {
        let sign: CGFloat = side == .right || side == .bottom ? 1 : -1
        let isUpright = !side.isHorizontal
        var reach = (isUpright ? view.size.width : view.size.height) / 2
        var middle: CGFloat = 0
        if view.form == .actor {
            if isUpright {
                reach = UseCaseNodeMeasurement.figureWidth / 2 + 3
                middle = (UseCaseNodeMeasurement.figureHeight - view.size.height) / 2
            } else {
                reach += 2
            }
        } else if view.form == .ellipse {
            let span = (isUpright ? view.size.height : view.size.width) / 2
            reach *= max(1 - (along / span) * (along / span), 0).squareRoot()
        }
        return isUpright ? CGPoint(x: center.x + sign * reach, y: center.y + middle + along) : CGPoint(x: center.x + along, y: center.y + sign * reach)
    }

    /// How much of a side edges may spread over.
    static func sideLength(of view: UseCaseNodeView, side: DiagramSide) -> CGFloat {
        let isUpright = !side.isHorizontal
        if view.form == .actor { return isUpright ? UseCaseNodeMeasurement.figureHeight * 0.5 : UseCaseNodeMeasurement.figureWidth * 0.6 }
        let length = isUpright ? view.size.height : view.size.width
        return view.form == .ellipse ? length * 0.6 : length - 16
    }
}

/// Routes whose ends `UseCaseEdgeEnds` moves: an array of the cluster layout's routes, or a use case layout's routes in a
/// scratch arena.
protocol UseCaseAttachedRoutes {
    var routeCount: Int { get }
    func pointCount(ofRoute route: Int) -> Int
    func point(_ index: Int, ofRoute route: Int) -> CGPoint
    func segmentRunsVertically(_ segment: Int, ofRoute route: Int) -> Bool
    mutating func setPoint(_ point: CGPoint, at index: Int, ofRoute route: Int)
}

extension Array: UseCaseAttachedRoutes where Element == LayeredClusterRoute {
    var routeCount: Int { count }
    func pointCount(ofRoute route: Int) -> Int { self[route].points.count }
    func point(_ index: Int, ofRoute route: Int) -> CGPoint { self[route].points[index] }
    func segmentRunsVertically(_ segment: Int, ofRoute route: Int) -> Bool { self[route].segmentsRunVertically[segment] }
    mutating func setPoint(_ point: CGPoint, at index: Int, ofRoute route: Int) { self[route].points[index] = point }
}

extension UseCaseRoutes: UseCaseAttachedRoutes {
    var routeCount: Int { count }
    func pointCount(ofRoute route: Int) -> Int { counts[route] }
    func point(_ index: Int, ofRoute route: Int) -> CGPoint { points[starts[route] + index] }
    func segmentRunsVertically(_ segment: Int, ofRoute route: Int) -> Bool { segmentsRunVertically[starts[route] + segment] }
    func setPoint(_ point: CGPoint, at index: Int, ofRoute route: Int) { points[starts[route] + index] = point }
}
