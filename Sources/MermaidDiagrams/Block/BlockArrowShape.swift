/**
 * File: BlockArrowShape.swift
 * ---------------------------
 * Layer: Core
 * Description: A block arrow as Pele draws one: the directions it points in, its size around its text, and its outline,
 *              a shaft with heads along one axis or a box with a point on each side it names.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// The directions a block arrow points in, Pele's mask (`arrows.ts`).
struct BlockArrowDirections: OptionSet, Equatable, Sendable {
    let rawValue: Int

    static let right = BlockArrowDirections(rawValue: 1)
    static let left = BlockArrowDirections(rawValue: 2)
    static let up = BlockArrowDirections(rawValue: 4)
    static let down = BlockArrowDirections(rawValue: 8)

    /// The directions written, spaces around each ignored (Mermaid compares them exactly): `x` is both across, `y` both
    /// down; anything else adds none.
    init(written: [String]) {
        var directions: BlockArrowDirections = []
        for direction in written {
            switch direction.trimmingCharacters(in: .whitespacesAndNewlines) {
            case "right": directions.insert(.right)
            case "left": directions.insert(.left)
            case "up": directions.insert(.up)
            case "down": directions.insert(.down)
            case "x": directions.formUnion([.right, .left])
            case "y": directions.formUnion([.up, .down])
            default: break
            }
        }
        self = directions
    }

    init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// The axis an arrow with a shaft runs along: across when it points only across, down when only up or down; nil for
    /// one that points both ways, or nowhere, drawn as a box with points.
    var axis: BlockArrowAxis? {
        if !isEmpty, isDisjoint(with: [.up, .down]) { return .across }
        if !isEmpty, isDisjoint(with: [.right, .left]) { return .down }
        return nil
    }

    /// 1 for a direction it points in, else 0.
    func count(_ direction: BlockArrowDirections) -> CGFloat {
        contains(direction) ? 1 : 0
    }
}

enum BlockArrowAxis: Equatable, Sendable {
    case across, down
}

/// Pele's arrow sizes and outlines.
enum BlockArrowShape {
    /// How far a head reaches past each side of its shaft.
    static let overhang: CGFloat = 7
    /// The deepest a head is.
    static let largestHeadDepth: CGFloat = 20
    /// How far a box's point reaches out.
    static let pointReach: CGFloat = 12

    /// The arrow's size around a text of `textSize`, and how far its text is moved from its center, away from its heads.
    static func size(of directions: BlockArrowDirections, textSize: CGSize) -> (size: CGSize, textOffset: CGVector) {
        let across = directions.count(.left) - directions.count(.right)
        let along = directions.count(.up) - directions.count(.down)
        switch directions.axis {
        case .across:
            let height = max(textSize.height + 8, 14) + 2 * overhang
            let depth = min(height / 2, largestHeadDepth)
            let width = max(textSize.width + 12, 16) + depth * (directions == [.right, .left] ? 2 : 1)
            return (CGSize(width: width, height: height), CGVector(dx: across * depth / 2, dy: 0))
        case .down:
            let width = max(textSize.width + 16, 14) + 2 * overhang
            let depth = min(width / 2, largestHeadDepth)
            let height = max(textSize.height + 8, 16) + depth * (directions == [.up, .down] ? 2 : 1)
            return (CGSize(width: width, height: height), CGVector(dx: 0, dy: along * depth / 2))
        case nil:
            let width = max(textSize.width + 16, 24) + pointReach * (directions.count(.left) + directions.count(.right))
            let height = max(textSize.height + 8, 24) + pointReach * (directions.count(.up) + directions.count(.down))
            return (CGSize(width: width, height: height), CGVector(dx: across * pointReach / 2, dy: along * pointReach / 2))
        }
    }

    /// The outline's corners around the arrow's center, for an arrow `size` large, in Pele's order.
    static func corners(of directions: BlockArrowDirections, size: CGSize) -> [CGPoint] {
        let halfWidth = size.width / 2
        let halfHeight = size.height / 2
        switch directions.axis {
        case .across: return acrossCorners(directions, halfWidth: halfWidth, halfHeight: halfHeight)
        case .down:
            // The same outline turned a quarter, x and y swapped, up and down for left and right.
            var turned: BlockArrowDirections = []
            if directions.contains(.down) { turned.insert(.right) }
            if directions.contains(.up) { turned.insert(.left) }
            let corners = acrossCorners(turned, halfWidth: halfHeight, halfHeight: halfWidth)
            return downCorners(from: corners)
        case nil: return boxCorners(directions, halfWidth: halfWidth, halfHeight: halfHeight)
        }
    }

    private static func acrossCorners(_ directions: BlockArrowDirections, halfWidth: CGFloat, halfHeight: CGFloat) -> [CGPoint] {
        let depth = min(halfHeight, largestHeadDepth)
        let shaft = halfHeight - overhang
        let start = directions.contains(.left) ? -halfWidth + depth : -halfWidth
        let end = directions.contains(.right) ? halfWidth - depth : halfWidth
        var corners = [CGPoint(x: start, y: -shaft), CGPoint(x: end, y: -shaft)]
        if directions.contains(.right) { corners += [CGPoint(x: end, y: -halfHeight), CGPoint(x: halfWidth, y: 0), CGPoint(x: end, y: halfHeight)] }
        corners += [CGPoint(x: end, y: shaft), CGPoint(x: start, y: shaft)]
        if directions.contains(.left) { corners += [CGPoint(x: start, y: halfHeight), CGPoint(x: -halfWidth, y: 0), CGPoint(x: start, y: -halfHeight)] }
        return corners
    }

    /// Pele's down arrow from the across one drawn on swapped axes: its points are (s, y0), (s, y1), … where the across
    /// one's are (x0, -s), (x1, -s), …, so each point's coordinates swap and the across one's y changes sign.
    private static func downCorners(from across: [CGPoint]) -> [CGPoint] {
        across.map { corner in CGPoint(x: -corner.y, y: corner.x) }
    }

    private static func boxCorners(_ directions: BlockArrowDirections, halfWidth: CGFloat, halfHeight: CGFloat) -> [CGPoint] {
        let left = directions.contains(.left) ? -halfWidth + pointReach : -halfWidth
        let right = directions.contains(.right) ? halfWidth - pointReach : halfWidth
        let top = directions.contains(.up) ? -halfHeight + pointReach : -halfHeight
        let bottom = directions.contains(.down) ? halfHeight - pointReach : halfHeight
        let middle = CGPoint(x: (left + right) / 2, y: (top + bottom) / 2)
        let notchAcross = min(10, (right - left) / 2)
        let notchDown = min(10, (bottom - top) / 2)
        var corners = [CGPoint(x: left, y: top)]
        if directions.contains(.up) {
            corners += [CGPoint(x: middle.x - notchAcross, y: top), CGPoint(x: middle.x, y: -halfHeight), CGPoint(x: middle.x + notchAcross, y: top)]
        }
        corners.append(CGPoint(x: right, y: top))
        if directions.contains(.right) {
            corners += [CGPoint(x: right, y: middle.y - notchDown), CGPoint(x: halfWidth, y: middle.y), CGPoint(x: right, y: middle.y + notchDown)]
        }
        corners.append(CGPoint(x: right, y: bottom))
        if directions.contains(.down) {
            corners += [CGPoint(x: middle.x + notchAcross, y: bottom), CGPoint(x: middle.x, y: halfHeight), CGPoint(x: middle.x - notchAcross, y: bottom)]
        }
        corners.append(CGPoint(x: left, y: bottom))
        if directions.contains(.left) {
            corners += [CGPoint(x: left, y: middle.y + notchDown), CGPoint(x: -halfWidth, y: middle.y), CGPoint(x: left, y: middle.y - notchDown)]
        }
        return corners
    }
}
