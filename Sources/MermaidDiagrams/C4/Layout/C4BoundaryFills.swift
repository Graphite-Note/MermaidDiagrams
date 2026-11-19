/**
 * File: C4BoundaryFills.swift
 * ---------------------------
 * Layer: Core
 * Description: How a C4 relation is painted over the boundaries a style fills, as Pele's svg/edges.ts decides it: in
 *              the text color picked for the fill it lies on, or cased in the page's color where it crosses a border.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// A boundary a style fills: its frame and its look.
struct C4BoundaryFill {
    let frame: CGRect
    let look: C4ElementLook
}

/// Pele's `fillUnder`, `edgeInk` and `overFills` for C4 relations.
enum C4BoundaryFills {
    /// Where a line lies among the fills: on none, across a border, or inside one, the innermost that holds it whole.
    private enum Placement {
        case onNone
        case acrossBorder
        case inside(C4BoundaryFill)
    }

    /// The line's color and whether it is cased. Off every fill it keeps its own color. Inside a fill it takes the text
    /// color picked for the fill, unless its style sets a stroke or no color is picked, when it is cased instead, as it is
    /// across a border.
    static func painting(of route: C4Route, lineColor written: String?, fills: [C4BoundaryFill]) -> (lineColor: DiagramColor?, isCased: Bool) {
        let ownColor = C4ElementLook.color(written, property: "stroke")
        switch placement(of: route, among: fills) {
        case .onNone: return (ownColor, false)
        case .acrossBorder: return (ownColor, true)
        case .inside(let fill):
            if C4ElementLook.isWritten(written) { return (ownColor, true) }
            guard let ink = fill.look.inkForLines else { return (nil, true) }
            return (ink, false)
        }
    }

    private static func placement(of route: C4Route, among fills: [C4BoundaryFill]) -> Placement {
        guard !fills.isEmpty else { return .onNone }
        let points = sampled(route.path)
        let tips = [route.start, route.end]
        let all = points + tips
        let minimumX = all.map(\.x).min() ?? 0
        let maximumX = all.map(\.x).max() ?? 0
        let minimumY = all.map(\.y).min() ?? 0
        let maximumY = all.map(\.y).max() ?? 0
        var holder: C4BoundaryFill?
        var least = CGFloat.infinity
        for fill in fills {
            let frame = fill.frame
            if maximumX < frame.minX + 0.5 || minimumX > frame.maxX - 0.5 || maximumY < frame.minY + 0.5 || minimumY > frame.maxY - 0.5 { continue }
            let inner = frame.insetBy(dx: 0.5, dy: 0.5)
            let isTouched = enters(points, inner) || tips.contains { tip in tip.x > inner.minX && tip.x < inner.maxX && tip.y > inner.minY && tip.y < inner.maxY }
            guard isTouched else { continue }
            if minimumX < frame.minX || maximumX > frame.maxX || minimumY < frame.minY || maximumY > frame.maxY { return .acrossBorder }
            let area = frame.width * frame.height
            if area < least {
                least = area
                holder = fill
            }
        }
        return holder.map(Placement.inside) ?? .onNone
    }

    /// The path's points as Pele samples a drawn path: its start, each line's end, and each curve at every eighth.
    private static func sampled(_ path: DiagramPath) -> [CGPoint] {
        var points = [path.start]
        var current = path.start
        for segment in path.segments {
            switch segment {
            case .line(let end):
                points.append(end)
                current = end
            case .curve(let end, let firstControl, let secondControl):
                for step in 1...8 {
                    let fraction = CGFloat(step) / 8
                    let remaining = 1 - fraction
                    let x = remaining * remaining * remaining * current.x + 3 * remaining * remaining * fraction * firstControl.x
                        + 3 * remaining * fraction * fraction * secondControl.x + fraction * fraction * fraction * end.x
                    let y = remaining * remaining * remaining * current.y + 3 * remaining * remaining * fraction * firstControl.y
                        + 3 * remaining * fraction * fraction * secondControl.y + fraction * fraction * fraction * end.y
                    points.append(CGPoint(x: x, y: y))
                }
                current = end
            }
        }
        return points
    }

    /// Whether a stretch between two of the points enters the rectangle (Pele's `enters`, by its `clips`).
    private static func enters(_ points: [CGPoint], _ rectangle: CGRect) -> Bool {
        guard points.count > 1 else { return false }
        for index in 1..<points.count {
            let start = points[index - 1]
            let end = points[index]
            if (start.x < rectangle.minX && end.x < rectangle.minX) || (start.x > rectangle.maxX && end.x > rectangle.maxX)
                || (start.y < rectangle.minY && end.y < rectangle.minY) || (start.y > rectangle.maxY && end.y > rectangle.maxY) { continue }
            if clips(start, CGVector(dx: end.x - start.x, dy: end.y - start.y), rectangle) { return true }
        }
        return false
    }

    private static func clips(_ start: CGPoint, _ delta: CGVector, _ rectangle: CGRect) -> Bool {
        var low: CGFloat = 0
        var high: CGFloat = 1
        let sides: [(CGFloat, CGFloat)] = [(-delta.dx, start.x - rectangle.minX), (delta.dx, rectangle.maxX - start.x),
                                           (-delta.dy, start.y - rectangle.minY), (delta.dy, rectangle.maxY - start.y)]
        for (direction, distance) in sides {
            if direction == 0 {
                if distance < 0 { high = -1 }
            } else if direction < 0 {
                low = max(low, distance / direction)
            } else {
                high = min(high, distance / direction)
            }
        }
        return low < high
    }
}
