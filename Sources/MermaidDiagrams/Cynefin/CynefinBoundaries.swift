/**
 * File: CynefinBoundaries.swift
 * -----------------------------
 * Layer: Core
 * Description: The geometry of a Cynefin framework's boundaries as Pele's boundaries.ts makes it, after Mermaid: seeded
 *              wavy lines between the domains (one step of mulberry32 per point) and the S-shaped cliff.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

import CoreGraphics
import Foundation

/// Mermaid's seeded waves and cliff, number for number: the same seed gives the same boundaries as Pele's and Mermaid's.
enum CynefinBoundaries {
    /// One step of mulberry32 from `seed`, as JavaScript computes it on 32-bit integers: a number from 0 up to 1.
    static func seededRandom(_ seed: Double) -> Double {
        var state = UInt32(bitPattern: javaScriptInt32(seed + 0x6D2B_79F5))
        state = (state ^ (state >> 15)) &* (state | 1)
        state ^= state &+ ((state ^ (state >> 7)) &* (state | 61))
        return Double(state ^ (state >> 14)) / 4_294_967_296
    }

    /// JavaScript's `ToInt32`: the number truncated, then taken modulo 2³², as a signed integer; 0 for one not finite.
    static func javaScriptInt32(_ value: Double) -> Int32 {
        guard value.isFinite else { return 0 }
        var remainder = fmod(value.rounded(.towardZero), 4_294_967_296)
        if remainder < 0 { remainder += 4_294_967_296 }
        return Int32(bitPattern: UInt32(remainder))
    }

    /// Mermaid's `hashString`: `hash * 31 + code` over the text's UTF-16 code units, on 32-bit integers.
    static func hash(_ text: String) -> Int32 {
        var hash: Int32 = 0
        for unit in text.utf16 { hash = hash &* 31 &+ Int32(unit) }
        return hash
    }

    /// The seed of the waves: one configured other than zero, else the hash of the diagram's identifier, Pele's `pele`.
    static func seed(configured: Double?) -> Double {
        configured ?? Double(hash(identifierPrefix))
    }

    /// Pele's identifier prefix for a diagram rendered without one.
    static let identifierPrefix = "pele"

    /// How a wave varies its seed per point and per control point, and whether its ends stay on its center line.
    struct WaveShape {
        var segmentCount: Int
        var isVertical: Bool
        var pointStep: Double
        var controlStep: Double
        var controlShift: Double
        var pinsStart = false
        var pinsEnd = false

        /// The fold between the top domains, and the horizon between the top and the bottom ones: Mermaid's multipliers.
        static let fold = WaveShape(segmentCount: 7, isVertical: true, pointStep: 17, controlStep: 31, controlShift: 7)
        static let horizon = WaveShape(segmentCount: 7, isVertical: false, pointStep: 23, controlStep: 37, controlShift: 11)
    }

    /// A wavy line along one axis from `from` to `to`, centered on `center` across: each point jitters by up to the
    /// amplitude, a pinned end stays on the center line, and each segment's control points swing one and a half
    /// amplitudes, by turns one way and the other.
    static func wave(from: Double, to: Double, center: Double, seed: Double, amplitude: Double, shape: WaveShape) -> DiagramPath {
        let count = shape.segmentCount
        let step = (to - from) / Double(count)
        var along: [Double] = []
        var across: [Double] = []
        along.reserveCapacity(count + 1)
        across.reserveCapacity(count + 1)
        for index in 0...count {
            let isPinned = (index == 0 && shape.pinsStart) || (index == count && shape.pinsEnd)
            along.append(from + Double(index) * step)
            across.append(isPinned ? center : center + seededRandom(seed + Double(index) * shape.pointStep) * amplitude * 2 - amplitude)
        }
        func point(along position: Double, across offset: Double) -> CGPoint {
            shape.isVertical ? CGPoint(x: offset, y: position) : CGPoint(x: position, y: offset)
        }
        var segments: [DiagramPathSegment] = []
        segments.reserveCapacity(count)
        for index in 0..<count {
            let middle = (along[index] + along[index + 1]) / 2
            let swing = amplitude * 1.5 * (index % 2 == 0 ? 1 : -1) * seededRandom(seed + Double(index) * shape.controlStep + shape.controlShift)
            segments.append(.curve(to: point(along: along[index + 1], across: across[index + 1]), control1: point(along: middle, across: across[index] + swing),
                                   control2: point(along: middle, across: across[index + 1] - swing)))
        }
        return DiagramPath(start: point(along: along[0], across: across[0]), segments: segments)
    }

    /// The cliff: a steep S from (`centerX`, `top`) down to (`centerX`, `bottom`).
    static func cliff(centerX: Double, top: Double, bottom: Double, amplitude: Double) -> DiagramPath {
        let height = bottom - top
        func point(_ x: Double, _ share: Double) -> CGPoint { CGPoint(x: x, y: top + height * share) }
        return DiagramPath(start: CGPoint(x: centerX, y: top), segments: [
            .curve(to: point(centerX + amplitude * 0.5, 0.75), control1: point(centerX + amplitude, 0.2), control2: point(centerX - amplitude * 1.5, 0.55)),
            .curve(to: CGPoint(x: centerX, y: bottom), control1: point(centerX - amplitude, 0.85), control2: point(centerX + amplitude * 0.3, 0.95)),
        ])
    }

    /// The point a path ends at.
    static func endPoint(of path: DiagramPath) -> CGPoint {
        switch path.segments.last {
        case .line(let end): end
        case .curve(let end, _, _): end
        case nil: path.start
        }
    }

    /// `path` run backwards, from its end to its start.
    static func reversed(_ path: DiagramPath) -> DiagramPath {
        var points = [path.start]
        points.reserveCapacity(path.segments.count + 1)
        for segment in path.segments {
            switch segment {
            case .line(let end), .curve(let end, _, _): points.append(end)
            }
        }
        var segments: [DiagramPathSegment] = []
        segments.reserveCapacity(path.segments.count)
        for index in path.segments.indices.reversed() {
            switch path.segments[index] {
            case .line: segments.append(.line(to: points[index]))
            case .curve(_, let first, let second): segments.append(.curve(to: points[index], control1: second, control2: first))
            }
        }
        return DiagramPath(start: endPoint(of: path), segments: segments)
    }
}
