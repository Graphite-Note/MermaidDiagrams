/**
 * File: CynefinTransitionRouting.swift
 * ------------------------------------
 * Layer: Core
 * Description: Routes a Cynefin framework's transitions as Pele's renderCynefin does: a quadratic curve from block to
 *              block bowing away from the middle, cut where it leaves one block and enters the other, with its arrow and
 *              its label beside its middle.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics
import Foundation

/// Routes transitions between placed blocks. A curve bows away from the middle of the board, a diagonal far enough to
/// pass the ellipse, and each further transition between the same two domains 56 points farther; it starts where it
/// leaves its block (8 points past the block's frame, or 4 past the ellipse for confusion) and ends where it enters the
/// other, both found on 48 steps and then by 16 halvings. A transition that never leaves its block is not drawn.
struct CynefinTransitionRouting<Measurer: DiagramTextMeasuring> {
    let blocks: [CynefinLayoutBlock]
    let ellipse: CGRect
    let board: CGRect
    let labelText: Measurer

    /// How far past a block's frame, and past the ellipse, a curve is still inside.
    static var blockReach: CGFloat { 8 }
    static var ellipseReach: CGFloat { 4 }
    /// The bow of a curve between neighbours, as a share of its length; a diagonal's clears the ellipse by 16 points.
    static var bowShare: CGFloat { 0.15 }
    static var diagonalClearance: CGFloat { 16 }
    /// How much farther each repeated transition between two domains bows.
    static var repeatBow: CGFloat { 56 }
    static var stepCount: Int { 48 }
    static var halvingCount: Int { 16 }
    /// Between a label and its curve.
    static var labelGap: CGFloat { 6 }
    static var labelWrappingWidth: CGFloat { 200 }

    func routed(_ transitions: [CynefinTransition]) -> [CynefinLayoutTransition] {
        var repeats: [Set<CynefinDomain>: Int] = [:]
        var routed: [CynefinLayoutTransition] = []
        for transition in transitions {
            guard let from = block(transition.from), let to = block(transition.to), transition.from != transition.to else { continue }
            let pair: Set<CynefinDomain> = [transition.from, transition.to]
            let repeatCount = repeats[pair] ?? 0
            repeats[pair] = repeatCount + 1
            if let route = route(transition, from: from, to: to, repeatCount: repeatCount) { routed.append(route) }
        }
        return routed
    }

    private func block(_ domain: CynefinDomain) -> CynefinLayoutBlock? {
        blocks.first { block in block.domain == domain }
    }

    private func route(_ transition: CynefinTransition, from: CynefinLayoutBlock, to: CynefinLayoutBlock, repeatCount: Int) -> CynefinLayoutTransition? {
        let start = CGPoint(x: from.frame.midX, y: from.frame.midY)
        let end = CGPoint(x: to.frame.midX, y: to.frame.midY)
        let curve = bowedCurve(from: start, to: end, isDiagonal: from.domain != .confusion && to.domain != .confusion, repeatCount: repeatCount)
        var step = 1
        while step <= Self.stepCount && isInside(from, curve.point(CGFloat(step) / CGFloat(Self.stepCount))) { step += 1 }
        guard step <= Self.stepCount else { return nil }
        let leaving = crossing(from, curve: curve, low: CGFloat(step - 1) / CGFloat(Self.stepCount), high: CGFloat(step) / CGFloat(Self.stepCount), isLeaving: true)
        while step <= Self.stepCount && !isInside(to, curve.point(CGFloat(step) / CGFloat(Self.stepCount))) { step += 1 }
        let entering = step > Self.stepCount ? 1
            : crossing(to, curve: curve, low: CGFloat(step - 1) / CGFloat(Self.stepCount), high: CGFloat(step) / CGFloat(Self.stepCount), isLeaving: false)
        let piece = curve.piece(from: leaving, to: entering)
        let length = hypot(piece.end.x - piece.control.x, piece.end.y - piece.control.y)
        let direction = length == 0 ? CGVector(dx: 1, dy: 0) : CGVector(dx: (piece.end.x - piece.control.x) / length, dy: (piece.end.y - piece.control.y) / length)
        let trim = DiagramEdgeMark.lineTrim(for: .arrow)
        let lineEnd = CGPoint(x: piece.end.x - direction.dx * trim, y: piece.end.y - direction.dy * trim)
        let path = CynefinQuadraticCurve(start: piece.start, control: piece.control, end: lineEnd, normal: curve.normal).path
        let label = transition.label.flatMap { text in placedLabel(text, curve: curve, middle: (leaving + entering) / 2) }
        return CynefinLayoutTransition(from: transition.from, to: transition.to, path: path,
                                       arrow: DiagramEdgeMark(arrowhead: .arrow, tip: piece.end, direction: direction), label: label)
    }

    /// The curve from `start` to `end` through a control point beside their middle, on the side away from the board's
    /// middle.
    private func bowedCurve(from start: CGPoint, to end: CGPoint, isDiagonal: Bool, repeatCount: Int) -> CynefinQuadraticCurve {
        let across = end.x - start.x
        let down = end.y - start.y
        let measured = hypot(across, down)
        let length = measured == 0 ? 1 : measured
        let middle = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        let outward: CGFloat = -down * (middle.x - board.midX) + across * (middle.y - board.midY) >= 0 ? 1 : -1
        let normal = CGVector(dx: -down / length * outward, dy: across / length * outward)
        let diagonal = isDiagonal && abs(across) > 1 && abs(down) > 1
        let radii = CGSize(width: ellipse.width / 2, height: ellipse.height / 2)
        let bow = (diagonal ? 2 * (hypot(radii.width * normal.dx, radii.height * normal.dy) + Self.diagonalClearance) : length * Self.bowShare)
            + CGFloat(repeatCount) * Self.repeatBow
        return CynefinQuadraticCurve(start: start, control: CGPoint(x: middle.x + normal.dx * bow, y: middle.y + normal.dy * bow), end: end, normal: normal)
    }

    private func isInside(_ block: CynefinLayoutBlock, _ point: CGPoint) -> Bool {
        if block.domain == .confusion {
            let across = (point.x - ellipse.midX) / (ellipse.width / 2 + Self.ellipseReach)
            let down = (point.y - ellipse.midY) / (ellipse.height / 2 + Self.ellipseReach)
            return across * across + down * down <= 1
        }
        return abs(point.x - block.frame.midX) <= block.frame.width / 2 + Self.blockReach && abs(point.y - block.frame.midY) <= block.frame.height / 2 + Self.blockReach
    }

    /// Where the curve crosses the block's edge between `low` and `high`, by halving.
    private func crossing(_ block: CynefinLayoutBlock, curve: CynefinQuadraticCurve, low: CGFloat, high: CGFloat, isLeaving: Bool) -> CGFloat {
        var low = low
        var high = high
        for _ in 0..<Self.halvingCount {
            let middle = (low + high) / 2
            if isInside(block, curve.point(middle)) == isLeaving { low = middle } else { high = middle }
        }
        return (low + high) / 2
    }

    /// The label beside the curve's middle, on its outer side, kept within the board's width.
    private func placedLabel(_ text: String, curve: CynefinQuadraticCurve, middle: CGFloat) -> DiagramTextBlock? {
        guard let block = PlaneMapLabel.block(text, measurer: labelText, maximumWidth: Self.labelWrappingWidth) else { return nil }
        let point = curve.point(middle)
        let normal = curve.normal
        let away = abs(normal.dx) * block.size.width / 2 + abs(normal.dy) * block.size.height / 2 + Self.labelGap
        let half = block.size.width / 2 + 4
        let x = min(max(point.x + normal.dx * away, board.minX + half), max(board.maxX - half, board.minX + half))
        return PlaneMapLabel.placed(block, at: CGPoint(x: x, y: point.y + normal.dy * away))
    }
}

/// A quadratic curve, and the unit normal it bowed along.
struct CynefinQuadraticCurve {
    let start: CGPoint
    let control: CGPoint
    let end: CGPoint
    let normal: CGVector

    /// The point at `parameter`, from 0 at the start to 1 at the end.
    func point(_ parameter: CGFloat) -> CGPoint {
        let rest = 1 - parameter
        return CGPoint(x: rest * rest * start.x + 2 * rest * parameter * control.x + parameter * parameter * end.x,
                       y: rest * rest * start.y + 2 * rest * parameter * control.y + parameter * parameter * end.y)
    }

    /// The part of the curve from `first` to `last`: its ends, and its control point found by blossoming.
    func piece(from first: CGFloat, to last: CGFloat) -> (start: CGPoint, control: CGPoint, end: CGPoint) {
        func blossom(_ startValue: CGFloat, _ controlValue: CGFloat, _ endValue: CGFloat) -> CGFloat {
            (1 - first) * (1 - last) * startValue + ((1 - first) * last + first * (1 - last)) * controlValue + first * last * endValue
        }
        return (point(first), CGPoint(x: blossom(start.x, control.x, end.x), y: blossom(start.y, control.y, end.y)), point(last))
    }

    /// The curve as cubic segments, its control points two thirds of the way to the quadratic one, the same curve.
    var path: DiagramPath {
        let twoThirds: CGFloat = 2.0 / 3.0
        let firstControl = CGPoint(x: start.x + twoThirds * (control.x - start.x), y: start.y + twoThirds * (control.y - start.y))
        let secondControl = CGPoint(x: end.x + twoThirds * (control.x - end.x), y: end.y + twoThirds * (control.y - end.y))
        return DiagramPath(start: start, segments: [.curve(to: end, control1: firstControl, control2: secondControl)])
    }
}
