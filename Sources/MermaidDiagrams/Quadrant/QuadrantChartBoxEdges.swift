/**
 * File: QuadrantChartBoxEdges.swift
 * ---------------------------------
 * Layer: Core
 * Description: A box a quadrant chart's point text is kept clear of, by its edges read once, as a rectangle's own
 *              `minX` to `maxY` read them, so that placing a text compares numbers instead of reading each box again.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics

/// A rectangle's edges, as `CGRect.minX`, `minY`, `maxX` and `maxY` give them for it (a negative size included).
struct QuadrantChartBoxEdges {
    let minX: CGFloat
    let minY: CGFloat
    let maxX: CGFloat
    let maxY: CGFloat

    init(_ box: CGRect) {
        minX = box.minX
        minY = box.minY
        maxX = box.maxX
        maxY = box.maxY
    }

    /// Whether the box is inside `outer`, its edges on `outer`'s included.
    func isInside(_ outer: QuadrantChartBoxEdges) -> Bool {
        minX >= outer.minX && maxX <= outer.maxX && minY >= outer.minY && maxY <= outer.maxY
    }

    /// Whether the box overlaps none of `boxes` from `start` on, edges that only touch apart; an empty box is a point that
    /// a box overlaps when the point is strictly inside it.
    func isClear(of boxes: [QuadrantChartBoxEdges], from start: Int) -> Bool {
        var index = start
        while index < boxes.count {
            let other = boxes[index]
            if minX < other.maxX && maxX > other.minX && minY < other.maxY && maxY > other.minY { return false }
            index += 1
        }
        return true
    }
}
