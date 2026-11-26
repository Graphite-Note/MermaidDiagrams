/**
 * File: StateDiagramModel.swift
 * -----------------------------
 * Layer: Core
 * Description: A state diagram as flat records over its text: each state, transition and note a few numbers, each
 *              identifier and text a range of the source or, when it had to be decoded or written, an index into the
 *              model's labels and identifiers, kept behind one reference once read; the public states, transitions
 *              and notes made from them when asked.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

/// A text written for a state, a transition or a note: a range of the diagram's text that the label decoder reads
/// without markup (one line, trimmed, as written), or a label decoded when it was read (markup, a written `\n`, a text
/// beyond ASCII, or one made by a caller).
struct StateDiagramText: Equatable, Sendable {
    let start: Int32
    let end: Int32
    /// Index into `StateDiagramModel.labels`, `sourceRange` for a range of the text, or `absent`.
    let labelIndex: Int32

    static let sourceRange: Int32 = -1
    static let absent: Int32 = -2
    static let none = StateDiagramText(start: 0, end: 0, labelIndex: absent)

    init(start: Int32, end: Int32, labelIndex: Int32) {
        self.start = start
        self.end = end
        self.labelIndex = labelIndex
    }

    init(range: MermaidTextRange) {
        self.init(start: range.start, end: range.end, labelIndex: Self.sourceRange)
    }

    var isNone: Bool { labelIndex == Self.absent }
    var isSourceRange: Bool { labelIndex == Self.sourceRange }
    var range: MermaidTextRange { MermaidTextRange(start: Int(start), end: Int(end)) }
}

/// A state: its identifier, a range of the text or an index into the model's identifiers; its kind; where it was last
/// named; and its descriptions, a run of the model's descriptions.
struct StateDiagramStateRecord: Equatable, Sendable {
    var identifierStart: Int32
    var identifierEnd: Int32
    /// Index into `StateDiagramModel.identifiers` for an identifier not in the text (one trimmed as Foundation trims it
    /// beyond ASCII, or made by a caller), `startOrEndIdentifier` for `[*]`, -1 for a range of the text.
    var writtenIdentifierIndex: Int32
    var kind: StateDiagramStateKind
    /// Index into the composites of the one it was last named inside, -1 for none.
    var composite: Int32 = -1
    var region: Int32 = 0
    var firstDescription: Int32 = 0
    var descriptionCount: Int32 = 0

    /// `writtenIdentifierIndex` of a start or an end, whose identifier is `[*]`.
    static let startOrEndIdentifier: Int32 = -2

    var descriptionIndices: Range<Int> { Int(firstDescription)..<Int(firstDescription + descriptionCount) }
    /// Whether the identifier is a range of the text.
    var isIdentifierInText: Bool { writtenIdentifierIndex == -1 }
    var compositeIndex: Int? { composite < 0 ? nil : Int(composite) }
    var regionIndex: Int { Int(region) }
}

struct StateDiagramTransitionRecord: Equatable, Sendable {
    let source: Int32
    let target: Int32
    /// `StateDiagramText.none` when the transition has no text.
    let label: StateDiagramText

    var sourceIndex: Int { Int(source) }
    var targetIndex: Int { Int(target) }
}

struct StateDiagramNoteRecord: Equatable, Sendable {
    let state: Int32
    let side: StateDiagramNoteSide
    let text: StateDiagramText

    var stateIndex: Int { Int(state) }
}

/// The records of a state diagram over its text, which they index, as the reader writes them.
struct StateDiagramRecords: Sendable {
    var text: MermaidSourceText
    var states: [StateDiagramStateRecord] = []
    /// Every state's descriptions, each state's in a run in the order written.
    var descriptions: [StateDiagramText] = []
    var transitions: [StateDiagramTransitionRecord] = []
    var notes: [StateDiagramNoteRecord] = []
    /// The texts decoded when they were read, which `StateDiagramText.labelIndex` indexes.
    var labels: [DiagramLabel] = []
    /// The identifiers not in the text, which `StateDiagramStateRecord.writtenIdentifierIndex` indexes.
    var identifiers: [String] = []

    init(text: MermaidSourceText) {
        self.text = text
    }

    /// A model of states, transitions and notes made by a caller: every identifier written and every text a label.
    init(states: [StateDiagramState], transitions: [StateDiagramTransition], notes: [StateDiagramNote]) {
        text = MermaidSourceText(bytes: [])
        self.states.reserveCapacity(states.count)
        for state in states {
            let record = StateDiagramStateRecord(identifierStart: 0, identifierEnd: 0, writtenIdentifierIndex: Int32(identifiers.count), kind: state.kind,
                                                 composite: state.compositeIndex.map(Int32.init) ?? -1, region: Int32(state.regionIndex),
                                                 firstDescription: Int32(descriptions.count), descriptionCount: Int32(state.descriptions.count))
            identifiers.append(state.identifier)
            for description in state.descriptions { descriptions.append(written(description)) }
            self.states.append(record)
        }
        self.transitions = transitions.map { transition in
            StateDiagramTransitionRecord(source: Int32(transition.sourceIndex), target: Int32(transition.targetIndex),
                                         label: transition.label.map { label in written(label) } ?? .none)
        }
        self.notes = notes.map { note in StateDiagramNoteRecord(state: Int32(note.stateIndex), side: note.side, text: written(note.text)) }
    }

    /// `label` kept among the labels.
    mutating func written(_ label: DiagramLabel) -> StateDiagramText {
        labels.append(label)
        return StateDiagramText(start: 0, end: 0, labelIndex: Int32(labels.count - 1))
    }

}

/// The records of a state diagram once read, behind one reference, so that a diagram, a layout or a measuring that
/// holds them retains one object rather than each of their lists; none changes once made.
final class StateDiagramModel: Sendable {
    let text: MermaidSourceText
    let states: [StateDiagramStateRecord]
    let descriptions: [StateDiagramText]
    let transitions: [StateDiagramTransitionRecord]
    let notes: [StateDiagramNoteRecord]
    let labels: [DiagramLabel]
    let identifiers: [String]

    init(_ records: consuming StateDiagramRecords) {
        text = records.text
        states = records.states
        descriptions = records.descriptions
        transitions = records.transitions
        notes = records.notes
        labels = records.labels
        identifiers = records.identifiers
    }

    /// The identifier of `state` as written.
    func identifier(of state: Int) -> String {
        let record = states[state]
        if record.writtenIdentifierIndex >= 0 { return identifiers[Int(record.writtenIdentifierIndex)] }
        if record.writtenIdentifierIndex == StateDiagramStateRecord.startOrEndIdentifier { return "[*]" }
        return text.string(MermaidTextRange(start: Int(record.identifierStart), end: Int(record.identifierEnd)))
    }

    /// `text` as the label 0.7.0 read: decoded from its range, which reads it as one line trimmed, or the label kept.
    func label(_ text: StateDiagramText) -> DiagramLabel {
        guard text.isSourceRange else { return labels[Int(text.labelIndex)] }
        return self.text.withBytes { bytes in
            DiagramLabelDecoder.label(fromUTF8: UnsafeBufferPointer(rebasing: bytes[Int(text.start)..<Int(text.end)]), form: .plain)
        }
    }

    /// The label `StateDiagramState.name` gives `state`: its first description, else its identifier.
    func nameLabel(of state: Int) -> DiagramLabel {
        let record = states[state]
        return record.descriptionCount > 0 ? label(descriptions[Int(record.firstDescription)]) : DiagramLabel(identifier(of: state))
    }

    /// The public state at `index`.
    func state(at index: Int) -> StateDiagramState {
        let record = states[index]
        return StateDiagramState(identifier: identifier(of: index), kind: record.kind, descriptions: record.descriptionIndices.map { label(descriptions[$0]) },
                                 compositeIndex: record.compositeIndex, regionIndex: record.regionIndex)
    }

    func transition(at index: Int) -> StateDiagramTransition {
        let record = transitions[index]
        return StateDiagramTransition(sourceIndex: Int(record.source), targetIndex: Int(record.target),
                                      label: record.label.isNone ? nil : label(record.label))
    }

    func note(at index: Int) -> StateDiagramNote {
        let record = notes[index]
        return StateDiagramNote(stateIndex: Int(record.state), side: record.side, text: label(record.text))
    }
}
