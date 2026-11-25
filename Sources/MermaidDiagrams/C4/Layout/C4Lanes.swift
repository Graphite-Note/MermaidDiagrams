/**
 * File: C4Lanes.swift
 * -------------------
 * Layer: Core
 * Description: What the C4 relations routed so far take up, so that the next keeps apart from them: their upright and
 *              level stretches, the boundaries' frames, and where lines leave or reach each side of a box (Pele's Lanes).
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

import CoreGraphics

/// What the routes drawn so far take up: upright stretches as x, top, bottom; level ones as y, left, right; the
/// boundaries' frames as both; and, for each box by its index, the sides and places lines leave or reach it from.
struct C4Lanes {
    private var upright: [CGFloat] = []
    private var level: [CGFloat] = []
    private var uprightFrames: [CGFloat] = []
    private var levelFrames: [CGFloat] = []
    /// By box, the sides and places taken, two numbers each.
    private var takenPorts: [[CGFloat]] = []
    /// Routes that found no lane of their own: a line left straight behind a shape, or a lane that runs along another.
    var squeezedCount = 0

    /// Whether a stretch at `position` from `start` to `end`, upright or level, keeps apart from the stretches and frames
    /// already there.
    func isFree(upright isUpright: Bool, at position: CGFloat, from start: CGFloat, to end: CGFloat) -> Bool {
        let low = min(start, end)
        let high = max(start, end)
        func isNear(_ list: [CGFloat], within distance: CGFloat) -> Bool {
            var index = 0
            while index < list.count {
                if abs(list[index] - position) < distance, list[index + 1] < high, list[index + 2] > low { return true }
                index += 3
            }
            return false
        }
        return !isNear(isUpright ? upright : level, within: C4Metrics.nearDistance)
            && !isNear(isUpright ? uprightFrames : levelFrames, within: C4Metrics.frameNearDistance)
    }

    /// How many stretches already there the line through `points` crosses.
    func crossings<Points: RandomAccessCollection<CGFloat>>(_ points: Points) -> Int where Points.Index == Int {
        var count = 0
        var index = 2
        while index < points.count {
            let isUpright = points[index] == points[index - 2]
            let position = isUpright ? points[index] : points[index + 1]
            let low = min(isUpright ? points[index - 1] : points[index - 2], isUpright ? points[index + 1] : points[index])
            let high = max(isUpright ? points[index - 1] : points[index - 2], isUpright ? points[index + 1] : points[index])
            let list = isUpright ? level : upright
            var other = 0
            while other < list.count {
                if list[other] > low, list[other] < high, list[other + 1] < position, list[other + 2] > position { count += 1 }
                other += 3
            }
            index += 2
        }
        return count
    }

    /// A boundary's frame, which a lane keeps apart from.
    mutating func addFrame(_ box: C4RouteBox) {
        for value in [box.x, box.y, box.bottom, box.right, box.y, box.bottom] { uprightFrames.append(value) }
        for value in [box.y, box.x, box.right, box.bottom, box.x, box.right] { levelFrames.append(value) }
    }

    /// The upright and level stretches of the line through `points`.
    mutating func take<Points: RandomAccessCollection<CGFloat>>(_ points: Points) where Points.Index == Int {
        var index = 2
        while index < points.count {
            if points[index] == points[index - 2] {
                upright.append(points[index])
                upright.append(min(points[index - 1], points[index + 1]))
                upright.append(max(points[index - 1], points[index + 1]))
            } else if points[index + 1] == points[index - 1] {
                level.append(points[index + 1])
                level.append(min(points[index - 2], points[index]))
                level.append(max(points[index - 2], points[index]))
            }
            index += 2
        }
    }

    /// Where on one side of the box `boxIndex` (0 left, 1 right, 2 top, 3 bottom) a line can leave or arrive, between
    /// `low` and `high`: up to four places clear of the lines already there, nearest `wanted` first, else `wanted`.
    func ports(of boxIndex: Int, side: Int, wanted: CGFloat, low: CGFloat, high: CGFloat) -> C4Numbers {
        let used = boxIndex < takenPorts.count ? takenPorts[boxIndex] : []
        var found = C4Numbers()
        for step in 0..<9 where found.count < 4 {
            let place = wanted + (step & 1 == 1 ? 1 : -1) * CGFloat((step + 1) / 2) * C4Metrics.portStep
            if place < low || place > high { continue }
            var isClear = true
            var index = 0
            while index < used.count {
                if used[index] == CGFloat(side), abs(used[index + 1] - place) < C4Metrics.portStep { isClear = false }
                index += 2
            }
            if isClear { found.append(place) }
        }
        if found.isEmpty { found.append(wanted) }
        return found
    }

    mutating func claim(_ boxIndex: Int, side: Int, at place: CGFloat) {
        while takenPorts.count <= boxIndex { takenPorts.append([]) }
        takenPorts[boxIndex].append(CGFloat(side))
        takenPorts[boxIndex].append(place)
    }
}
