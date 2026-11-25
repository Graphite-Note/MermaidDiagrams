/**
 * File: StateDiagramCompositeTitles.swift
 * ---------------------------------------
 * Layer: Core
 * Description: Where a composite state's name sits in the band along its box's top, as Pele's state diagram places it.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

import CoreGraphics

/// Where a composite state's name sits in its title band, as Pele's state diagram places it (state/render.ts `titleX`):
/// in the band's middle, down the page, and across it at the box's middle, else 16 points from its left, else 16 points
/// from its right, the first that keeps 6 points clear of every transition bending on the box's top; where none does,
/// the one farthest from them. Unlike a flowchart group's title it is never drawn over the transitions.
struct StateDiagramCompositeTitles {
    /// The least room between a transition crossing the box's top and the name's letters.
    static let clearance: CGFloat = 6
    /// A place must be clearer than the best so far by this much to be preferred.
    static let preferenceMargin: CGFloat = 0.5

    /// The across-the-page places of the transitions' bends, by their place down the page rounded as JavaScript's
    /// `Math.round` rounds it; a transition's two ends are left out, as Pele leaves them out.
    private var bendsByRoundedHeight: [Int: [CGFloat]] = [:]

    /// The bends of every route of a compound layout: each route's points but its two ends.
    init(compound: LayeredCompoundLayout) {
        for edge in 0..<compound.edges.count {
            let range = compound.routeRange(of: edge)
            guard range.count > 2 else { continue }
            for index in (range.lowerBound + 1)..<(range.upperBound - 1) {
                let point = compound.routePoints[index].point
                guard let key = Self.roundedHeight(point.y) else { continue }
                bendsByRoundedHeight[key, default: []].append(point.x)
            }
        }
    }

    /// `title` placed in the band along the top of `frame`, the band `title`'s height and `StateDiagramClusterGraph.titleRoom`.
    func placed(_ title: DiagramTextBlock, in frame: CGRect) -> DiagramTextBlock {
        var placed = title
        let band = title.size.height + StateDiagramClusterGraph.titleRoom
        placed.center = CGPoint(x: across(width: title.size.width, in: frame), y: frame.minY + band / 2)
        return placed
    }

    private func across(width: CGFloat, in frame: CGRect) -> CGFloat {
        guard let key = Self.roundedHeight(frame.minY), let bends = bendsByRoundedHeight[key], width > 0 else { return frame.midX }
        let half = width / 2
        let padding = StateDiagramClusterGraph.compositePadding
        var best = frame.midX
        var bestGap: CGFloat = -1
        for candidate in [frame.midX, frame.minX + padding + half, frame.maxX - padding - half] {
            var gap = CGFloat.infinity
            for bend in bends where bend > frame.minX && bend < frame.maxX { gap = min(gap, abs(bend - candidate) - half) }
            if gap >= Self.clearance { return candidate }
            if gap > bestGap + Self.preferenceMargin {
                bestGap = gap
                best = candidate
            }
        }
        return best
    }

    /// JavaScript's `Math.round` (halves up), or nil for a place too far out to be a key.
    private static func roundedHeight(_ height: CGFloat) -> Int? {
        let rounded = (height + 0.5).rounded(.down)
        return rounded.isFinite && abs(rounded) < 1e15 ? Int(rounded) : nil
    }
}
