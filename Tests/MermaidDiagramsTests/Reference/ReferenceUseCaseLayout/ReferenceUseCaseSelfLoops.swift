/**
 * File: ReferenceUseCaseSelfLoops.swift
 * -------------------------------------
 * Layer: Tests
 * Description: The 0.7.0 (de81532) use case layout kept as the reference the flat one is checked against. A use case
 *              diagram's relationship from a node to itself, as Pele's renderUsecase draws it: a curve out across the
 *              flow and back, each further loop reaching further, its label beyond it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// A loop leaves a node across the flow (below it when the flow runs across, to its right when it runs down), both
/// ends leaning away from each other, and the curve joins them outside; the node's box in the layout grows to hold it.
enum ReferenceUseCaseSelfLoops {
    static let reach: CGFloat = 26
    /// How much further each loop after the first spreads its ends and reaches.
    static let spreadStep: CGFloat = 6
    static let reachStep: CGFloat = 8
    static let leastSpread: CGFloat = 8

    struct Loop {
        let path: DiagramPath
        let startTip: CGPoint
        let startDirection: CGVector
        let endTip: CGPoint
        let endDirection: CGVector
        let labelCenter: CGPoint
    }

    /// The `loopIndex`-th loop on a node whose flow runs across when `isSideways`, its marks trimming `startTrim` and
    /// `endTrim` of its ends.
    static func loop(of view: ReferenceUseCaseNodeView, center: CGPoint, loopIndex: Int, isSideways: Bool, labelSize: CGSize, startTrim: CGFloat,
                     endTrim: CGFloat) -> Loop {
        let side: DiagramSide = isSideways ? .bottom : .right
        let spread = min(ReferenceUseCaseEdgeEnds.sideLength(of: view, side: side) / 2, leastSpread + CGFloat(loopIndex) * spreadStep)
        let loopReach = reach + CGFloat(loopIndex) * reachStep
        let first = ReferenceUseCaseEdgeEnds.anchor(of: view, center: center, side: side, along: -spread)
        let second = ReferenceUseCaseEdgeEnds.anchor(of: view, center: center, side: side, along: spread)
        let length = max(hypot(loopReach, spread), .leastNonzeroMagnitude)
        let across = isSideways ? spread / length : loopReach / length
        let down = isSideways ? loopReach / length : spread / length
        func outward(_ point: CGPoint, sign: CGFloat) -> CGPoint {
            isSideways ? CGPoint(x: point.x + sign * spread, y: point.y + loopReach) : CGPoint(x: point.x + loopReach, y: point.y + sign * spread)
        }
        let start = isSideways ? CGPoint(x: first.x - across * startTrim, y: first.y + down * startTrim)
            : CGPoint(x: first.x + across * startTrim, y: first.y - down * startTrim)
        let end = CGPoint(x: second.x + across * endTrim, y: second.y + down * endTrim)
        let path = DiagramPath(start: start, segments: [.curve(to: end, control1: outward(first, sign: -1), control2: outward(second, sign: 1))])
        let labelCenter = isSideways
            ? CGPoint(x: center.x, y: max(first.y, second.y) + loopReach * 0.75 + 6 + labelSize.height / 2)
            : CGPoint(x: max(first.x, second.x) + loopReach * 0.75 + 8 + labelSize.width / 2, y: center.y)
        return Loop(path: path, startTip: first, startDirection: CGVector(dx: isSideways ? across : -across, dy: isSideways ? -down : down),
                    endTip: second, endDirection: CGVector(dx: -across, dy: -down), labelCenter: labelCenter)
    }
}
