/**
 * File: ReferenceFlowchartClusterTitles.swift
 * -------------------------------------------
 * Layer: Tests
 * Description: The 0.7.0 FlowchartClusterTitles kept as the reference the 0.8.0 flowchart layout is checked against:
 *              where a group's title sits along the top of its box, clear of the edges crossing it where it can be.
 *
 * Authors: Bahey Shalash, felixchvl
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// Where a group's title sits along the top of its box, as Pele places it: at the left, else the middle, else the
/// right, the first that keeps clear of every edge crossing the box's top; where none does, the one farthest from
/// them, and when an edge still runs through it the title is drawn over the edges (`FlowchartLayoutCluster`).
enum ReferenceFlowchartClusterTitles {
    /// The least room between an edge crossing the box's top and the title's letters.
    static let clearance: CGFloat = 6
    /// An edge closer than this to the title's letters runs through it.
    static let crossingReach: CGFloat = 4
    /// How far a title at the left or the right reaches into the box's side padding.
    static let sideReach: CGFloat = 6
    /// A route point this close to the box's top crosses it: Pele compares whole points.
    static let topTolerance: CGFloat = 0.5
    /// A place must be clearer than the best so far by this much to be preferred.
    static let preferenceMargin: CGFloat = 0.5

    /// The title placed in `frame`, `ReferenceFlowchartClusterGraph.titleMargin` below its top, and whether an edge runs through it.
    /// - Parameter edgePoints: The points every edge passes through, its ends on their outlines included.
    static func placed(_ title: DiagramTextBlock, in frame: CGRect, edgePoints: [[CGPoint]]) -> (title: DiagramTextBlock, isCrossed: Bool) {
        placed(title, in: frame, crossings: ReferenceFlowchartRoutePointIndex(edgePoints))
    }

    /// The title placed in `frame`, the edges' points looked up in `crossings`, sorted once for every box.
    static func placed(_ title: DiagramTextBlock, in frame: CGRect, crossings index: ReferenceFlowchartRoutePointIndex) -> (title: DiagramTextBlock, isCrossed: Bool) {
        let crossings = index.points(within: topTolerance, of: frame.minY).filter { point in point.x > frame.minX && point.x < frame.maxX }.map(\.x)
        let halfWidth = title.size.width / 2
        let padding = ReferenceFlowchartClusterGraph.clusterPadding
        let candidates = [frame.minX + padding - sideReach + halfWidth, frame.midX, frame.maxX - padding + sideReach - halfWidth]
        var best = candidates[0]
        // As in Pele, another place replaces the left only where no crossing reaches half a point into its letters,
        // and then only a clearer one.
        var bestGap: CGFloat = -1
        for candidate in candidates {
            let gap = crossings.map { crossing in abs(crossing - candidate) - halfWidth }.min() ?? .greatestFiniteMagnitude
            if gap >= clearance {
                best = candidate
                break
            }
            if gap > bestGap + preferenceMargin {
                bestGap = gap
                best = candidate
            }
        }
        var placed = title
        placed.center = CGPoint(x: best, y: frame.minY + ReferenceFlowchartClusterGraph.titleMargin + title.size.height / 2)
        let isCrossed = crossings.contains { crossing in abs(crossing - best) < halfWidth + crossingReach }
        return (placed, isCrossed)
    }
}

/// The points edges pass through, sorted down the page once, so that the points on each box's top are found by search.
struct ReferenceFlowchartRoutePointIndex {
    private let points: [CGPoint]

    init(_ routes: [[CGPoint]]) {
        points = routes.joined().sorted { first, second in first.y < second.y }
    }

    /// The points less than `tolerance` from the line `along` across the page, in the order they are sorted.
    func points(within tolerance: CGFloat, of along: CGFloat) -> ArraySlice<CGPoint> {
        var low = 0
        var high = points.count
        while low < high {
            let middle = (low + high) / 2
            if points[middle].y <= along - tolerance { low = middle + 1 } else { high = middle }
        }
        var end = low
        while end < points.count && points[end].y < along + tolerance { end += 1 }
        return points[low..<end]
    }
}
