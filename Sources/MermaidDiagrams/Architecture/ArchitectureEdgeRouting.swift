/**
 * File: ArchitectureEdgeRouting.swift
 * -----------------------------------
 * Layer: Core
 * Description: Routes an architecture diagram's edges as Pele's renderer does: orthogonal, from one side's port to the
 *              other's, each leaving along its side's normal, between or around the two boxes, corners rounded.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics
import Foundation

/// Where an edge meets a side, Pele's `Port`: the point, the side's outward normal, the box the route keeps out of
/// when it cannot leave straight, how far short of the point an arrow stops (a junction's dot), and whether the line
/// carries on through a group's border to a junction inside it.
struct ArchitecturePort {
    var point: CGPoint
    let normal: CGVector
    var box: CGRect
    var gap: CGFloat
    var continuesToJunction: Bool
}

/// Pele's `route`, `simplify` and `pathData`.
enum ArchitectureEdgeRouting {
    /// How far a route runs straight out of a side before it turns.
    static let stub: CGFloat = 12
    /// The most a corner is rounded by.
    static let cornerRadius: CGFloat = 6

    /// The orthogonal route from one port to the other.
    static func route(from start: ArchitecturePort, to end: ArchitecturePort) -> [CGPoint] {
        let (source, target) = (start.point, end.point)
        let (sourceNormal, targetNormal) = (start.normal, end.normal)
        let sourceStub = CGPoint(x: source.x + sourceNormal.dx * stub, y: source.y + sourceNormal.dy * stub)
        let targetStub = CGPoint(x: target.x + targetNormal.dx * stub, y: target.y + targetNormal.dy * stub)
        if sourceNormal.dx * targetNormal.dx + sourceNormal.dy * targetNormal.dy == 0 {
            let corner = sourceNormal.dx != 0 ? CGPoint(x: target.x, y: source.y) : CGPoint(x: source.x, y: target.y)
            let isAheadOfBoth = (corner.x - source.x) * sourceNormal.dx + (corner.y - source.y) * sourceNormal.dy > 0
                && (corner.x - target.x) * targetNormal.dx + (corner.y - target.y) * targetNormal.dy > 0
            if isAheadOfBoth { return [source, corner, target] }
            return sourceNormal.dx != 0 ? [source, sourceStub, CGPoint(x: sourceStub.x, y: targetStub.y), targetStub, target]
                : [source, sourceStub, CGPoint(x: targetStub.x, y: sourceStub.y), targetStub, target]
        }
        let isSideways = sourceNormal.dx != 0
        let offset = isSideways ? target.y - source.y : target.x - source.x
        if sourceNormal.dx == -targetNormal.dx, sourceNormal.dy == -targetNormal.dy {
            let ahead = (target.x - source.x) * sourceNormal.dx + (target.y - source.y) * sourceNormal.dy
            if ahead > 0 { return facing(start, end, offset: offset, isSideways: isSideways) }
        } else if abs(offset) >= 1 {
            if isSideways {
                let x = sourceNormal.dx > 0 ? max(source.x, target.x) + stub : min(source.x, target.x) - stub
                return [source, CGPoint(x: x, y: source.y), CGPoint(x: x, y: target.y), target]
            }
            let y = sourceNormal.dy > 0 ? max(source.y, target.y) + stub : min(source.y, target.y) - stub
            return [source, CGPoint(x: source.x, y: y), CGPoint(x: target.x, y: y), target]
        }
        return around(start, end, sourceStub: sourceStub, targetStub: targetStub, isSideways: isSideways)
    }

    /// Facing sides with the target ahead: straight, or turning midway between the two boxes, clear of both titles, when
    /// there is such a place.
    private static func facing(_ start: ArchitecturePort, _ end: ArchitecturePort, offset: CGFloat, isSideways: Bool) -> [CGPoint] {
        let (source, target) = (start.point, end.point)
        if abs(offset) < 0.5 { return [source, target] }
        if isSideways {
            let low = start.normal.dx > 0 ? start.box.maxX : end.box.maxX
            let high = start.normal.dx > 0 ? end.box.minX : start.box.minX
            let middle = low < high ? (low + high) / 2 : (source.x + target.x) / 2
            return [source, CGPoint(x: middle, y: source.y), CGPoint(x: middle, y: target.y), target]
        }
        let low = start.normal.dy > 0 ? start.box.maxY : end.box.maxY
        let high = start.normal.dy > 0 ? end.box.minY : start.box.minY
        let middle = low < high ? (low + high) / 2 : (source.y + target.y) / 2
        return [source, CGPoint(x: source.x, y: middle), CGPoint(x: target.x, y: middle), target]
    }

    /// The straight way blocked by one of the two boxes: between them, or round both.
    private static func around(_ start: ArchitecturePort, _ end: ArchitecturePort, sourceStub: CGPoint, targetStub: CGPoint,
                               isSideways: Bool) -> [CGPoint] {
        let (source, target) = (start.point, end.point)
        let (first, second) = (start.box, end.box)
        if isSideways {
            let lane = first.maxY + stub <= second.minY ? (first.maxY + second.minY) / 2
                : second.maxY + stub <= first.minY ? (second.maxY + first.minY) / 2 : max(first.maxY, second.maxY) + stub
            return [source, CGPoint(x: sourceStub.x, y: source.y), CGPoint(x: sourceStub.x, y: lane), CGPoint(x: targetStub.x, y: lane),
                    CGPoint(x: targetStub.x, y: target.y), target]
        }
        let lane = first.maxX + stub <= second.minX ? (first.maxX + second.minX) / 2
            : second.maxX + stub <= first.minX ? (second.maxX + first.minX) / 2 : max(first.maxX, second.maxX) + stub
        return [source, CGPoint(x: source.x, y: sourceStub.y), CGPoint(x: lane, y: sourceStub.y), CGPoint(x: lane, y: targetStub.y),
                CGPoint(x: target.x, y: targetStub.y), target]
    }

    /// Pele's `simplify`: repeated points dropped and runs that go on in a straight line joined.
    static func simplified(_ points: [CGPoint]) -> [CGPoint] {
        var out = [points[0]]
        for point in points.dropFirst() {
            let last = out[out.count - 1]
            let isSameX = abs(point.x - last.x) < 0.01
            let isSameY = abs(point.y - last.y) < 0.01
            if isSameX, isSameY { continue }
            if out.count >= 2, (isSameX && abs(out[out.count - 2].x - last.x) < 0.01) || (isSameY && abs(out[out.count - 2].y - last.y) < 0.01) {
                out[out.count - 1] = point
            } else {
                out.append(point)
            }
        }
        return out
    }

    /// Pele's `pathData`: the ends cut back (never past a point short of the next), each corner rounded by up to six
    /// points or half its legs.
    static func path(through route: [CGPoint], startTrim: CGFloat, endTrim: CGFloat) -> DiagramPath {
        var points = route
        func trim(_ at: Int, toward: Int, by amount: CGFloat) {
            let length = hypot(points[toward].x - points[at].x, points[toward].y - points[at].y)
            let cut = min(amount, max(0, length - 1))
            guard length > 0, cut > 0 else { return }
            points[at].x += (points[toward].x - points[at].x) / length * cut
            points[at].y += (points[toward].y - points[at].y) / length * cut
        }
        trim(0, toward: 1, by: startTrim)
        trim(points.count - 1, toward: points.count - 2, by: endTrim)
        var segments: [DiagramPathSegment] = []
        for index in points.indices.dropFirst().dropLast() {
            let (previous, corner, next) = (points[index - 1], points[index], points[index + 1])
            let before = hypot(corner.x - previous.x, corner.y - previous.y)
            let after = hypot(next.x - corner.x, next.y - corner.y)
            let radius = min(cornerRadius, before / 2, after / 2)
            guard radius >= 0.5 else {
                segments.append(.line(to: corner))
                continue
            }
            let into = CGPoint(x: corner.x - (corner.x - previous.x) / before * radius, y: corner.y - (corner.y - previous.y) / before * radius)
            let out = CGPoint(x: corner.x + (next.x - corner.x) / after * radius, y: corner.y + (next.y - corner.y) / after * radius)
            segments.append(.line(to: into))
            segments.append(BlockEdgePaths.quadratic(from: into, control: corner, to: out))
        }
        segments.append(.line(to: points[points.count - 1]))
        return DiagramPath(start: points[0], segments: segments)
    }
}
