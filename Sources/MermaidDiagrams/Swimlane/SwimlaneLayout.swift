/**
 * File: SwimlaneLayout.swift
 * --------------------------
 * Layer: Core
 * Description: A swimlane diagram laid out on a page: the flowchart inside its lanes, and the lanes with their title bands.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// A swimlane diagram (`swimlane-beta`) laid out on a page whose origin is the top left corner and whose y runs down: a
/// flowchart whose top-level groups are lanes. The flowchart's nodes, edges, title and the groups inside lanes are drawn as
/// a flowchart's (`flowchart`, its `clusters` the groups inside lanes); the lanes are drawn behind them.
public struct SwimlaneLayout: Equatable, Sendable {
    public let flowchart: FlowchartLayout
    /// The lanes across the flow in the order they are written, a lane for the nodes outside every group first.
    public let lanes: [SwimlaneLayoutLane]

    public var size: CGSize { flowchart.size }
}

/// A lane: an outline the length of the diagram, with its title in a filled band at its start along the flow.
public struct SwimlaneLayoutLane: Equatable, Sendable {
    public let frame: CGRect
    /// The band at the lane's start: along its top in a flow that runs down or up, along its left in one that runs across.
    public let titleBand: CGRect
    /// The title, centered in the band, or nil for the lane of the nodes outside every group.
    public let title: DiagramTextBlock?
    /// Whether the title is drawn turned a quarter turn counterclockwise, as in a flow that runs across.
    public let isTitleTurned: Bool
}

extension SwimlaneLayoutLane {
    func translated(by offset: CGVector) -> SwimlaneLayoutLane {
        SwimlaneLayoutLane(frame: frame.offsetBy(dx: offset.dx, dy: offset.dy), titleBand: titleBand.offsetBy(dx: offset.dx, dy: offset.dy),
                           title: title?.translated(by: offset), isTitleTurned: isTitleTurned)
    }
}
