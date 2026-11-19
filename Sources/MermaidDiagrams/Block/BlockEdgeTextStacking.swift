/**
 * File: BlockEdgeTextStacking.swift
 * ---------------------------------
 * Layer: Core
 * Description: Stacks the texts of edges between the same two blocks along their shared line, measures how much the
 *              texts cover each other, and widens the gap a pair's texts do not fit in, as Pele's block renderer does.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

extension BlockEdgePlacement {
    /// Pele's `stackLabels`: texts on one straight shared line that cover each other are stacked along it between its
    /// marks, unless one would then cover another block or a title; the length the line lacks for them, or zero.
    mutating func stackTexts(_ members: [Int], end: (source: Int, target: Int), obstacles: [BlockObstacle]?) -> CGFloat {
        guard let firstLeg = legs[members[0]] else { return 0 }
        let isVertical = firstLeg[0].x == firstLeg[1].x
        var low = -CGFloat.infinity
        var high = CGFloat.infinity
        var need = -Self.textGap
        var isCrowded = false
        for (place, member) in members.enumerated() {
            guard let leg = legs[member], isVertical ? leg[0].x == leg[1].x : leg[0].y == leg[1].y else { return 0 }
            low = max(low, isVertical ? min(leg[0].y, leg[1].y) : min(leg[0].x, leg[1].x))
            high = min(high, isVertical ? max(leg[0].y, leg[1].y) : max(leg[0].x, leg[1].x))
            let route = routes[member]
            need += (isVertical ? route.textSize.height : route.textSize.width + 8) + Self.textGap
            for earlier in members[..<place] where Self.cover(route, routes[earlier]) { isCrowded = true }
        }
        guard isCrowded else { return 0 }
        let room = high - low - 2 * DiagramEdgeMark.arrowLength
        if need > room { return need - room }
        var along: [CGFloat] = []
        var next = (low + high - need) / 2
        for member in members {
            let route = routes[member]
            let length = isVertical ? route.textSize.height : route.textSize.width + 8
            let at = next + length / 2
            let center = isVertical ? CGPoint(x: route.textCenter.x, y: at) : CGPoint(x: at, y: route.textCenter.y)
            if Self.covers(center, size: CGSize(width: route.textSize.width + 8, height: route.textSize.height), end: end, obstacles: obstacles) { return 0 }
            along.append(at)
            next += length + Self.textGap
        }
        for (member, at) in zip(members, along) {
            if isVertical { routes[member].textCenter.y = at } else { routes[member].textCenter.x = at }
        }
        return 0
    }

    /// Whether two texts are close enough to cover each other, 8 points of patch across.
    private static func cover(_ first: BlockRoute, _ second: BlockRoute) -> Bool {
        abs(first.textCenter.x - second.textCenter.x) < (first.textSize.width + second.textSize.width) / 2 + 8
            && abs(first.textCenter.y - second.textCenter.y) < (first.textSize.height + second.textSize.height) / 2
    }

    /// Pele's `overlap`: the area the texts' patches cover each other by, pair by pair.
    var textOverlap: CGFloat {
        var area: CGFloat = 0
        for first in routes.indices where routes[first].textSize.width > 0 {
            let one = routes[first]
            for second in (first + 1)..<routes.count where routes[second].textSize.width > 0 {
                let other = routes[second]
                let halfWidths = ((one.textSize.width + 8) / 2, (other.textSize.width + 8) / 2)
                let width = min(one.textCenter.x + halfWidths.0, other.textCenter.x + halfWidths.1) - max(one.textCenter.x - halfWidths.0, other.textCenter.x - halfWidths.1)
                let height = min(one.textCenter.y + one.textSize.height / 2, other.textCenter.y + other.textSize.height / 2)
                    - max(one.textCenter.y - one.textSize.height / 2, other.textCenter.y - other.textSize.height / 2)
                if width > 0, height > 0 { area += width * height }
            }
        }
        return area
    }

    /// Pele's `bound`: the drawing's extent, the grid's grown by the loops and the texts.
    func extent(contentSize: CGSize, outlines: [BlockOutline]) -> CGRect {
        var extent = CGRect(origin: .zero, size: contentSize)
        for (index, route) in routes.enumerated() {
            if route.loopCount > 0 {
                let arc = BlockEdgePaths.loopArc(on: outlines[ends[index].source], count: route.loopCount)
                extent = extent.union(CGRect(x: arc.center.x - arc.radius - 1, y: arc.center.y - arc.radius - 1, width: 2 * arc.radius + 2, height: 2 * arc.radius + 2))
            }
            if route.textSize.width > 0 {
                extent = extent.union(CGRect(x: route.textCenter.x - (route.textSize.width + 8) / 2, y: route.textCenter.y - route.textSize.height / 2,
                                             width: route.textSize.width + 8, height: route.textSize.height))
            }
        }
        return extent
    }
}

/// Pele's `widen`, keeping the gaps as they were when the texts were measured, so that a round widens each gap once.
struct BlockGapWidening {
    private var baseGaps: [BlockGapKey: [CGFloat]] = [:]

    private struct BlockGapKey: Hashable {
        let cellIndex: Int
        let isVertical: Bool
    }

    /// Widens the gap between the two blocks' children of their nearest shared container by `short`; whether it did.
    mutating func widen(_ placement: inout BlockPlacement, between end: (source: Int, target: Int), isVertical: Bool, by short: CGFloat) -> Bool {
        let parents = placement.parentIndices
        var sourceChain: Set<Int> = []
        var walker = end.source
        while walker >= 0 {
            sourceChain.insert(walker)
            walker = parents[walker]
        }
        var targetChild = -1
        var shared = end.target
        while shared >= 0, !sourceChain.contains(shared) {
            targetChild = shared
            shared = parents[shared]
        }
        guard shared >= 0, targetChild >= 0, shared != end.source else { return false }
        var sourceChild = end.source
        while parents[sourceChild] != shared { sourceChild = parents[sourceChild] }
        let source = placement.cells[sourceChild]
        let target = placement.cells[targetChild]
        let at: Int
        if isVertical {
            guard source.row != target.row else { return false }
            at = max(source.row, target.row) - 1
        } else {
            let (left, right) = source.column < target.column ? (source, target) : (target, source)
            guard right.column >= left.column + left.span else { return false }
            at = right.column - 1
        }
        let key = BlockGapKey(cellIndex: shared, isVertical: isVertical)
        var gaps = isVertical ? placement.cells[shared].rowGaps : placement.cells[shared].columnGaps
        if baseGaps[key] == nil { baseGaps[key] = gaps }
        if gaps.count <= at { gaps += [CGFloat](repeating: 0, count: at + 1 - gaps.count) }
        gaps[at] = max(gaps[at], BlockGridLayout.gapAt(baseGaps[key] ?? [], at) + short)
        if isVertical { placement.cells[shared].rowGaps = gaps } else { placement.cells[shared].columnGaps = gaps }
        return true
    }
}
