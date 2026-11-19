/**
 * File: SequenceMessage.swift
 * ---------------------------
 * Layer: Core
 * Description: A sequence diagram's message: its two participants, its arrow (line, head, half heads and their side,
 *              the ends the heads are at), its text, the circles of its central connections, and the participants it
 *              creates or whose lifelines it ends.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */

/// A message from one participant to another, or to itself, drawn as an arrow between their lifelines.
public struct SequenceMessage: Equatable, Sendable {
    /// Index into `SequenceDiagram.participants` of the participant the message is written from.
    public let sourceIndex: Int
    /// Index into `SequenceDiagram.participants` of the participant the message is written to.
    public let targetIndex: Int
    public let arrow: SequenceArrow
    /// The text after the colon, which may be empty.
    public let text: DiagramLabel
    /// Whether the text wraps to the width Mermaid gives it (`wrap:` before it) rather than staying on its lines.
    public let wrapsText: Bool
    /// `()` before the arrow: a circle where the message leaves the source's lifeline, the line starting at it.
    public let hasCentralConnectionAtSource: Bool
    /// `()` after the arrow: a circle where the message meets the target's lifeline, the line ending at it.
    public let hasCentralConnectionAtTarget: Bool
    /// Whether this is the first message after `create participant` names its target: the target's box is drawn at
    /// the end of this message instead of above the first row.
    public internal(set) var createsTarget: Bool
    /// Whether this is the first message after `destroy` names its source (or its target): that participant's lifeline
    /// ends in a cross under this message, and it is not drawn again under the last row.
    public internal(set) var destroysSource: Bool
    public internal(set) var destroysTarget: Bool

    init(sourceIndex: Int, targetIndex: Int, arrow: SequenceArrow, text: DiagramLabel, wrapsText: Bool, hasCentralConnectionAtSource: Bool = false,
         hasCentralConnectionAtTarget: Bool = false, createsTarget: Bool = false, destroysSource: Bool = false, destroysTarget: Bool = false) {
        self.sourceIndex = sourceIndex
        self.targetIndex = targetIndex
        self.arrow = arrow
        self.text = text
        self.wrapsText = wrapsText
        self.hasCentralConnectionAtSource = hasCentralConnectionAtSource
        self.hasCentralConnectionAtTarget = hasCentralConnectionAtTarget
        self.createsTarget = createsTarget
        self.destroysSource = destroysSource
        self.destroysTarget = destroysTarget
    }
}

/// How a message's arrow is drawn: its line, its head, and which ends the head is at.
public struct SequenceArrow: Equatable, Sendable {
    public let stroke: SequenceLineStroke
    public let head: SequenceArrowhead
    /// Whether the head is at both ends (`<<->>`, `<<-->>`) rather than at the target only.
    public let pointsBothWays: Bool
    /// Whether the head is at the source only, the arrow written backwards (`/|-`, `\|-`, `//-`, `\\-` and their
    /// dotted forms).
    public let pointsBackwards: Bool
    /// For a half head, the side of the line its one barb is on; `.top` for the other heads.
    public let halfHeadSide: SequenceHalfHeadSide

    init(stroke: SequenceLineStroke, head: SequenceArrowhead, pointsBothWays: Bool = false, pointsBackwards: Bool = false,
         halfHeadSide: SequenceHalfHeadSide = .top) {
        self.stroke = stroke
        self.head = head
        self.pointsBothWays = pointsBothWays
        self.pointsBackwards = pointsBackwards
        self.halfHeadSide = halfHeadSide
    }

    /// Whether a head is drawn where the message leaves its source.
    var hasHeadAtSource: Bool {
        head != .none && (pointsBothWays || pointsBackwards)
    }

    /// Whether a head is drawn where the message reaches its target.
    var hasHeadAtTarget: Bool {
        head != .none && !pointsBackwards
    }

    /// Whether the message's tail, where its number goes, is at the target: an arrow written backwards.
    var isTailAtTarget: Bool {
        pointsBackwards
    }
}

/// How a message's line is drawn.
public enum SequenceLineStroke: Equatable, Sendable, CaseIterable {
    /// `-`: a solid line.
    case solid
    /// `--`: a dashed line, an answer by convention.
    case dotted
}

/// The mark at the end of a message's line.
public enum SequenceArrowhead: Equatable, Sendable, CaseIterable {
    /// `->`, `-->`: a line without a head.
    case none
    /// `->>`, `-->>`: a filled arrowhead.
    case arrow
    /// `-x`, `--x`: a cross, a message that is lost or refused.
    case cross
    /// `-)`, `--)`: an open arrowhead, an asynchronous message.
    case open
    /// `-|\`, `-|/` (and `/|-`, `\|-` backwards): the filled half of an arrowhead, on one side of the line.
    case solidHalf
    /// `-\\`, `-//` (and `//-`, `\\-` backwards): one barb of an open arrowhead, on one side of the line.
    case stickHalf
}

/// The side of a message's line a half head is on, as Mermaid names it: seen along the message, the top is to its left,
/// so above the line of a message to the right and below the line of one to the left.
public enum SequenceHalfHeadSide: Equatable, Sendable, CaseIterable {
    /// `-|\`, `-\\`, `/|-`, `//-`.
    case top
    /// `-|/`, `-//`, `\|-`, `\\-`.
    case bottom
}
