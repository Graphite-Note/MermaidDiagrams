/**
 * File: StateDiagramCompositeTitles.swift
 * ---------------------------------------
 * Layer: Core
 * Description: Where a composite state's name sits in the band along its box's top, as Pele's state diagram places it,
 *              the transitions' bends found in a sorted span of the thread's scratch arena.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 26/11/2026
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
    /// In the calling thread's arena, sorted by that place, so that the bends at one height are a run found by halving.
    private let bends: ScratchSpan<Bend>

    /// A bend's place down the page, rounded, and across it.
    private struct Bend {
        let roundedHeight: Int
        let x: CGFloat
    }

    /// The bends of every route of a compound layout: each route's points but its two ends.
    init(compound: LayeredCompoundLayout, arena: DiagramScratchArena) {
        var bends = arena.list(capacity: compound.routePoints.count, of: Bend.self)
        for edge in 0..<compound.edges.count {
            let range = compound.routeRange(of: edge)
            guard range.count > 2 else { continue }
            for index in (range.lowerBound + 1)..<(range.upperBound - 1) {
                let point = compound.routePoints[index].point
                guard let key = Self.roundedHeight(point.y) else { continue }
                bends.append(Bend(roundedHeight: key, x: point.x))
            }
        }
        // Which bends share a height matters, not their order: the clearest place takes the least gap to any of them.
        var sorted = bends.elements.buffer
        sorted.sort { first, second in first.roundedHeight < second.roundedHeight }
        self.bends = bends.elements
    }

    /// The bends at `roundedHeight`: a run of `bends`, empty for none.
    private func bends(at roundedHeight: Int) -> ScratchSpan<Bend> {
        var low = 0
        var high = bends.count
        while low < high {
            let middle = (low + high) / 2
            if bends[middle].roundedHeight < roundedHeight { low = middle + 1 } else { high = middle }
        }
        var end = low
        while end < bends.count, bends[end].roundedHeight == roundedHeight { end += 1 }
        return bends.part(low..<end)
    }

    /// `title` placed in the band along the top of `frame`, the band `title`'s height and `StateDiagramClusterGraph.titleRoom`.
    func placed(_ title: DiagramTextBlock, in frame: CGRect) -> DiagramTextBlock {
        var placed = title
        let band = title.size.height + StateDiagramClusterGraph.titleRoom
        placed.center = CGPoint(x: across(width: title.size.width, in: frame), y: frame.minY + band / 2)
        return placed
    }

    private func across(width: CGFloat, in frame: CGRect) -> CGFloat {
        guard let key = Self.roundedHeight(frame.minY), case let bends = bends(at: key), !bends.isEmpty, width > 0 else { return frame.midX }
        let half = width / 2
        let padding = StateDiagramClusterGraph.compositePadding
        var best = frame.midX
        var bestGap: CGFloat = -1
        for candidate in [frame.midX, frame.minX + padding + half, frame.maxX - padding - half] {
            var gap = CGFloat.infinity
            for bend in bends where bend.x > frame.minX && bend.x < frame.maxX { gap = min(gap, abs(bend.x - candidate) - half) }
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
