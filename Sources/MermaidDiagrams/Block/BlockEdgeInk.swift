/**
 * File: BlockEdgeInk.swift
 * ------------------------
 * Layer: Core
 * Description: How a block diagram's edge is inked over the composites a style fills, as Pele's overFills and
 *              edgeCasing (src/svg/edges.ts) decide it: plain, on a page-colored casing, or in the fill's own ink; an
 *              agent flow's edges over the flows a style fills are inked the same way.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 20/11/2026
 */

import CoreGraphics

/// How an edge is drawn over the composites a style fills: plain where it touches none; on a casing, a wider stroke of
/// the page's color under it, where it crosses the border of one (or lies on one whose ink Pele cannot pick, under half
/// opacity); in the dark or white ink that contrasts with the innermost one that holds the whole of it and its marks.
enum BlockEdgeInk: Equatable {
    case plain
    case cased
    case inked(DiagramColor)

    /// A composite's box and the fill its style sets, for each composite whose fill paints (not `none`, not fully clear).
    static func fills(of composites: [BlockLayoutComposite]) -> [(box: CGRect, color: DiagramColor)] {
        composites.compactMap { composite in
            guard let color = composite.appearance.style.fill, color.alpha > 0 else { return nil }
            return (composite.frame, color)
        }
    }

    /// How many edges and filled composites are looked at together at most; past it every edge is drawn plain, so a
    /// diagram of thousands of both is not slow to draw (Pele has no such bound).
    static let comparisonBudget = 2_000_000

    /// Each edge's ink over the filled composites, in the order of `edges`.
    static func inks(of edges: [BlockLayoutEdge], over composites: [BlockLayoutComposite]) -> [BlockEdgeInk] {
        let fills = fills(of: composites)
        guard !fills.isEmpty, edges.count * fills.count <= comparisonBudget else { return Array(repeating: .plain, count: edges.count) }
        return edges.map { edge in ink(of: edge, over: fills) }
    }

    /// Pele's `fillUnder` then `edgeInk`, for `edge` over `fills`.
    static func ink(of edge: BlockLayoutEdge, over fills: [(box: CGRect, color: DiagramColor)]) -> BlockEdgeInk {
        guard !fills.isEmpty else { return .plain }
        let points = sampledPoints(of: edge.path)
        return ink(along: points, tips: [edge.sourceMark?.tip ?? edge.path.start, edge.targetMark?.tip ?? points[points.count - 1]], over: fills)
    }

    /// Pele's `fillUnder` then `edgeInk` for a path whose end's mark reaches `targetTip`, or that ends where its path
    /// does: an agent flow looks at its edges' ends only.
    static func ink(of path: DiagramPath, targetTip: CGPoint?, over fills: [(box: CGRect, color: DiagramColor)]) -> BlockEdgeInk {
        guard !fills.isEmpty else { return .plain }
        let points = sampledPoints(of: path)
        return ink(along: points, tips: [targetTip ?? points[points.count - 1]], over: fills)
    }

    private static func ink(along points: [CGPoint], tips: [CGPoint], over fills: [(box: CGRect, color: DiagramColor)]) -> BlockEdgeInk {
        var extent = CGRect.null
        for point in points + tips { extent = extent.union(CGRect(origin: point, size: .zero)) }
        var holder: (area: CGFloat, color: DiagramColor)?
        for fill in fills {
            let inner = fill.box.insetBy(dx: borderTolerance, dy: borderTolerance)
            if extent.maxX < inner.minX || extent.minX > inner.maxX || extent.maxY < inner.minY || extent.minY > inner.maxY { continue }
            let touched = enters(points, inner) || tips.contains { tip in tip.x > inner.minX && tip.x < inner.maxX && tip.y > inner.minY && tip.y < inner.maxY }
            guard touched else { continue }
            if extent.minX < fill.box.minX || extent.maxX > fill.box.maxX || extent.minY < fill.box.minY || extent.maxY > fill.box.maxY { return .cased }
            let area = fill.box.width * fill.box.height
            if area < holder?.area ?? .infinity { holder = (area, fill.color) }
        }
        guard let holder else { return .plain }
        return SequenceTextInk.ink(onColor: holder.color).map(BlockEdgeInk.inked) ?? .cased
    }

    /// How far inside a box's border an edge must reach to touch it, so one that runs along the border does not.
    private static let borderTolerance: CGFloat = 0.5
    /// The points a curve is sampled at, eight along it, as Pele samples one.
    private static let curveSampleCount = 8

    /// The path's corners and eight points along each curve.
    private static func sampledPoints(of path: DiagramPath) -> [CGPoint] {
        var points = [path.start]
        var current = path.start
        for segment in path.segments {
            switch segment {
            case .line(let end):
                points.append(end)
                current = end
            case .curve(let end, let firstControl, let secondControl):
                for step in 1...curveSampleCount {
                    let along = CGFloat(step) / CGFloat(curveSampleCount)
                    let remaining = 1 - along
                    let weights = (remaining * remaining * remaining, 3 * remaining * remaining * along, 3 * remaining * along * along, along * along * along)
                    points.append(CGPoint(x: weights.0 * current.x + weights.1 * firstControl.x + weights.2 * secondControl.x + weights.3 * end.x,
                                          y: weights.0 * current.y + weights.1 * firstControl.y + weights.2 * secondControl.y + weights.3 * end.y))
                }
                current = end
            }
        }
        return points
    }

    /// Whether a run between two of `points` passes inside `box` (Pele's `enters`, clipping each run to the box).
    private static func enters(_ points: [CGPoint], _ box: CGRect) -> Bool {
        for index in points.indices.dropLast() {
            let from = points[index]
            let to = points[index + 1]
            if (from.x < box.minX && to.x < box.minX) || (from.x > box.maxX && to.x > box.maxX)
                || (from.y < box.minY && to.y < box.minY) || (from.y > box.maxY && to.y > box.maxY) { continue }
            if clips(from: from, by: CGVector(dx: to.x - from.x, dy: to.y - from.y), box) { return true }
        }
        return false
    }

    /// Liang and Barsky's test: whether the run from `from` along `delta` keeps a part of some length inside `box`.
    private static func clips(from: CGPoint, by delta: CGVector, _ box: CGRect) -> Bool {
        var low: CGFloat = 0
        var high: CGFloat = 1
        let sides: [(along: CGFloat, room: CGFloat)] = [(-delta.dx, from.x - box.minX), (delta.dx, box.maxX - from.x),
                                                        (-delta.dy, from.y - box.minY), (delta.dy, box.maxY - from.y)]
        for side in sides {
            if side.along == 0 {
                if side.room < 0 { high = -1 }
            } else if side.along < 0 {
                low = max(low, side.room / side.along)
            } else {
                high = min(high, side.room / side.along)
            }
        }
        return low < high
    }
}
