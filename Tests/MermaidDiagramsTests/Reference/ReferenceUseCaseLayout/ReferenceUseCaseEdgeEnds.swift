/**
 * File: ReferenceUseCaseEdgeEnds.swift
 * ------------------------------------
 * Layer: Tests
 * Description: The 0.7.0 UseCaseEdgeEnds kept as the reference the 0.8.0 layout is checked against: where a use case
 *              diagram's lines meet its nodes, as Pele's attachEnds puts them: the ends on one side of a node spread
 *              along it in the order they fan out, each on the node's outline, an actor's at its figure.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 26/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// The layout brings every edge that ends on one side of a node to that side. These spread them along the side, at
/// most 14 points apart, in the order they fan out, and put each on the node's outline.
enum ReferenceUseCaseEdgeEnds {
    static let portGap: CGFloat = 14

    /// A route's end: which route, its first or last point, the node and side it meets, and where the route goes next
    /// across that side.
    private struct End {
        let route: Int
        let isFirst: Bool
        let toward: CGFloat
    }

    /// Each route's first and last points moved onto the outlines of `sources[route]` and `targets[route]`.
    static func attach(_ routes: inout [LayeredClusterRoute], sources: [Int], targets: [Int], centers: [CGPoint], views: [ReferenceUseCaseNodeView]) {
        var sides: [Int: [End]] = [:]
        var order: [Int] = []
        for (route, path) in routes.enumerated() where path.points.count >= 2 {
            for isFirst in [true, false] {
                let (side, toward) = Self.side(of: path, isFirst: isFirst)
                let key = (isFirst ? sources[route] : targets[route]) * 4 + Self.number(of: side)
                if sides[key] == nil { order.append(key) }
                sides[key, default: []].append(End(route: route, isFirst: isFirst, toward: toward))
            }
        }
        for key in order {
            guard var ends = sides[key] else { continue }
            let node = key / 4
            let side = DiagramSide.allCases[key % 4]
            let step = ends.count > 1 ? min(portGap, sideLength(of: views[node], side: side) / CGFloat(ends.count - 1)) : 0
            ends = ends.enumerated().sorted { first, second in
                first.element.toward != second.element.toward ? first.element.toward < second.element.toward : first.offset < second.offset
            }.map(\.element)
            for (place, end) in ends.enumerated() {
                let along = (CGFloat(place) - CGFloat(ends.count - 1) / 2) * step
                let point = anchor(of: views[node], center: centers[node], side: side, along: along)
                let index = end.isFirst ? 0 : routes[end.route].points.count - 1
                routes[end.route].points[index] = point
            }
        }
    }

    /// The side a route leaves its source by or arrives at its target from, along its end segment's flow, and where it
    /// goes next across that side.
    private static func side(of route: LayeredClusterRoute, isFirst: Bool) -> (DiagramSide, CGFloat) {
        let points = route.points
        let end = isFirst ? points[0] : points[points.count - 1]
        let next = isFirst ? points[1] : points[points.count - 2]
        let runsVertically = isFirst ? route.segmentsRunVertically[0] : route.segmentsRunVertically[route.segmentsRunVertically.count - 1]
        let side: DiagramSide = runsVertically ? (next.y > end.y ? .bottom : .top) : (next.x > end.x ? .right : .left)
        return (side, side.isHorizontal ? next.x : next.y)
    }

    private static func number(of side: DiagramSide) -> Int {
        DiagramSide.allCases.firstIndex(of: side) ?? 0
    }

    /// The point of a node's outline on `side`, `along` away from the middle of that side. Lines meet an actor at its
    /// figure, not at its label.
    static func anchor(of view: ReferenceUseCaseNodeView, center: CGPoint, side: DiagramSide, along: CGFloat) -> CGPoint {
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
    static func sideLength(of view: ReferenceUseCaseNodeView, side: DiagramSide) -> CGFloat {
        let isUpright = !side.isHorizontal
        if view.form == .actor { return isUpright ? UseCaseNodeMeasurement.figureHeight * 0.5 : UseCaseNodeMeasurement.figureWidth * 0.6 }
        let length = isUpright ? view.size.height : view.size.width
        return view.form == .ellipse ? length * 0.6 : length - 16
    }
}
