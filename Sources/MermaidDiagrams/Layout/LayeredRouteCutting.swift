/**
 * File: LayeredRouteCutting.swift
 * -------------------------------
 * Layer: Core
 * Description: Cuts drawn routes into straight pieces and counts the pieces that cross, for Pele's compound layout.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

import CoreGraphics

extension LayeredRouteCrossings {
    /// One route cut as it is drawn: a straight step as itself, a rounded corner between two straight legs as a few
    /// pieces (adjacent corners sharing a leg, each getting half), a step drawn in three, an S curve in three.
    static func cut(_ route: ScratchSpan<LayeredRoutePoint>, edge: Int, style: LayeredRouteStyle, into segments: inout LayeredRouteSegments) {
        guard route.count >= 2 else { return }
        func point(_ index: Int) -> CGPoint { route[index].point }
        func isAligned(_ index: Int) -> Bool { abs(point(index).x - point(index - 1).x) < 0.01 || abs(point(index).y - point(index - 1).y) < 0.01 }
        func length(_ index: Int) -> Double { abs(point(index).x - point(index - 1).x) + abs(point(index).y - point(index - 1).y) }
        func turns(_ index: Int) -> Bool {
            style == .curved && index > 0 && index < route.count - 1 && isAligned(index) && isAligned(index + 1) && length(index) >= 0.01
                && length(index + 1) >= 0.01 && (abs(point(index).x - point(index - 1).x) < 0.01) != (abs(point(index + 1).x - point(index).x) < 0.01)
        }
        var at = point(0)
        for index in 1..<route.count {
            let part: UInt8 = (index == 1 ? 1 : 0) | (index == route.count - 1 ? 2 : 0)
            let from = at
            let to = point(index)
            at = to
            if isAligned(index) || style == .linear {
                if !turns(index) {
                    segments.add(edge: edge, part: part, from: from, to: to)
                    continue
                }
                let before = turns(index - 1) ? length(index) / 2 : length(index)
                let after = turns(index + 1) ? length(index + 1) / 2 : length(index + 1)
                let incoming = CGVector(dx: (to.x - point(index - 1).x) / length(index), dy: (to.y - point(index - 1).y) / length(index))
                let outgoing = CGVector(dx: (point(index + 1).x - to.x) / length(index + 1), dy: (point(index + 1).y - to.y) / length(index + 1))
                let turnPart = part | (index + 1 == route.count - 1 ? 2 : 0)
                at = addCorner(edge: edge, parts: (part, turnPart), from: from, corner: to, incoming: incoming, outgoing: outgoing,
                               legs: (before, after), into: &segments)
                continue
            }
            let isDown = !route[index].runsHorizontally
            if style == .stepped {
                addStep(edge: edge, part: part, from: from, to: to, isDown: isDown, into: &segments)
            } else {
                addSCurve(edge: edge, part: part, from: from, to: to, isDown: isDown, into: &segments)
            }
        }
    }

    /// A rounded corner between two straight legs: the leg up to where it starts, then the curve; returns its end.
    private static func addCorner(edge: Int, parts: (leg: UInt8, turn: UInt8), from: CGPoint, corner: CGPoint, incoming: CGVector, outgoing: CGVector,
                                  legs: (before: Double, after: Double), into segments: inout LayeredRouteSegments) -> CGPoint {
        let start = CGPoint(x: corner.x - incoming.dx * legs.before, y: corner.y - incoming.dy * legs.before)
        segments.add(edge: edge, part: parts.leg, from: from, to: start)
        let handle = 1 - LayeredCompoundConstants.handle
        let control1 = CGPoint(x: corner.x - incoming.dx * legs.before * handle, y: corner.y - incoming.dy * legs.before * handle)
        let control2 = CGPoint(x: corner.x + outgoing.dx * legs.after * handle, y: corner.y + outgoing.dy * legs.after * handle)
        let end = CGPoint(x: corner.x + outgoing.dx * legs.after, y: corner.y + outgoing.dy * legs.after)
        addCubic(edge: edge, part: parts.turn, start: start, control1: control1, control2: control2, end: end, into: &segments)
        return end
    }

    private static func addCubic(edge: Int, part: UInt8, start: CGPoint, control1: CGPoint, control2: CGPoint, end: CGPoint,
                                 into segments: inout LayeredRouteSegments) {
        var previous = start
        for piece in 1...LayeredCompoundConstants.cornerPieces {
            let progress = Double(piece) / Double(LayeredCompoundConstants.cornerPieces)
            let rest = 1 - progress
            let x = rest * rest * rest * start.x + 3 * rest * rest * progress * control1.x + 3 * rest * progress * progress * control2.x + progress * progress * progress * end.x
            let y = rest * rest * rest * start.y + 3 * rest * rest * progress * control1.y + 3 * rest * progress * progress * control2.y + progress * progress * progress * end.y
            segments.add(edge: edge, part: part, from: previous, to: CGPoint(x: x, y: y))
            previous = CGPoint(x: x, y: y)
        }
    }

    /// A step drawn in three: along its flow to halfway, across, and on.
    private static func addStep(edge: Int, part: UInt8, from: CGPoint, to: CGPoint, isDown: Bool, into segments: inout LayeredRouteSegments) {
        let middle = isDown ? CGPoint(x: from.x, y: (from.y + to.y) / 2) : CGPoint(x: (from.x + to.x) / 2, y: from.y)
        let turn = isDown ? CGPoint(x: to.x, y: middle.y) : CGPoint(x: middle.x, y: to.y)
        segments.add(edge: edge, part: part, from: from, to: middle)
        segments.add(edge: edge, part: part, from: middle, to: turn)
        segments.add(edge: edge, part: part, from: turn, to: to)
    }

    /// The drawn S curve approximated with straight pieces.
    private static func addSCurve(edge: Int, part: UInt8, from: CGPoint, to: CGPoint, isDown: Bool, into segments: inout LayeredRouteSegments) {
        let handle = isDown ? LayeredCurveEasing.ease(across: to.x - from.x, along: to.y - from.y) : LayeredCurveEasing.ease(across: to.y - from.y, along: to.x - from.x)
        var previous = from
        for piece in 1...LayeredCompoundConstants.curvePieces {
            let progress = Double(piece) / Double(LayeredCompoundConstants.curvePieces)
            let rest = 1 - progress
            let across = progress * progress * (3 - 2 * progress)
            let along = 3 * handle * progress * rest * rest + 3 * (1 - handle) * progress * progress * rest + progress * progress * progress
            let next = CGPoint(x: from.x + (to.x - from.x) * (isDown ? across : along), y: from.y + (to.y - from.y) * (isDown ? along : across))
            segments.add(edge: edge, part: part, from: previous, to: next)
            previous = next
        }
    }
}
