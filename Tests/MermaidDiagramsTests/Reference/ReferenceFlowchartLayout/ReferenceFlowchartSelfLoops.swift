/**
 * File: ReferenceFlowchartSelfLoops.swift
 * ---------------------------------------
 * Layer: Tests
 * Description: The 0.7.0 FlowchartSelfLoops kept as the reference the 0.8.0 flowchart layout is checked against: edges
 *              from a flowchart's, a swimlane's or an agent flow's node to itself, looped beside it as Pele's loopPath
 *              draws them, and the room they take in the node's place.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// Edges from a node to itself, as Pele's `loopPath` (`svg/edges.ts`) draws them for its flowchart renderer (flowcharts,
/// swimlanes) and its agent flow renderer: each loops out of the side across the flow (the right in a flow that runs down
/// or up, the bottom in one that runs across) and back, leaving 8 points from the side's middle (at most 4 points inside
/// the side's ends) and reaching 26 points out, the next one 6 points wider and 8 farther, its text beyond it. The
/// node's place in its rank grows on both sides by the room each loop takes, so that it stays centered. A group's node has
/// no size, so a group's loop starts at its box's middle, its two ends 4 points apart the other way, as Pele's does.
enum ReferenceFlowchartSelfLoops {
    /// How far the first loop reaches beyond the node, and how much farther each next one.
    static let loopReach: CGFloat = 26
    static let reachStep: CGFloat = 8
    /// How far from the side's middle the first loop leaves and comes back, how much farther each next one, and how far
    /// inside the side's ends it stays.
    static let firstSpread: CGFloat = 8
    static let spreadStep: CGFloat = 6
    static let spreadClearance: CGFloat = 4
    /// Between a loop's reach and its text's room.
    static let textGap: CGFloat = 4
    /// The room a loop keeps for its text beyond the text, across the flow (as its place in the layout) and along it.
    static let textRoomAcross: CGFloat = 12
    static let textRoomAlong: CGFloat = 8
    /// The room of an edge's text beyond its lines along the flow, as Pele's `labelH` holds it.
    static let textPlaceAlong: CGFloat = 4

    /// The room beside its node, on each side across the flow, that one loop with text of `textSize` takes.
    static func room(textSize: CGSize?, flowRunsAcross: Bool) -> CGFloat {
        loopReach + (textSize.map { size in flowRunsAcross ? size.height + textRoomAlong : size.width + textRoomAcross } ?? 0)
    }

    /// The room beside its node, on each side across the flow, that loops with texts of `textSizes` take.
    static func room(textSizes: [CGSize?], flowRunsAcross: Bool) -> CGFloat {
        textSizes.reduce(0) { room, textSize in room + Self.room(textSize: textSize, flowRunsAcross: flowRunsAcross) }
    }

    /// One loop: its path, where it leaves the node and the way into the node there, where it comes back and the way it
    /// arrives, and its text's center.
    struct Loop {
        let path: DiagramPath
        let leave: CGPoint
        let intoNodeAtLeave: CGVector
        let back: CGPoint
        let arriving: CGVector
        let textCenter: CGPoint
    }

    /// The `loopIndex`-th loop of a node drawn at `center` in `shapeSize`; its end stops `endTrim` short of the node for a
    /// mark, along the way it arrives.
    static func loop(center: CGPoint, shapeSize: CGSize, loopIndex: Int, flowRunsAcross: Bool, endTrim: CGFloat, textSize: CGSize?) -> Loop {
        let half = (flowRunsAcross ? shapeSize.width : shapeSize.height) / 2
        let spread = min(half - spreadClearance, firstSpread + CGFloat(loopIndex) * spreadStep)
        let reach = loopReach + CGFloat(loopIndex) * reachStep
        let length = max((reach * reach + spread * spread).squareRoot(), 1)
        // `outward` away from the node through the side, `along` the side.
        func point(outward: CGFloat, along: CGFloat) -> CGPoint {
            flowRunsAcross ? CGPoint(x: center.x + along, y: center.y + shapeSize.height / 2 + outward)
                           : CGPoint(x: center.x + shapeSize.width / 2 + outward, y: center.y + along)
        }
        let path = DiagramPath(start: point(outward: 0, along: -spread), segments: [
            .curve(to: point(outward: reach / length * endTrim, along: spread + spread / length * endTrim),
                   control1: point(outward: reach, along: -2 * spread), control2: point(outward: reach, along: 2 * spread)),
        ])
        let textCenter = flowRunsAcross
            ? point(outward: reach + textGap + ((textSize?.height ?? 0) + textPlaceAlong) / 2, along: 0)
            : point(outward: reach + textGap + ((textSize?.width ?? 0) + textRoomAcross) / 2, along: 0)
        return Loop(path: path, leave: point(outward: 0, along: -spread),
                    intoNodeAtLeave: flowRunsAcross ? CGVector(dx: 0, dy: -1) : CGVector(dx: -1, dy: 0),
                    back: point(outward: 0, along: spread),
                    arriving: flowRunsAcross ? CGVector(dx: -spread / length, dy: -reach / length) : CGVector(dx: -reach / length, dy: -spread / length),
                    textCenter: textCenter)
    }
}
