/**
 * File: VennRegionOutline.swift
 * -----------------------------
 * Layer: Core
 * Description: The outline of the region several circles of a Venn diagram share, as Pele's regionPath traces it: the
 *              corners where two outlines cross inside the others, joined by arcs of the circles between them, as a Core
 *              Graphics path or recorded into a lane of the scene's workspace.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

import CoreGraphics
import Foundation

/// The outline of the region all the given circles share: one whole circle (one circle, or one inside all the others),
/// or corners joined by arcs, each the arc of a circle through both corners that stays inside the others.
public enum VennRegionOutline: Equatable, Sendable {
    case circle(center: CGPoint, radius: CGFloat)
    case corners(start: CGPoint, sides: [VennRegionOutlineSide])

    /// The shared region's outline, or nil when the circles share nothing.
    static func shared(by circles: [VennCircle]) -> VennRegionOutline? {
        guard let first = circles.first else { return nil }
        if circles.count == 1 { return .circle(center: CGPoint(x: first.x, y: first.y), radius: first.radius) }
        let corners = crossings(of: circles)
        if corners.count < 2 { return enclosedCircle(circles) }
        var middleX = 0.0
        var middleY = 0.0
        for corner in corners {
            middleX += corner.x / Double(corners.count)
            middleY += corner.y / Double(corners.count)
        }
        let ordered = corners.sorted { first, second in atan2(first.y - middleY, first.x - middleX) < atan2(second.y - middleY, second.x - middleX) }
        var sides: [VennRegionOutlineSide] = []
        for (index, from) in ordered.enumerated() {
            let to = ordered[(index + 1) % ordered.count]
            sides.append(side(from: from, to: to, circles: circles))
        }
        return .corners(start: CGPoint(x: ordered[0].x, y: ordered[0].y), sides: sides)
    }

    /// A point where two outlines cross, and the two circles.
    private struct Corner {
        let x: Double
        let y: Double
        let first: Int
        let second: Int
    }

    /// Where each two outlines cross inside all the other circles.
    private static func crossings(of circles: [VennCircle]) -> [Corner] {
        var corners: [Corner] = []
        for first in circles.indices {
            for second in circles.indices where second > first {
                let one = circles[first]
                let other = circles[second]
                let distance = hypot(other.x - one.x, other.y - one.y)
                if distance >= one.radius + other.radius || distance <= abs(one.radius - other.radius) || distance == 0 { continue }
                let along = (one.radius * one.radius - other.radius * other.radius + distance * distance) / (2 * distance)
                let up = sqrt(max(one.radius * one.radius - along * along, 0))
                let middleX = one.x + (other.x - one.x) * along / distance
                let middleY = one.y + (other.y - one.y) * along / distance
                for sign in [1.0, -1.0] {
                    let x = middleX + sign * up * (other.y - one.y) / distance
                    let y = middleY - sign * up * (other.x - one.x) / distance
                    if isWithinOthers(x, y, circles: circles, except: first, second) { corners.append(Corner(x: x, y: y, first: first, second: second)) }
                }
            }
        }
        return corners
    }

    private static func isWithinOthers(_ x: Double, _ y: Double, circles: [VennCircle], except first: Int, _ second: Int) -> Bool {
        for (index, circle) in circles.enumerated() where index != first && index != second {
            if hypot(x - circle.x, y - circle.y) > circle.radius * (1 + insideTolerance) { return false }
        }
        return true
    }

    /// No corners: the smallest circle when it lies inside all the others, else nothing.
    private static func enclosedCircle(_ circles: [VennCircle]) -> VennRegionOutline? {
        var smallest = circles[0]
        for circle in circles where circle.radius < smallest.radius { smallest = circle }
        for circle in circles where circle != smallest {
            if hypot(circle.x - smallest.x, circle.y - smallest.y) + smallest.radius > circle.radius * (1 + insideTolerance) { return nil }
        }
        return .circle(center: CGPoint(x: smallest.x, y: smallest.y), radius: smallest.radius)
    }

    /// The side from one corner to the next: of the circles through both, the arc that bulges least from their chord,
    /// else a straight line.
    private static func side(from: Corner, to: Corner, circles: [VennCircle]) -> VennRegionOutlineSide {
        var chosen: VennRegionOutlineSide?
        var narrowest = Double.infinity
        for index in [from.first, from.second] where index == to.first || index == to.second {
            let circle = circles[index]
            let start = atan2(from.y - circle.y, from.x - circle.x)
            var sweep = atan2(to.y - circle.y, to.x - circle.x) - start
            if sweep <= 0 { sweep += 2 * Double.pi }
            let bulgeX = circle.x + circle.radius * cos(start + sweep / 2)
            let bulgeY = circle.y + circle.radius * sin(start + sweep / 2)
            let width = hypot(bulgeX - (from.x + to.x) / 2, bulgeY - (from.y + to.y) / 2)
            if width < narrowest {
                narrowest = width
                chosen = .arc(center: CGPoint(x: circle.x, y: circle.y), radius: circle.radius, startAngle: start, endAngle: start + sweep,
                              end: CGPoint(x: to.x, y: to.y))
            }
        }
        return chosen ?? .line(to: CGPoint(x: to.x, y: to.y))
    }

    /// How far past a circle's radius a point may be and still count as inside it.
    private static let insideTolerance = 1e-9
}

/// A side of a region's outline from the corner before it.
public enum VennRegionOutlineSide: Equatable, Sendable {
    case line(to: CGPoint)
    /// An arc of the circle around `center` with increasing angles (clockwise on a page whose y runs down), from the
    /// corner before it to `end`.
    case arc(center: CGPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, end: CGPoint)
}

extension VennRegionOutline {
    /// The outline scaled by `scale` about the origin and moved by `offset`, as the circles are placed on the page.
    func placed(scale: CGFloat, offset: CGVector) -> VennRegionOutline {
        func point(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x * scale + offset.dx, y: point.y * scale + offset.dy) }
        switch self {
        case .circle(let center, let radius): return .circle(center: point(center), radius: radius * scale)
        case .corners(let start, let sides):
            return .corners(start: point(start), sides: sides.map { side in
                switch side {
                case .line(let end): .line(to: point(end))
                case .arc(let center, let radius, let startAngle, let endAngle, let end):
                    .arc(center: point(center), radius: radius * scale, startAngle: startAngle, endAngle: endAngle, end: point(end))
                }
            })
        }
    }

    /// The outline as a closed path.
    var path: CGPath {
        let path = CGMutablePath()
        switch self {
        case .circle(let center, let radius):
            path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius))
        case .corners(let start, let sides):
            path.move(to: start)
            for side in sides {
                switch side {
                case .line(let end): path.addLine(to: end)
                case .arc(let center, let radius, let startAngle, let endAngle, _):
                    path.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
                }
            }
            path.closeSubpath()
        }
        return path
    }

    /// The outline recorded into `lane`, element for element as `path` records it.
    func record(into lane: DiagramPathLane) {
        switch self {
        case .circle(let center, let radius):
            lane.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius))
        case .corners(let start, let sides):
            lane.move(to: start)
            for side in sides {
                switch side {
                case .line(let end): lane.addLine(to: end)
                case .arc(let center, let radius, let startAngle, let endAngle, _):
                    lane.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
                }
            }
            lane.closeSubpath()
        }
    }
}
