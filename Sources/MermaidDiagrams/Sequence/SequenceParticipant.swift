/**
 * File: SequenceParticipant.swift
 * -------------------------------
 * Layer: Core
 * Description: A sequence diagram's participant: its identifier, its text, the shape it is drawn as and the box it is
 *              grouped in.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */

/// A participant of a sequence diagram: the identifier messages name it by, the text drawn for it and how it is drawn.
public struct SequenceParticipant: Equatable, Sendable {
    public let identifier: String
    /// The text drawn for the participant: its alias (`participant A as Alice`, or `alias` in its attributes), else its
    /// identifier.
    public internal(set) var label: DiagramLabel
    public internal(set) var kind: SequenceParticipantKind
    /// Index into `SequenceDiagram.boxes` of the `box` the participant is declared in, or nil.
    public internal(set) var boxIndex: Int?

    init(identifier: String, label: DiagramLabel, kind: SequenceParticipantKind = .participant, boxIndex: Int? = nil) {
        self.identifier = identifier
        self.label = label
        self.kind = kind
        self.boxIndex = boxIndex
    }
}

/// How a participant is drawn at the top and the bottom of its lifeline: by its keyword (`participant`, `actor`), or by
/// the `type` its attributes give it (`participant A@{ "type": "database" }`), Pele's shapes.
public enum SequenceParticipantKind: Equatable, Sendable, CaseIterable {
    /// `participant`, a participant only named by a message or a note, and any type not listed here: a box around its
    /// text.
    case participant
    /// `actor`: a stick figure above its text.
    case actor
    /// A boundary: a circle with a vertical line joined to its left, above the text.
    case boundary
    /// A control: a circle with an arrowhead on its top, above the text.
    case control
    /// An entity: a circle on a line, above the text.
    case entity
    /// A database: a cylinder above the text.
    case database
    /// Collections: two boxes, one behind the other, around the text.
    case collections
    /// A queue: a cylinder lying on its side around the text.
    case queue

    /// The kind an attribute's `type` names, Mermaid's spelling; any other text is a plain participant, as in Pele.
    init(attributeType: String) {
        self = switch attributeType {
        case "actor": .actor
        case "boundary": .boundary
        case "control": .control
        case "entity": .entity
        case "database": .database
        case "collections": .collections
        case "queue": .queue
        default: .participant
        }
    }

    /// Whether the participant is a figure standing above its text, rather than a shape holding it.
    public var isFigure: Bool {
        switch self {
        case .actor, .boundary, .control, .entity, .database: true
        case .participant, .collections, .queue: false
        }
    }
}
