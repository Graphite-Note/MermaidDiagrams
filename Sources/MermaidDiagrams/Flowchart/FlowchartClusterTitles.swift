/**
 * File: FlowchartClusterTitles.swift
 * ----------------------------------
 * Layer: Core
 * Description: Where a group's title sits along the top of its box, clear of the edges crossing it where it can be.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

import CoreGraphics

/// Where a group's title sits along the top of its box, as Pele places it: at the left, else the middle, else the
/// right, the first that keeps clear of every edge crossing the box's top; where none does, the one farthest from
/// them, and when an edge still runs through it the title is drawn over the edges (`FlowchartLayoutCluster`).
enum FlowchartClusterTitles {
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

    /// The title placed in `frame`, `FlowchartClusterGraph.titleMargin` below its top, and whether an edge runs through it.
    /// - Parameter edgePoints: The points every edge passes through, its ends on their outlines included.
    static func placed(_ title: DiagramTextBlock, in frame: CGRect, edgePoints: [[CGPoint]]) -> (title: DiagramTextBlock, isCrossed: Bool) {
        placed(title, in: frame, crossings: FlowchartRoutePointIndex(edgePoints))
    }

    /// The title placed in `frame`, the edges' points looked up in `crossings`, sorted once for every box.
    static func placed(_ title: DiagramTextBlock, in frame: CGRect, crossings index: FlowchartRoutePointIndex) -> (title: DiagramTextBlock, isCrossed: Bool) {
        placed(title, in: frame, near: index.points(within: topTolerance, of: frame.minY))
    }

    /// The title placed in `frame`, among `points` sorted down the page by y.
    static func placed(_ title: DiagramTextBlock, in frame: CGRect, sortedPoints points: ScratchSpan<CGPoint>) -> (title: DiagramTextBlock, isCrossed: Bool) {
        placed(title, in: frame, near: points.part(FlowchartRoutePointIndex.range(within: topTolerance, of: frame.minY, in: points)))
    }

    /// The title placed in `frame`, `points` those near its top: the ones strictly between its sides cross it.
    private static func placed<Points: Collection<CGPoint>>(_ title: DiagramTextBlock, in frame: CGRect, near points: Points) -> (title: DiagramTextBlock, isCrossed: Bool) {
        let halfWidth = title.size.width / 2
        let padding = FlowchartClusterGraph.clusterPadding
        let candidates = (frame.minX + padding - sideReach + halfWidth, frame.midX, frame.maxX - padding + sideReach - halfWidth)
        var best = candidates.0
        // As in Pele, another place replaces the left only where no crossing reaches half a point into its letters,
        // and then only a clearer one.
        var bestGap: CGFloat = -1
        for candidateIndex in 0..<3 {
            let candidate = candidateIndex == 0 ? candidates.0 : candidateIndex == 1 ? candidates.1 : candidates.2
            var gap = CGFloat.greatestFiniteMagnitude
            var isFirst = true
            for point in points where point.x > frame.minX && point.x < frame.maxX {
                let distance = abs(point.x - candidate) - halfWidth
                if isFirst || distance < gap { gap = distance }
                isFirst = false
            }
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
        placed.center = CGPoint(x: best, y: frame.minY + FlowchartClusterGraph.titleMargin + title.size.height / 2)
        let isCrossed = points.contains { point in point.x > frame.minX && point.x < frame.maxX && abs(point.x - best) < halfWidth + crossingReach }
        return (placed, isCrossed)
    }
}

/// The points edges pass through, sorted down the page once, so that the points on each box's top are found by search.
struct FlowchartRoutePointIndex {
    private let points: [CGPoint]

    init(_ routes: [[CGPoint]]) {
        points = routes.joined().sorted { first, second in first.y < second.y }
    }

    /// The points less than `tolerance` from the line `along` across the page, in the order they are sorted.
    func points(within tolerance: CGFloat, of along: CGFloat) -> ArraySlice<CGPoint> {
        points[Self.range(within: tolerance, of: along, in: points)]
    }

    /// Where the points less than `tolerance` from the line `along` are in `points`, sorted down the page.
    static func range<Points: RandomAccessCollection<CGPoint>>(within tolerance: CGFloat, of along: CGFloat, in points: Points) -> Range<Int>
        where Points.Index == Int {
        var low = points.startIndex
        var high = points.endIndex
        while low < high {
            let middle = (low + high) / 2
            if points[middle].y <= along - tolerance { low = middle + 1 } else { high = middle }
        }
        var end = low
        while end < points.endIndex && points[end].y < along + tolerance { end += 1 }
        return low..<end
    }
}
