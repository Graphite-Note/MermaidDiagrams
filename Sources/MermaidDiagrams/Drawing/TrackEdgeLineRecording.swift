/**
 * File: TrackEdgeLineRecording.swift
 * ----------------------------------
 * Layer: Core
 * Description: Adds an edge's line to a group of lines as adding it through a path of its own does, recorded straight
 *              into a lane when that gives the same elements: for the sequence diagram's messages and the event model's
 *              relations, and the railroad's, timeline's and journey column's connecting lines.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

extension DiagramPathMaking {
    /// `addEdgeLine(_:to:)`, the line recorded straight into `path` when it is a lane that does not end with a move:
    /// adding a path through `addPath` copies its elements as they are, and recording them gives the same ones but where
    /// the lane ends with a move, which a move recorded after it takes the place of. A Core Graphics path takes the line
    /// through a path of its own, as before.
    func addEdgeLineInPlace(_ line: DiagramPath, to path: Path) {
        if let lane = path as? DiagramPathLane, lane.state.pointee.lastVerb != .move {
            return DiagramEdgeDrawing.record(line, into: lane)
        }
        addEdgeLine(line, to: path)
    }
}
