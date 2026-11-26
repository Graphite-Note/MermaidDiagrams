/**
 * File: RequirementSelfLoops.swift
 * --------------------------------
 * Layer: Core
 * Description: Relations from a requirement or an element to itself, looped beside its box as Pele's requirement
 *              renderer draws them.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 26/11/2026
 */

import CoreGraphics

/// Relations from a box to itself, as Pele draws them: each loops out of the box's side across the flow (its right in a
/// flow that runs down or up, its bottom in one that runs across) and back, the next one reaching 8 points farther and
/// leaving 6 points farther from the side's middle, its text beyond it. The box's place in its rank grows on both sides
/// by the room each loop takes, so that it stays centered.
enum RequirementSelfLoops {
    /// How far the first loop reaches beyond the box, and how much farther each next one.
    static let loopReach: CGFloat = 26
    static let reachStep: CGFloat = 8
    /// How far from the side's middle the first loop leaves and comes back, how much farther each next one, and how far
    /// inside the side's ends it stays.
    static let firstSpread: CGFloat = 12
    static let spreadStep: CGFloat = 6
    static let spreadClearance: CGFloat = 4
    /// A cubic whose control points are `reach / 0.75` out peaks at `reach`.
    static let controlReachRatio: CGFloat = 0.75
    /// Between a loop's reach and its text's room.
    static let textGap: CGFloat = 4
    /// The room a loop keeps beyond its text, across and along the flow.
    static let textRoomAcross: CGFloat = 12
    static let textRoomAlong: CGFloat = 8

    /// The room beside its box that one loop with text of `textSize` takes, on each side across the flow.
    static func room(textSize: CGSize, flowIsVertical: Bool) -> CGFloat {
        loopReach + (flowIsVertical ? textSize.width + textRoomAcross : textSize.height + textRoomAlong)
    }

    /// One loop: its path's start and its one curve, where it leaves the box and the way into the box there, where it
    /// comes back, and its text's center.
    struct Loop {
        let start: CGPoint
        let curve: DiagramPathSegment
        let leave: CGPoint
        let back: CGPoint
        /// The way into the box, at both ends.
        let intoBox: CGVector
        let textCenter: CGPoint
    }

    /// The `loopIndex`-th loop of a box drawn at `center` in `boxSize`; `startTrim` keeps its start off the box for a mark.
    static func loop(center: CGPoint, boxSize: CGSize, loopIndex: Int, flowIsVertical: Bool, startTrim: CGFloat, textSize: CGSize) -> Loop {
        let half = (flowIsVertical ? boxSize.height : boxSize.width) / 2
        let spread = min(half - spreadClearance, firstSpread + CGFloat(loopIndex) * spreadStep)
        let reach = loopReach + CGFloat(loopIndex) * reachStep
        // `outward` away from the box through the side, `along` the side.
        func point(outward: CGFloat, along: CGFloat) -> CGPoint {
            flowIsVertical ? CGPoint(x: center.x + boxSize.width / 2 + outward, y: center.y + along)
                           : CGPoint(x: center.x + along, y: center.y + boxSize.height / 2 + outward)
        }
        let pull = reach / controlReachRatio
        let curve = DiagramPathSegment.curve(to: point(outward: 0, along: spread), control1: point(outward: pull, along: -spread),
                                             control2: point(outward: pull, along: spread))
        let textCenter = flowIsVertical
            ? point(outward: reach + textGap + (textSize.width + textRoomAcross) / 2, along: 0)
            : point(outward: reach + textGap + (textSize.height + RequirementMeasurement.edgeTextRoom.height) / 2, along: 0)
        return Loop(start: point(outward: startTrim, along: -spread), curve: curve, leave: point(outward: 0, along: -spread), back: point(outward: 0, along: spread),
                    intoBox: flowIsVertical ? CGVector(dx: -1, dy: 0) : CGVector(dx: 0, dy: -1), textCenter: textCenter)
    }
}
