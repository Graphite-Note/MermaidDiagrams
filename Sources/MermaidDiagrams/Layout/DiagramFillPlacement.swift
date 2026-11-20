/**
 * File: DiagramFillPlacement.swift
 * --------------------------------
 * Layer: Core
 * Description: Where a drawn line lies among the boxes a style fills, as Pele's fillUnder finds it: on none, across a
 *              border, or inside the innermost box that holds it and its marks' tips whole.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// Where a line lies among filled boxes (Pele's `fillUnder`): a box it neither enters nor touches with a tip is not
/// under it; one it enters and leaves puts it across a border, which is cased; else the smallest box that holds it.
enum DiagramFillPlacement: Equatable {
    case onNone
    case acrossBorder
    /// Inside the box of this place among the frames.
    case inside(Int)

    static func placement(of path: DiagramPath, tips: [CGPoint], among frames: [CGRect]) -> DiagramFillPlacement {
        guard !frames.isEmpty else { return .onNone }
        let points = sampled(path)
        let all = points + tips
        let minimumX = all.map(\.x).min() ?? 0
        let maximumX = all.map(\.x).max() ?? 0
        let minimumY = all.map(\.y).min() ?? 0
        let maximumY = all.map(\.y).max() ?? 0
        var holder: Int?
        var least = CGFloat.infinity
        for (place, frame) in frames.enumerated() {
            if maximumX < frame.minX + 0.5 || minimumX > frame.maxX - 0.5 || maximumY < frame.minY + 0.5 || minimumY > frame.maxY - 0.5 { continue }
            let inner = frame.insetBy(dx: 0.5, dy: 0.5)
            let isTouched = enters(points, inner) || tips.contains { tip in tip.x > inner.minX && tip.x < inner.maxX && tip.y > inner.minY && tip.y < inner.maxY }
            guard isTouched else { continue }
            if minimumX < frame.minX || maximumX > frame.maxX || minimumY < frame.minY || maximumY > frame.maxY { return .acrossBorder }
            let area = frame.width * frame.height
            if area < least {
                least = area
                holder = place
            }
        }
        return holder.map(DiagramFillPlacement.inside) ?? .onNone
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
