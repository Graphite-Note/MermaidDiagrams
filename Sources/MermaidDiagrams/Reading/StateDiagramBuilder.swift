/**
 * File: StateDiagramBuilder.swift
 * -------------------------------
 * Layer: Core
 * Description: Collects a state diagram as its statements are read on the text's bytes, as records over the text:
 *              states by their interned names, one start and one end per scope, transitions and notes within the
 *              limits, texts as ranges where the decoder reads them as written, and the composite bodies open at each
 *              point.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.3
 * Date: 26/11/2026
 */

/// Collects a state diagram as its statements are read: states by identifier, one start and one end per scope (the
/// top level, or a region of a composite's body), transitions and notes within the limits, and the composite bodies
/// open at each point, which take the states named inside them.
struct StateDiagramBuilder {
    private(set) var model: StateDiagramRecords
    private var direction = FlowchartDirection.topToBottom
    private var composites: [StateDiagramComposite] = []
    private var accessibilityTitle: String?
    private var accessibilityDescription: String?
    private var unappliedStatementCount = 0
    private let limits: MermaidDiagramLimits
    /// The thread's working lists, given back when the reading ends: the names read, interned (`names`); the state each
    /// names by its number (`indexByName`); the composite of each state that has a body, by the state's index, -1 for
    /// none (`firstNumbers`); the state each description in `model.descriptions` is written for, in the order written,
    /// which `finished` puts in a run a state (`secondNumbers`).
    private var lists = GraphDiagramReadingLists()
    /// The `[*]` states by their scope (`scopeKey`): a few in a list, searched in order, and past them a dictionary.
    private var startOrEndScopes: [(key: UInt64, index: Int)] = []
    private var startOrEndIndexByScope: [UInt64: Int] = [:]
    /// The composite bodies open now, outermost first, with the region being read in each.
    private var openBodies: [OpenBody] = []

    private struct OpenBody {
        let compositeIndex: Int
        var regionIndex: Int
    }

    /// - Parameters:
    ///   - text: The text the statements are read from, which the records index.
    ///   - byteCount: The length of the text, which bounds what it can name: room is made for a state and a transition
    ///     every `bytesPerStatement` bytes, within the limits, so that most diagrams grow no list.
    ///   - lists: The thread's working lists, emptied for this text, which the builder holds until `finished` gives them back.
    init(text: MermaidSourceText, limits: MermaidDiagramLimits, byteCount: Int, lists: inout GraphDiagramReadingLists) {
        model = StateDiagramRecords(text: text)
        self.limits = limits
        swap(&self.lists, &lists)
        let statementCount = min(byteCount / Self.bytesPerStatement + 4, limits.maximumNodeCount, Self.mostReserved)
        self.lists.names.reserveCapacity(statementCount)
        self.lists.indexByName.reserveCapacity(statementCount)
        self.lists.firstNumbers.reserveCapacity(statementCount)
        model.states.reserveCapacity(statementCount)
        model.transitions.reserveCapacity(min(byteCount / Self.bytesPerStatement + 4, limits.maximumEdgeCount, Self.mostReserved))
    }

    /// About the bytes a short statement takes (`  A --> B`).
    private static let bytesPerStatement = 12
    /// The most of each list made room for at once; a longer text's lists grow.
    private static let mostReserved = 4_096

    /// Where a `[*]` is: the composite body and region it is written in (none at the top level), and whether it starts
    /// or ends the scope, as one key.
    private func scopeKey(isStart: Bool) -> UInt64 {
        guard let innermost = openBodies.last else { return isStart ? 1 : 0 }
        return (UInt64(innermost.compositeIndex + 1) << 33) | (UInt64(innermost.regionIndex) << 1) | (isStart ? 1 : 0)
    }

    /// The index of the state a reference names. `[*]` is the start of the scope it is written in when `isFirst`
    /// (it leaves a transition, or stands alone), else its end. A state is added the first time it is named, as a
    /// box or with `kind`; naming it again keeps the kind it was first given, as Mermaid does.
    mutating func stateIndex(for reference: StateDiagramStateReference, in bytes: GraphDiagramBytes, isFirst: Bool,
                             kind: StateDiagramStateKind = .state) throws(MermaidDiagramReadError) -> Int {
        let index: Int
        switch reference {
        case .named(let range):
            let (number, isNew) = lists.names.intern(bytes.buffer, range)
            index = isNew ? try addNamedState(StateDiagramStateRecord(identifierStart: range.start, identifierEnd: range.end, writtenIdentifierIndex: -1,
                                                                      kind: kind)) : Int(lists.indexByName[number])
        case .written(let identifier):
            let (number, isNew) = lists.names.intern(identifier)
            index = isNew ? try addNamedState(writtenState(identifier, kind: kind)) : Int(lists.indexByName[number])
        case .startOrEnd:
            let scope = scopeKey(isStart: isFirst)
            if let existing = startOrEndIndex(of: scope) {
                index = existing
            } else {
                index = try addState(StateDiagramStateRecord(identifierStart: 0, identifierEnd: 0,
                                                             writtenIdentifierIndex: StateDiagramStateRecord.startOrEndIdentifier, kind: isFirst ? .start : .end))
                addStartOrEnd(index, of: scope)
            }
        }
        if let innermost = openBodies.last, composites[innermost.compositeIndex].stateIndex != index {
            model.states[index].composite = Int32(innermost.compositeIndex)
            model.states[index].region = Int32(innermost.regionIndex)
        }
        return index
    }

    /// A state whose identifier is not a range of the text.
    private mutating func writtenState(_ identifier: String, kind: StateDiagramStateKind) -> StateDiagramStateRecord {
        model.identifiers.append(identifier)
        return StateDiagramStateRecord(identifierStart: 0, identifierEnd: 0, writtenIdentifierIndex: Int32(model.identifiers.count - 1), kind: kind)
    }

    private func startOrEndIndex(of scope: UInt64) -> Int? {
        guard startOrEndIndexByScope.isEmpty else { return startOrEndIndexByScope[scope] }
        for entry in startOrEndScopes where entry.key == scope { return entry.index }
        return nil
    }

    private mutating func addStartOrEnd(_ index: Int, of scope: UInt64) {
        guard startOrEndIndexByScope.isEmpty, startOrEndScopes.count < Self.listedScopeCount else {
            if startOrEndIndexByScope.isEmpty { for entry in startOrEndScopes { startOrEndIndexByScope[entry.key] = entry.index } }
            startOrEndIndexByScope[scope] = index
            return
        }
        if startOrEndScopes.isEmpty { startOrEndScopes.reserveCapacity(Self.listedScopeCount) }
        startOrEndScopes.append((scope, index))
    }

    /// The descriptions made room for when the first is read.
    private static let firstDescriptionCapacity = 16

    /// The scopes a list holds before a dictionary takes them.
    private static let listedScopeCount = 8

    /// Adds the state a name read for the first time names; the name's number is the next.
    private mutating func addNamedState(_ state: StateDiagramStateRecord) throws(MermaidDiagramReadError) -> Int {
        let index = try addState(state)
        lists.indexByName.append(Int32(index))
        return index
    }

    private mutating func addState(_ state: StateDiagramStateRecord) throws(MermaidDiagramReadError) -> Int {
        guard model.states.count + model.notes.count < limits.maximumNodeCount else { throw .tooManyNodes(limit: limits.maximumNodeCount) }
        model.states.append(state)
        lists.firstNumbers.append(-1)
        return model.states.count - 1
    }

    /// Adds a text written for a state. A state given a text is drawn as a box with it, whatever it was first declared
    /// as, as in Mermaid; an empty text is not kept.
    mutating func addDescription(_ description: StateDiagramReadText, in bytes: GraphDiagramBytes, toStateAt index: Int) {
        guard !description.isEmpty(in: bytes) else { return }
        if lists.secondNumbers.isEmpty {
            lists.secondNumbers.reserveCapacity(Self.firstDescriptionCapacity)
            model.descriptions.reserveCapacity(Self.firstDescriptionCapacity)
        }
        model.descriptions.append(kept(description))
        lists.secondNumbers.append(Int32(index))
        model.states[index].kind = .state
    }

    mutating func addTransition(from sourceIndex: Int, to targetIndex: Int, label: StateDiagramReadText?) throws(MermaidDiagramReadError) {
        guard model.transitions.count < limits.maximumEdgeCount else { throw .tooManyEdges(limit: limits.maximumEdgeCount) }
        model.transitions.append(StateDiagramTransitionRecord(source: Int32(sourceIndex), target: Int32(targetIndex), label: label.map { kept($0) } ?? .none))
    }

    mutating func addNote(toStateAt stateIndex: Int, side: StateDiagramNoteSide, text: StateDiagramReadText) throws(MermaidDiagramReadError) {
        guard model.states.count + model.notes.count < limits.maximumNodeCount else { throw .tooManyNodes(limit: limits.maximumNodeCount) }
        model.notes.append(StateDiagramNoteRecord(state: Int32(stateIndex), side: side, text: kept(text)))
    }

    /// The text as a record: its range, or its label kept among the model's.
    private mutating func kept(_ text: StateDiagramReadText) -> StateDiagramText {
        switch text {
        case .range(let range): StateDiagramText(range: range)
        case .label(let label): model.written(label)
        }
    }

    /// Opens a body of the composite state at `stateIndex`: the states named until it closes are inside it.
    mutating func openBody(ofStateAt stateIndex: Int) {
        let compositeIndex: Int
        if lists.firstNumbers[stateIndex] >= 0 {
            compositeIndex = Int(lists.firstNumbers[stateIndex])
        } else {
            compositeIndex = composites.count
            composites.append(StateDiagramComposite(stateIndex: stateIndex, parentCompositeIndex: openBodies.last?.compositeIndex))
            lists.firstNumbers[stateIndex] = Int32(compositeIndex)
        }
        openBodies.append(OpenBody(compositeIndex: compositeIndex, regionIndex: 0))
    }

    /// Closes the innermost body; false when none is open.
    mutating func closeBody() -> Bool {
        openBodies.popLast() != nil
    }

    /// `--` in a body: the states after it are in a concurrent region of their own. False at the top level.
    mutating func startRegion() -> Bool {
        guard let innermost = openBodies.last else { return false }
        openBodies[openBodies.count - 1].regionIndex += 1
        composites[innermost.compositeIndex].regionCount += 1
        return true
    }

    /// The identifier of the composite whose body is the innermost still open, or nil.
    var innermostOpenCompositeIdentifier: String? {
        openBodies.last.map { body in
            let state = model.states[composites[body.compositeIndex].stateIndex]
            if state.writtenIdentifierIndex >= 0 { return model.identifiers[Int(state.writtenIdentifierIndex)] }
            return model.text.string(MermaidTextRange(start: Int(state.identifierStart), end: Int(state.identifierEnd)))
        }
    }

    /// Sets the direction of the body being read, or of the top level.
    mutating func setDirection(_ direction: FlowchartDirection) {
        if let innermost = openBodies.last {
            composites[innermost.compositeIndex].direction = direction
        } else {
            self.direction = direction
        }
    }

    mutating func setAccessibilityTitle(_ title: String) {
        accessibilityTitle = title
    }

    mutating func setAccessibilityDescription(_ description: String) {
        accessibilityDescription = description
    }

    mutating func countUnappliedStatement() {
        unappliedStatementCount += 1
    }

    /// The diagram read, each state's descriptions put in a run in the order written; the working lists given back to
    /// `lists`. The records are moved out, not copied.
    mutating func finished(returning lists: inout GraphDiagramReadingLists) -> StateDiagram {
        StateDiagramDescriptionRuns.group(&model, describedStates: self.lists.secondNumbers)
        swap(&self.lists, &lists)
        var records = StateDiagramRecords(text: model.text)
        swap(&records, &model)
        return StateDiagram(direction: direction, model: StateDiagramModel(records), composites: composites, accessibilityTitle: accessibilityTitle,
                            accessibilityDescription: accessibilityDescription, unappliedStatementCount: unappliedStatementCount)
    }
}

/// Puts the descriptions read, in the order written, in one run a state, in the states' order.
enum StateDiagramDescriptionRuns {
    static func group(_ model: inout StateDiagramRecords, describedStates: [Int32]) {
        guard !describedStates.isEmpty else { return }
        for state in describedStates { model.states[Int(state)].descriptionCount += 1 }
        var next: Int32 = 0
        for state in model.states.indices {
            model.states[state].firstDescription = next
            next += model.states[state].descriptionCount
        }
        // Written in the states' order, as they mostly are, the descriptions are in their runs already.
        var isInOrder = true
        for index in 1..<describedStates.count where describedStates[index] < describedStates[index - 1] {
            isInOrder = false
            break
        }
        guard !isInOrder else { return }
        var placed = [StateDiagramText](repeating: .none, count: model.descriptions.count)
        var written = [Int32](repeating: 0, count: model.states.count)
        for (index, state) in describedStates.enumerated() {
            placed[Int(model.states[Int(state)].firstDescription + written[Int(state)])] = model.descriptions[index]
            written[Int(state)] += 1
        }
        model.descriptions = placed
    }
}
