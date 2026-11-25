/**
 * File: StateDiagramBuilder.swift
 * -------------------------------
 * Layer: Core
 * Description: Collects a state diagram as its statements are read on the text's bytes: states by their interned
 *              names, one start and one end per scope, transitions and notes within the limits, and the composite
 *              bodies open at each point.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

/// Collects a state diagram as its statements are read: states by identifier, one start and one end per scope (the
/// top level, or a region of a composite's body), transitions and notes within the limits, and the composite bodies
/// open at each point, which take the states named inside them.
struct StateDiagramBuilder {
    private(set) var diagram = StateDiagram()
    private let limits: MermaidDiagramLimits
    /// The names read, interned; the state each names by its number.
    private var names: GraphDiagramNameTable
    private var stateIndexByName: [Int32] = []
    /// The `[*]` states by their scope (`scopeKey`): a few in a list, searched in order, and past them a dictionary.
    private var startOrEndScopes: [(key: UInt64, index: Int)] = []
    private var startOrEndIndexByScope: [UInt64: Int] = [:]
    /// The composite of each state that has a body, by the state's index, -1 for none.
    private var compositeIndexByStateIndex: [Int32] = []
    /// The composite bodies open now, outermost first, with the region being read in each.
    private var openBodies: [OpenBody] = []

    private struct OpenBody {
        let compositeIndex: Int
        var regionIndex: Int
    }

    /// - Parameter byteCount: The length of the text, which bounds what it can name: room is made for a state and a
    ///   transition every `bytesPerStatement` bytes, within the limits, so that most diagrams grow no list.
    init(limits: MermaidDiagramLimits, isASCII: Bool, byteCount: Int) {
        self.limits = limits
        names = GraphDiagramNameTable(isASCII: isASCII)
        let statementCount = min(byteCount / Self.bytesPerStatement + 4, limits.maximumNodeCount, Self.mostReserved)
        names.reserveCapacity(statementCount)
        stateIndexByName.reserveCapacity(statementCount)
        compositeIndexByStateIndex.reserveCapacity(statementCount)
        diagram.states.reserveCapacity(statementCount)
        diagram.transitions.reserveCapacity(min(byteCount / Self.bytesPerStatement + 4, limits.maximumEdgeCount, Self.mostReserved))
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
            let (number, isNew) = names.intern(bytes.buffer, range)
            index = isNew ? try addNamedState(identifier: bytes.text(range), kind: kind) : Int(stateIndexByName[number])
        case .written(let identifier):
            let (number, isNew) = names.intern(identifier)
            index = isNew ? try addNamedState(identifier: identifier, kind: kind) : Int(stateIndexByName[number])
        case .startOrEnd:
            let scope = scopeKey(isStart: isFirst)
            if let existing = startOrEndIndex(of: scope) {
                index = existing
            } else {
                index = try addState(identifier: "[*]", kind: isFirst ? .start : .end)
                addStartOrEnd(index, of: scope)
            }
        }
        if let innermost = openBodies.last, diagram.composites[innermost.compositeIndex].stateIndex != index {
            diagram.states[index].compositeIndex = innermost.compositeIndex
            diagram.states[index].regionIndex = innermost.regionIndex
        }
        return index
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
        startOrEndScopes.append((scope, index))
    }

    /// The scopes a list holds before a dictionary takes them.
    private static let listedScopeCount = 8

    /// Adds the state a name read for the first time names; the name's number is the next.
    private mutating func addNamedState(identifier: String, kind: StateDiagramStateKind) throws(MermaidDiagramReadError) -> Int {
        let index = try addState(identifier: identifier, kind: kind)
        stateIndexByName.append(Int32(index))
        return index
    }

    private mutating func addState(identifier: String, kind: StateDiagramStateKind) throws(MermaidDiagramReadError) -> Int {
        guard diagram.states.count + diagram.notes.count < limits.maximumNodeCount else { throw .tooManyNodes(limit: limits.maximumNodeCount) }
        diagram.states.append(StateDiagramState(identifier: identifier, kind: kind))
        compositeIndexByStateIndex.append(-1)
        return diagram.states.count - 1
    }

    /// Adds the texts written for a state. A state given a text is drawn as a box with it, whatever it was first
    /// declared as, as in Mermaid.
    mutating func addDescription(_ description: DiagramLabel, toStateAt index: Int) {
        guard !description.isEmpty else { return }
        diagram.states[index].descriptions.append(description)
        diagram.states[index].kind = .state
    }

    mutating func addDescriptions(_ descriptions: [DiagramLabel], toStateAt index: Int) {
        let written = descriptions.filter { description in !description.isEmpty }
        guard !written.isEmpty else { return }
        diagram.states[index].descriptions.append(contentsOf: written)
        diagram.states[index].kind = .state
    }

    mutating func addTransition(from sourceIndex: Int, to targetIndex: Int, label: DiagramLabel?) throws(MermaidDiagramReadError) {
        guard diagram.transitions.count < limits.maximumEdgeCount else { throw .tooManyEdges(limit: limits.maximumEdgeCount) }
        diagram.transitions.append(StateDiagramTransition(sourceIndex: sourceIndex, targetIndex: targetIndex, label: label))
    }

    mutating func addNote(toStateAt stateIndex: Int, side: StateDiagramNoteSide, text: DiagramLabel) throws(MermaidDiagramReadError) {
        guard diagram.states.count + diagram.notes.count < limits.maximumNodeCount else { throw .tooManyNodes(limit: limits.maximumNodeCount) }
        diagram.notes.append(StateDiagramNote(stateIndex: stateIndex, side: side, text: text))
    }

    /// Opens a body of the composite state at `stateIndex`: the states named until it closes are inside it.
    mutating func openBody(ofStateAt stateIndex: Int) {
        let compositeIndex: Int
        if compositeIndexByStateIndex[stateIndex] >= 0 {
            compositeIndex = Int(compositeIndexByStateIndex[stateIndex])
        } else {
            compositeIndex = diagram.composites.count
            diagram.composites.append(StateDiagramComposite(stateIndex: stateIndex, parentCompositeIndex: openBodies.last?.compositeIndex))
            compositeIndexByStateIndex[stateIndex] = Int32(compositeIndex)
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
        diagram.composites[innermost.compositeIndex].regionCount += 1
        return true
    }

    /// The identifier of the composite whose body is the innermost still open, or nil.
    var innermostOpenCompositeIdentifier: String? {
        openBodies.last.map { body in diagram.states[diagram.composites[body.compositeIndex].stateIndex].identifier }
    }

    /// Sets the direction of the body being read, or of the top level.
    mutating func setDirection(_ direction: FlowchartDirection) {
        if let innermost = openBodies.last {
            diagram.composites[innermost.compositeIndex].direction = direction
        } else {
            diagram.direction = direction
        }
    }

    mutating func setAccessibilityTitle(_ title: String) {
        diagram.accessibilityTitle = title
    }

    mutating func setAccessibilityDescription(_ description: String) {
        diagram.accessibilityDescription = description
    }

    mutating func countUnappliedStatement() {
        diagram.unappliedStatementCount += 1
    }
}
