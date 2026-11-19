/**
 * File: BlockEdgePlacement.swift
 * ------------------------------
 * Layer: Core
 * Description: Places a block diagram's edges and their text as Pele's block renderer does: edges between the same two
 *              blocks spread apart, each text on its longer leg where it covers no other block, texts stacked along
 *              their shared line, and the gap between two blocks widened where their texts do not fit.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// An edge routed: its points (none for a loop), which loop on its block it is (0 for none), its text and where.
struct BlockRoute {
    let points: [CGPoint]
    let loopCount: Int
    let textSize: CGSize
    var textCenter: CGPoint
}

/// The edges drawn and where each one's route and text go.
struct BlockEdgePlacement {
    /// Each edge drawn, by its place in the diagram's edges, and its ends' cells.
    let edgeIndices: [Int]
    let ends: [(source: Int, target: Int)]
    let textSizes: [CGSize]
    let edgeTextSize: CGFloat
    /// The blocks edges are routed round, nil when there are too many to check.
    let checksObstacles: Bool
    var routes: [BlockRoute] = []
    /// The edges between each pair of blocks that have text, in the order their pairs first come, and each one's leg.
    private var stacks: [(key: Int, members: [Int])] = []
    private(set) var legs: [Int: [CGPoint]] = [:]
    private let pairCounts: [Int: Int]
    private let labelledPairs: Set<Int>
    private let cellCount: Int

    /// Pele's budget: checking every edge against every block is quadratic, so a larger diagram routes without it.
    static let obstacleBudget = 2_000_000
    /// Between texts stacked along a line.
    static let textGap: CGFloat = 4
    /// The spots along a leg tried for a text, in Pele's order.
    static let textSpots: [CGFloat] = [0.5, 0.3, 0.7, 0.15, 0.85]

    init(edgeIndices: [Int], ends: [(source: Int, target: Int)], textSizes: [CGSize], edgeTextSize: CGFloat, obstacleCount: Int, cellCount: Int) {
        self.edgeIndices = edgeIndices
        self.ends = ends
        self.textSizes = textSizes
        self.edgeTextSize = edgeTextSize
        self.cellCount = cellCount
        checksObstacles = ends.count * obstacleCount <= Self.obstacleBudget
        var pairCounts: [Int: Int] = [:]
        var labelledPairs: Set<Int> = []
        for (index, end) in ends.enumerated() {
            let key = Self.pairKey(end, cellCount: cellCount)
            pairCounts[key, default: 0] += 1
            if textSizes[index].width > 0 { labelledPairs.insert(key) }
        }
        self.pairCounts = pairCounts
        self.labelledPairs = labelledPairs
    }

    static func pairKey(_ end: (source: Int, target: Int), cellCount: Int) -> Int {
        min(end.source, end.target) * cellCount + max(end.source, end.target)
    }

    /// Pele's `route`: every edge routed and its text placed on its longer leg.
    mutating func route(_ placement: BlockPlacement) {
        var seen: [Int: Int] = [:]
        routes = []
        stacks = []
        legs = [:]
        var stackPlaces: [Int: Int] = [:]
        let obstacles = checksObstacles ? placement.obstacleIndices : nil
        let blockObstacles = checksObstacles ? placement.blockObstacles : nil
        for (index, end) in ends.enumerated() {
            let key = Self.pairKey(end, cellCount: cellCount)
            let total = pairCounts[key] ?? 1
            let count = seen[key] ?? 0
            seen[key] = count + 1
            let textSize = textSizes[index]
            guard end.source != end.target else {
                let arc = BlockEdgePaths.loopArc(on: placement.outlines[end.source], count: count + 1)
                let center = CGPoint(x: arc.center.x + arc.radius + 6 + textSize.width / 2, y: arc.center.y - arc.radius / 2)
                routes.append(BlockRoute(points: [], loopCount: count + 1, textSize: textSize, textCenter: center))
                continue
            }
            let step = labelledPairs.contains(key) ? (edgeTextSize * 1.5).rounded() + 2 : 14
            let shift = (CGFloat(count) - CGFloat(total - 1) / 2) * step
            let points = BlockEdgeRouting.route(from: end.source, to: end.target, outlines: placement.outlines, shift: shift, obstacles: obstacles)
            let leg = Self.longerLeg(points)
            let spot = textSize.width > 0 ? Self.spot(on: Array(points[leg...leg + 1]), textSize: textSize, end: end, obstacles: blockObstacles) : 0.5
            let center = CGPoint(x: points[leg].x + (points[leg + 1].x - points[leg].x) * spot, y: points[leg].y + (points[leg + 1].y - points[leg].y) * spot)
            if textSize.width > 0, total > 1 {
                legs[index] = Array(points[leg...leg + 1])
                if let place = stackPlaces[key] {
                    stacks[place].members.append(index)
                } else {
                    stackPlaces[key] = stacks.count
                    stacks.append((key, [index]))
                }
            }
            routes.append(BlockRoute(points: points, loopCount: 0, textSize: textSize, textCenter: center))
        }
    }

    /// The text goes on the longer leg: the last of a bend when it is longer than the first.
    private static func longerLeg(_ points: [CGPoint]) -> Int {
        guard points.count == 3 else { return 0 }
        let first = abs(points[1].x - points[0].x) + abs(points[1].y - points[0].y)
        let last = abs(points[2].x - points[1].x) + abs(points[2].y - points[1].y)
        return last > first ? 1 : 0
    }

    /// Pele's `labelSpot`: the first spot along the leg where the text covers no block but the two it joins.
    private static func spot(on leg: [CGPoint], textSize: CGSize, end: (source: Int, target: Int), obstacles: [BlockObstacle]?) -> CGFloat {
        guard let obstacles else { return 0.5 }
        let size = CGSize(width: textSize.width + 8, height: textSize.height)
        for spot in textSpots {
            let center = CGPoint(x: leg[0].x + (leg[1].x - leg[0].x) * spot, y: leg[0].y + (leg[1].y - leg[0].y) * spot)
            if !covers(center, size: size, end: end, obstacles: obstacles) { return spot }
        }
        return 0.5
    }

    /// Pele's `covers`: whether a text of `size` at `center` overlaps an obstacle other than the edge's two blocks.
    static func covers(_ center: CGPoint, size: CGSize, end: (source: Int, target: Int), obstacles: [BlockObstacle]?) -> Bool {
        guard let obstacles else { return false }
        for obstacle in obstacles where obstacle.cellIndex != end.source && obstacle.cellIndex != end.target {
            if abs(center.x - obstacle.center.x) < (size.width + obstacle.size.width) / 2, abs(center.y - obstacle.center.y) < (size.height + obstacle.size.height) / 2 {
                return true
            }
        }
        return false
    }

    /// Pele's `settle`: routes again, stacks the texts of each pair with several, and, when `grow` and they do not fit,
    /// widens the gap between the pair's blocks (across only when the layout is not tight); whether a gap was widened.
    mutating func settle(_ placement: inout BlockPlacement, grow: Bool, isTight: Bool) -> Bool {
        route(placement)
        let blocked = checksObstacles ? placement.blockObstacles + placement.titles : nil
        var widening = BlockGapWidening()
        var grown = false
        for stack in stacks where stack.members.count >= 2 {
            let end = ends[stack.members[0]]
            let short = stackTexts(stack.members, end: end, obstacles: blocked)
            guard let leg = legs[stack.members[0]] else { continue }
            let isVertical = leg[0].x == leg[1].x
            if grow, short > 0, isVertical || !isTight,
               widening.widen(&placement, between: end, isVertical: isVertical, by: short.rounded(.up)) {
                grown = true
            }
        }
        return grown
    }
}
