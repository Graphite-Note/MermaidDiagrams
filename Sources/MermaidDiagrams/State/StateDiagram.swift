/**
 * File: StateDiagram.swift
 * ------------------------
 * Layer: Core
 * Description: A Mermaid state diagram as its text describes it, a façade over the flat records the reader writes
 *              (`StateDiagramModel`): its states, transitions and notes made from them when asked.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.2
 * Date: 26/11/2026
 */

/// A Mermaid state diagram (`stateDiagram` or `stateDiagram-v2`) as its text describes it: the states in the order
/// they are first named, the transitions between them and the notes beside them in the order they are written, and
/// the composite states read but not drawn.
public struct StateDiagram: Equatable, Sendable {
    /// The way the top level runs: its last `direction` statement, top to bottom when it has none. A state diagram
    /// takes the same four directions as a flowchart.
    public internal(set) var direction: FlowchartDirection
    /// The states, transitions and notes as records over the diagram's text, which the layout reads.
    let model: StateDiagramModel
    /// The states written with a body (`state Id { … }`), in the order their bodies open.
    public internal(set) var composites: [StateDiagramComposite]
    /// The diagram's title, from `title:` in the front matter, or nil.
    public internal(set) var title: String?
    /// `accTitle: …`, the short name a screen reader gives the diagram, or nil.
    public internal(set) var accessibilityTitle: String?
    /// `accDescr: …` or `accDescr { … }`, the longer description a screen reader reads, or nil.
    public internal(set) var accessibilityDescription: String?
    /// Statements that change only how the diagram looks (`classDef`, `class`, `:::`, `style`) or what a click does
    /// (`click`). They are read and not applied yet.
    public internal(set) var unappliedStatementCount: Int

    init(direction: FlowchartDirection = .topToBottom, states: [StateDiagramState] = [], transitions: [StateDiagramTransition] = [],
         notes: [StateDiagramNote] = [], composites: [StateDiagramComposite] = [], title: String? = nil, accessibilityTitle: String? = nil,
         accessibilityDescription: String? = nil, unappliedStatementCount: Int = 0) {
        self.init(direction: direction, model: StateDiagramModel(StateDiagramRecords(states: states, transitions: transitions, notes: notes)),
                  composites: composites,
                  title: title, accessibilityTitle: accessibilityTitle, accessibilityDescription: accessibilityDescription,
                  unappliedStatementCount: unappliedStatementCount)
    }

    init(direction: FlowchartDirection, model: StateDiagramModel, composites: [StateDiagramComposite], title: String? = nil,
         accessibilityTitle: String? = nil, accessibilityDescription: String? = nil, unappliedStatementCount: Int = 0) {
        self.direction = direction
        self.model = model
        self.composites = composites
        self.title = title
        self.accessibilityTitle = accessibilityTitle
        self.accessibilityDescription = accessibilityDescription
        self.unappliedStatementCount = unappliedStatementCount
    }

    /// The states in the order they are first named, made from the records: `state(at:)` makes one.
    public var states: [StateDiagramState] { (0..<stateCount).map(model.state(at:)) }
    /// The transitions in the order they are written.
    public var transitions: [StateDiagramTransition] { (0..<transitionCount).map(model.transition(at:)) }
    /// The notes in the order they are written.
    public var notes: [StateDiagramNote] { (0..<noteCount).map(model.note(at:)) }

    public var stateCount: Int { model.states.count }
    public var transitionCount: Int { model.transitions.count }
    public var noteCount: Int { model.notes.count }

    public func state(at index: Int) -> StateDiagramState { model.state(at: index) }
    public func transition(at index: Int) -> StateDiagramTransition { model.transition(at: index) }
    public func note(at index: Int) -> StateDiagramNote { model.note(at: index) }

    public static func == (left: StateDiagram, right: StateDiagram) -> Bool {
        left.direction == right.direction && left.composites == right.composites && left.title == right.title
            && left.accessibilityTitle == right.accessibilityTitle && left.accessibilityDescription == right.accessibilityDescription
            && left.unappliedStatementCount == right.unappliedStatementCount && left.stateCount == right.stateCount
            && left.transitionCount == right.transitionCount && left.noteCount == right.noteCount
            && left.states == right.states && left.transitions == right.transitions && left.notes == right.notes
    }
}
