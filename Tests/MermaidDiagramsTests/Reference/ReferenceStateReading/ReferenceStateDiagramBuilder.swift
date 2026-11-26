/**
 * File: ReferenceStateDiagramBuilder.swift
 * ----------------------------------------
 * Layer: Tests
 * Description: 0.7.0's state diagram reader, kept unchanged but for its names, and for its parts kept in lists of their
 *              own that the diagram's façade is made from, as the reference the reader on bytes is compared with
 *              (StateReadingEquivalenceTests).
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.2
 * Date: 26/11/2026
 */

@testable import MermaidDiagrams
/// Collects a state diagram as its statements are read: states by identifier, one start and one end per scope (the
/// top level, or a region of a composite's body), transitions and notes within the limits, and the composite bodies
/// open at each point, which take the states named inside them.
struct ReferenceStateDiagramBuilder {
    /// The diagram's parts as 0.7.0 kept them, in lists, which the façade the diagram now is is made from.
    private(set) var parts = ReferenceStateDiagramParts()
    var diagram: StateDiagram { parts.diagram }
    private let limits: MermaidDiagramLimits
    private var stateIndexByIdentifier: [String: Int] = [:]
    private var startOrEndIndexByScope: [StartOrEndScope: Int] = [:]
    private var compositeIndexByStateIndex: [Int: Int] = [:]
    /// The composite bodies open now, outermost first, with the region being read in each.
    private var openBodies: [OpenBody] = []

    /// Where a `[*]` is: the composite body and region it is written in (none at the top level), and whether it
    /// starts or ends the scope.
    private struct StartOrEndScope: Hashable {
        let compositeIndex: Int?
        let regionIndex: Int
        let isStart: Bool
    }

    private struct OpenBody {
        let compositeIndex: Int
        var regionIndex: Int
    }

    init(limits: MermaidDiagramLimits) {
        self.limits = limits
    }

    /// The index of the state a reference names. `[*]` is the start of the scope it is written in when `isFirst`
    /// (it leaves a transition, or stands alone), else its end. A state is added the first time it is named, as a
    /// box or with `kind`; naming it again keeps the kind it was first given, as Mermaid does.
    mutating func stateIndex(for reference: ReferenceStateDiagramStateReference, isFirst: Bool,
                             kind: StateDiagramStateKind = .state) throws(MermaidDiagramReadError) -> Int {
        let index: Int
        switch reference {
        case .named(let identifier):
            if let existing = stateIndexByIdentifier[identifier] {
                index = existing
            } else {
                index = try addState(identifier: identifier, kind: kind)
                stateIndexByIdentifier[identifier] = index
            }
        case .startOrEnd:
            let scope = StartOrEndScope(compositeIndex: openBodies.last?.compositeIndex, regionIndex: openBodies.last?.regionIndex ?? 0, isStart: isFirst)
            if let existing = startOrEndIndexByScope[scope] {
                index = existing
            } else {
                index = try addState(identifier: "[*]", kind: isFirst ? .start : .end)
                startOrEndIndexByScope[scope] = index
            }
        }
        if let innermost = openBodies.last, parts.composites[innermost.compositeIndex].stateIndex != index {
            parts.states[index].compositeIndex = innermost.compositeIndex
            parts.states[index].regionIndex = innermost.regionIndex
        }
        return index
    }

    private mutating func addState(identifier: String, kind: StateDiagramStateKind) throws(MermaidDiagramReadError) -> Int {
        guard parts.states.count + parts.notes.count < limits.maximumNodeCount else { throw .tooManyNodes(limit: limits.maximumNodeCount) }
        parts.states.append(StateDiagramState(identifier: identifier, kind: kind))
        return parts.states.count - 1
    }

    /// Adds the texts written for a state. A state given a text is drawn as a box with it, whatever it was first
    /// declared as, as in Mermaid.
    mutating func addDescriptions(_ descriptions: [DiagramLabel], toStateAt index: Int) {
        let written = descriptions.filter { description in !description.isEmpty }
        guard !written.isEmpty else { return }
        parts.states[index].descriptions.append(contentsOf: written)
        parts.states[index].kind = .state
    }

    mutating func addTransition(from sourceIndex: Int, to targetIndex: Int, label: DiagramLabel?) throws(MermaidDiagramReadError) {
        guard parts.transitions.count < limits.maximumEdgeCount else { throw .tooManyEdges(limit: limits.maximumEdgeCount) }
        parts.transitions.append(StateDiagramTransition(sourceIndex: sourceIndex, targetIndex: targetIndex, label: label))
    }

    mutating func addNote(toStateAt stateIndex: Int, side: StateDiagramNoteSide, text: DiagramLabel) throws(MermaidDiagramReadError) {
        guard parts.states.count + parts.notes.count < limits.maximumNodeCount else { throw .tooManyNodes(limit: limits.maximumNodeCount) }
        parts.notes.append(StateDiagramNote(stateIndex: stateIndex, side: side, text: text))
    }

    /// Opens a body of the composite state at `stateIndex`: the states named until it closes are inside it.
    mutating func openBody(ofStateAt stateIndex: Int) {
        let compositeIndex: Int
        if let existing = compositeIndexByStateIndex[stateIndex] {
            compositeIndex = existing
        } else {
            compositeIndex = parts.composites.count
            parts.composites.append(StateDiagramComposite(stateIndex: stateIndex, parentCompositeIndex: openBodies.last?.compositeIndex))
            compositeIndexByStateIndex[stateIndex] = compositeIndex
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
        parts.composites[innermost.compositeIndex].regionCount += 1
        return true
    }

    /// The identifier of the composite whose body is the innermost still open, or nil.
    var innermostOpenCompositeIdentifier: String? {
        openBodies.last.map { body in parts.states[parts.composites[body.compositeIndex].stateIndex].identifier }
    }

    /// Sets the direction of the body being read, or of the top level.
    mutating func setDirection(_ direction: FlowchartDirection) {
        if let innermost = openBodies.last {
            parts.composites[innermost.compositeIndex].direction = direction
        } else {
            parts.direction = direction
        }
    }

    mutating func setAccessibilityTitle(_ title: String) {
        parts.accessibilityTitle = title
    }

    mutating func setAccessibilityDescription(_ description: String) {
        parts.accessibilityDescription = description
    }

    mutating func countUnappliedStatement() {
        parts.unappliedStatementCount += 1
    }
}

/// A state diagram's parts in lists, as 0.7.0's `StateDiagram` held them, so that the reference reader builds them as it did.
struct ReferenceStateDiagramParts {
    var direction: FlowchartDirection = .topToBottom
    var states: [StateDiagramState] = []
    var transitions: [StateDiagramTransition] = []
    var notes: [StateDiagramNote] = []
    var composites: [StateDiagramComposite] = []
    var accessibilityTitle: String?
    var accessibilityDescription: String?
    var unappliedStatementCount = 0

    var diagram: StateDiagram {
        StateDiagram(direction: direction, states: states, transitions: transitions, notes: notes, composites: composites,
                     accessibilityTitle: accessibilityTitle, accessibilityDescription: accessibilityDescription, unappliedStatementCount: unappliedStatementCount)
    }
}
