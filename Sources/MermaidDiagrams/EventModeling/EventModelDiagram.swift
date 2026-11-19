/**
 * File: EventModelDiagram.swift
 * -----------------------------
 * Layer: Core
 * Description: A Mermaid event model (`eventmodeling`) as Mermaid's database holds it: its time frames in their lanes,
 *              the relations between frames, notes and given, when and then specifications.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// A Mermaid event model as its text describes it, once Mermaid's database has built it: the frames in the order they
/// are written (time runs from the first to the last), the lanes they fall in from top to bottom, the relations that
/// feed one frame from another, and the notes and specifications written about frames.
public struct EventModelDiagram: Equatable, Sendable {
    /// `title …` after a frame or the keyword on its line, else `title:` in the front matter, else nil.
    public internal(set) var title: String?
    /// `accTitle: …`, or nil.
    public internal(set) var accessibilityTitle: String?
    /// `accDescr: …` or `accDescr { … }`, or nil.
    public internal(set) var accessibilityDescription: String?
    /// The time frames (`tf`) and reset frames (`rf`), in the order they are written.
    public internal(set) var frames: [EventModelFrame]
    /// One lane per group of kinds, and one more per namespace within a group, sorted from top to bottom.
    public internal(set) var lanes: [EventModelLane]
    /// Which frame feeds which, in the order Mermaid's database makes them.
    public internal(set) var relations: [EventModelRelation]
    public internal(set) var notes: [EventModelNote]
    public internal(set) var specifications: [EventModelSpecification]
    /// The names `entity` declares, in the order they are written; they are not drawn.
    public internal(set) var entities: [String]

    init(title: String? = nil, accessibilityTitle: String? = nil, accessibilityDescription: String? = nil, frames: [EventModelFrame] = [],
         lanes: [EventModelLane] = [], relations: [EventModelRelation] = [], notes: [EventModelNote] = [],
         specifications: [EventModelSpecification] = [], entities: [String] = []) {
        self.title = title
        self.accessibilityTitle = accessibilityTitle
        self.accessibilityDescription = accessibilityDescription
        self.frames = frames
        self.lanes = lanes
        self.relations = relations
        self.notes = notes
        self.specifications = specifications
        self.entities = entities
    }
}

/// What a frame shows: `ui`, `pcr` or `processor`, `cmd` or `command`, `rmo` or `readmodel`, `evt` or `event`.
public enum EventModelEntityKind: String, Equatable, Sendable, CaseIterable {
    case userInterface = "ui"
    case processor
    case command
    case readModel = "readmodel"
    case event

    /// The kind a frame's keyword names; any other word is an event, as in Mermaid's database.
    init(keyword: String) {
        switch keyword {
        case "ui": self = .userInterface
        case "pcr", "processor": self = .processor
        case "cmd", "command": self = .command
        case "rmo", "readmodel": self = .readModel
        default: self = .event
        }
    }

    /// The lanes' group the kind falls in: the trigger (a user interface or an automation), the state (a command or a
    /// read model), or the stream (an event).
    public var laneGroup: EventModelLaneGroup {
        switch self {
        case .userInterface, .processor: .trigger
        case .command, .readModel: .state
        case .event: .stream
        }
    }

    /// Whether Mermaid's event modeling language lets a frame of this kind take its input from one of `source`: a
    /// command from a user interface or a processor, an event from a command, a read model from an event, a processor
    /// or a user interface from a read model. Mermaid states these rules in its validator but never applies them while it
    /// reads a diagram, so a diagram that breaks them is drawn, there and here.
    public func acceptsInput(from source: EventModelEntityKind) -> Bool {
        switch self {
        case .command: source == .userInterface || source == .processor
        case .event: source == .command
        case .readModel: source == .event
        case .processor, .userInterface: source == .readModel
        }
    }
}

/// Where the lanes of a group of kinds sit, from the top: the trigger, the state, the stream.
public enum EventModelLaneGroup: Equatable, Sendable {
    case trigger
    case state
    case stream
}

/// A horizontal lane of frames.
public struct EventModelLane: Equatable, Sendable {
    /// Mermaid's ordering key: 0 for the user interfaces and automations, 100 for the commands and read models, 200 for
    /// the events, and the next free number after its group's for each namespace.
    public let orderKey: Int
    /// `UI/Automation`, `Command/Read Model` or `Events`, or for a namespace `UI/A: `, `C/RM: ` or `Stream: ` and its name.
    public let label: String
    public let group: EventModelLaneGroup
    public let namespace: String?
}

/// A time frame of an event model: what happens at one step of the timeline.
public struct EventModelFrame: Equatable, Sendable {
    /// The frame's number as written (`01`).
    public let identifier: String
    public let kind: EventModelEntityKind
    /// The entity as written, with its namespace (`Inventory.AddItem`).
    public let entity: String
    /// The entity without its namespace: the part after the dot of a name of two parts, else the whole name.
    public let name: String
    /// The part before the dot of a name of two parts, or nil.
    public let namespace: String?
    /// Whether it is a reset frame (`rf`), which no earlier frame feeds unless it names its sources.
    public let isReset: Bool
    /// The index of its lane in `EventModelDiagram.lanes`.
    public let laneIndex: Int
    /// The example data written in braces or quotes after it, or of the data block it names (`[[Data]]`), without the
    /// braces and the indentation its lines share; nil when it has none.
    public let data: String?
    /// The data's type between backticks (`json`, `md` …), or nil.
    public let dataType: String?
}

/// One frame feeding another, by their indices in `EventModelDiagram.frames`.
public struct EventModelRelation: Equatable, Sendable {
    public let sourceFrameIndex: Int
    public let targetFrameIndex: Int
}

/// A note written about a frame (`note 01 { … }`).
public struct EventModelNote: Equatable, Sendable {
    /// The number of the frame it is about, as written; it need not name a frame.
    public let frameIdentifier: String
    /// The note's text, without the braces and the indentation its lines share.
    public let text: String
    public let dataType: String?
}

/// A given, when and then specification of a frame (`gwt 01 given evt A when cmd B then evt C`).
public struct EventModelSpecification: Equatable, Sendable {
    public let frameIdentifier: String
    /// The entities named after `given`, `when` (none when it has no `when`) and `then`, in their order.
    public let given: [String]
    public let when: [String]
    public let then: [String]
}

extension EventModelDiagram: TitledMermaidDiagram {}
