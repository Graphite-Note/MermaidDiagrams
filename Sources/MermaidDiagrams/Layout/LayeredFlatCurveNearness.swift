/**
 * File: LayeredFlatCurveNearness.swift
 * ------------------------------------
 * Layer: Core
 * Description: How Pele's plain S curves ease, and whether two of them pass too near each other in a gap.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import Foundation

enum LayeredCurveEasing {
    /// How far along the flow the handles of a plain S reach, as a share of the way it travels along it: half gives an
    /// even S; one that runs more than eight times as far across as along turns sooner, down to a quarter at sixteen
    /// times (Pele's `ease`).
    static func ease(across: Double, along: Double) -> Double {
        let across = abs(across)
        return max(0.25, min(0.5, 4 * abs(along) / (across == 0 ? 1 : across)))
    }
}

extension LayeredFlatTracks {
    /// Points along the plain S of `piece` in a gap `height` tall.
    private func samples(of piece: Int, height: Double) -> [(x: Double, y: Double)] {
        let from = pieces.from[piece]
        let to = pieces.to[piece]
        let handle = LayeredCurveEasing.ease(across: to - from, along: height)
        let sampleCount = LayeredFlatConstants.curveSamples
        return (0...sampleCount).map { index in
            let progress = Double(index) / Double(sampleCount)
            let rest = 1 - progress
            let x = from + (to - from) * progress * progress * (3 - 2 * progress)
            let y = height * (3 * handle * progress * rest * rest + 3 * (1 - handle) * progress * progress * rest + progress * progress * progress)
            return (x, y)
        }
    }

    /// Whether a point of `points` comes nearer than `limit` to the polyline `line`.
    private static func reaches(_ points: [(x: Double, y: Double)], _ line: [(x: Double, y: Double)], limit: Double) -> Bool {
        // Allow rounding error in the cheap distance check before the exact one.
        let bound = limit * limit * (1 + 1e-9)
        for point in points {
            for index in 0..<(line.count - 1) {
                let deltaX = line[index + 1].x - line[index].x
                let deltaY = line[index + 1].y - line[index].y
                let lengthSquared = deltaX * deltaX + deltaY * deltaY
                let projection = ((point.x - line[index].x) * deltaX + (point.y - line[index].y) * deltaY) / (lengthSquared == 0 ? 1 : lengthSquared)
                let clamped = max(0, min(1, projection))
                let errorX = point.x - line[index].x - clamped * deltaX
                let errorY = point.y - line[index].y - clamped * deltaY
                if errorX * errorX + errorY * errorY < bound && hypot(errorX, errorY) < limit { return true }
            }
        }
        return false
    }

    /// Whether the plain curves of two pieces in a gap `height` tall pass nearer than `limit` (Pele's `near`).
    func passNear(_ first: Int, _ second: Int, height: Double, limit: Double) -> Bool {
        let curveHeight = max(height / 2, height - 2 * LayeredFlatConstants.levelLead)
        let firstLine = samples(of: first, height: curveHeight)
        let secondLine = samples(of: second, height: curveHeight)
        return Self.reaches(firstLine, secondLine, limit: limit) || Self.reaches(secondLine, firstLine, limit: limit)
    }
}
